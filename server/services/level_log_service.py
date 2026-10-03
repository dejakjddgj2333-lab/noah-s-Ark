"""等级变动日志服务: 在事件点记录 VIP/团队等级 (有变化才写, 只增不改)."""
from __future__ import annotations

from decimal import Decimal

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from models.level_log import HkLevelLog  # noqa: F401 注册元数据
from services import team_service, vip_service


async def record(
    db: AsyncSession,
    user_id: int,
    kind: str,
    level: int,
    *,
    holding: Decimal | None = None,
    member_count: int | None = None,
    source: str = "",
) -> HkLevelLog | None:
    """等级与上一条日志不同才写入; 返回新日志或 None."""
    last = (
        await db.execute(
            select(HkLevelLog)
            .where(HkLevelLog.user_id == user_id, HkLevelLog.kind == kind)
            .order_by(desc(HkLevelLog.id))
            .limit(1)
        )
    ).scalar_one_or_none()
    if last is not None and last.level == level:
        return None
    log = HkLevelLog(
        user_id=user_id,
        kind=kind,
        level=level,
        holding=holding,
        member_count=member_count,
        source=source,
    )
    db.add(log)
    await db.flush()
    return log


async def record_current(db: AsyncSession, user_id: int, source: str) -> None:
    """事件后记录用户当前 VIP 与团队等级 (购买/到期结算后调用, 同事务)."""
    vip = await vip_service.current_vip(db, user_id)
    await record(
        db, user_id, "vip", vip["vip_level"],
        holding=vip["effective_holding"], source=source,
    )
    members, holding = await team_service.team_stats(db, user_id)
    await record(
        db, user_id, "team", team_service.team_level(members, holding),
        holding=holding, member_count=members, source=source,
    )


async def record_event(db: AsyncSession, user_id: int, source: str) -> None:
    """购买/到期等持仓变动事件后: 记录本人 VIP+团队, 及三代上级的团队等级."""
    await record_current(db, user_id, source)
    for _gen, up_id in await team_service.uplines(db, user_id):
        members, holding = await team_service.team_stats(db, up_id)
        await record(
            db, up_id, "team", team_service.team_level(members, holding),
            holding=holding, member_count=members, source=source,
        )


async def list_logs(
    db: AsyncSession, user_id: int, kind: str | None = None, limit: int = 200
) -> list[HkLevelLog]:
    """我的等级变动日志, 最新在前."""
    q = select(HkLevelLog).where(HkLevelLog.user_id == user_id)
    if kind:
        q = q.where(HkLevelLog.kind == kind)
    result = await db.execute(q.order_by(desc(HkLevelLog.id)).limit(limit))
    return list(result.scalars().all())
