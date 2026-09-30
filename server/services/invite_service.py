"""邀请绑定服务.

规则 (需求文档 V0.7 第一节):
- 每名用户唯一专属邀请码; 上下级关系一旦绑定永久固定, 不能更换.
- 禁止自邀、重复绑定、循环邀请关系.
- 补绑资格: 本人无上级, 且本人及所有层级下级均无成功购买记录.
  检查覆盖全部层级, 不受三代返佣范围限制; 任何一代有记录即永久拒绝.
"""
from __future__ import annotations

import random
import string

from fastapi import HTTPException, status
from sqlalchemy import select, text
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import utc_now
from models.invite import HkInvite
from models.order import HkOrder  # noqa: F401 注册 HkBase 元数据, 建表用

_CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # 去除易混淆字符
_CODE_LEN = 8

# 本人 + 所有层级下级的成功购买检查 (递归 CTE; sqlite 与 postgres 均支持)
_DOWNLINE_PURCHASE_SQL = text(
    """
    WITH RECURSIVE downline AS (
        SELECT :uid AS user_id
        UNION
        SELECT i.user_id
        FROM hk_invites i
        JOIN downline d ON i.inviter_id = d.user_id
    )
    SELECT COUNT(*) AS n
    FROM hk_orders o
    JOIN downline dl ON o.user_id = dl.user_id
    WHERE o.status = 'effective'
    """
)

# 从 start_id 的上级出发沿邀请链向上, 检查是否可达 target_id (循环检测)
_CYCLE_SQL = text(
    """
    WITH RECURSIVE upchain AS (
        SELECT inviter_id FROM hk_invites WHERE user_id = :start_id
        UNION
        SELECT i.inviter_id
        FROM hk_invites i
        JOIN upchain u ON i.user_id = u.inviter_id
        WHERE u.inviter_id IS NOT NULL
    )
    SELECT COUNT(*) AS n FROM upchain WHERE inviter_id = :target_id
    """
)


async def _generate_code(db: AsyncSession) -> str:
    for _ in range(20):
        code = "".join(random.choices(_CODE_ALPHABET, k=_CODE_LEN))
        exists = await db.execute(
            select(HkInvite.user_id).where(HkInvite.invite_code == code)
        )
        if exists.first() is None:
            return code
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="邀请码生成失败, 请重试",
    )


async def get_or_create_invite(db: AsyncSession, user_id: int) -> HkInvite:
    """取用户邀请记录, 老用户无记录时自动补发邀请码."""
    result = await db.execute(
        select(HkInvite).where(HkInvite.user_id == user_id)
    )
    invite = result.scalar_one_or_none()
    if invite is not None:
        return invite
    invite = HkInvite(user_id=user_id, invite_code=await _generate_code(db))
    db.add(invite)
    await db.flush()
    return invite


async def has_any_purchase(db: AsyncSession, user_id: int) -> bool:
    """本人及所有层级下级是否存在成功购买记录 (不限三代, 逐级查到底)."""
    result = await db.execute(_DOWNLINE_PURCHASE_SQL, {"uid": user_id})
    return result.scalar_one() > 0


async def bind_block_reason(db: AsyncSession, user_id: int) -> str | None:
    """返回补绑拦截原因; None 表示可补绑. 仅用于展示, 真正校验在 bind_inviter."""
    invite = await get_or_create_invite(db, user_id)
    if invite.inviter_id is not None:
        return None  # 已绑定, 不属于补绑场景
    if await has_any_purchase(db, user_id):
        return "本人或任意层级下级已有成功购买记录, 不可补填邀请码"
    return None


async def bind_inviter(
    db: AsyncSession, user_id: int, invite_code: str
) -> HkInvite:
    """绑定上级. 全部校验通过才写入; 调用方负责 commit.

    校验顺序: 邀请码有效 → 非自邀 → 未绑定过 → 非循环 → 全层级无成功购买.
    """
    code = invite_code.strip().upper()
    result = await db.execute(
        select(HkInvite).where(HkInvite.invite_code == code)
    )
    inviter = result.scalar_one_or_none()
    if inviter is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="邀请码无效"
        )
    if inviter.user_id == user_id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="不能绑定自己为上级"
        )
    mine = await get_or_create_invite(db, user_id)
    if mine.inviter_id is not None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="已绑定上级, 绑定关系永久固定不可更换",
        )
    result = await db.execute(
        _CYCLE_SQL, {"start_id": inviter.user_id, "target_id": user_id}
    )
    if result.scalar_one() > 0:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="无效的邀请关系: 目标上级属于本人的下级链",
        )
    if await has_any_purchase(db, user_id):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="本人或任意层级下级已有成功购买记录, 不可绑定上级",
        )
    mine.inviter_id = inviter.user_id
    mine.bound_at = utc_now()
    await db.flush()
    return mine
