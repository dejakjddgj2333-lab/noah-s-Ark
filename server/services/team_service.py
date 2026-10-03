"""团队等级与三代返佣服务 (Phase 4, 需求文档第四节).

口径 (仅统计下级第一、二、三代, 不含本人及第四代以后):
- 有效成员: 同一成员当前全部有效产品合计 ≥300 USDT 计 1 人 (多笔合并, 最多计 1 人);
  不足 300 不计人数, 但其有效持仓金额仍计入团队总金额;
- 团队等级: 人数与金额**同时达标**, 取同时满足的最高等级; 不满足当前等级立即降级;
- 佣金比例: 按接收人**本次结算时点**的团队等级 + 与购买用户的代数选取;
  0 级仅第一代 5%; 1 级一/二代; 2 级起三代; 无资格份额不发放、不越级转移; 无上级不发放.

等级定级采用动态计算: 成员产品到期/新购即时反映, 天然满足"立即降级".
应结算时点的等级快照记录属 Phase 5 结算引擎 (4.3).
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal, ROUND_DOWN

from sqlalchemy import func, or_, select, text
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import utc_now
from models.invite import HkInvite  # noqa: F401 注册元数据
from models.order import HkOrder

# 有效成员持仓门槛 (文档第四节)
EFFECTIVE_MEMBER_HOLDING = Decimal("300")

# (等级, 三代内有效人数≥, 三代内有效持仓≥USDT, 第一代比例, 第二代比例, 第三代比例)
# —— 需求文档 V0.7 第四节, 门槛与比例均已确认; 0 级: 未达 1 级, 仅一代 5%
TEAM_TABLE: tuple[tuple[int, int | None, int | None, str, str, str], ...] = (
    (10, 1000, 1200000, "0.122", "0.066", "0.056"),
    (9, 600, 720000, "0.106", "0.058", "0.048"),
    (8, 350, 420000, "0.092", "0.051", "0.041"),
    (7, 200, 240000, "0.08", "0.045", "0.035"),
    (6, 120, 144000, "0.07", "0.04", "0.03"),
    (5, 70, 84000, "0.062", "0.036", "0.026"),
    (4, 40, 48000, "0.056", "0.033", "0.023"),
    (3, 20, 24000, "0.052", "0.031", "0.021"),
    (2, 10, 12000, "0.05", "0.03", "0.02"),
    (1, 5, 6000, "0.05", "0.03", "0"),
    (0, None, None, "0.05", "0", "0"),
)


def truncate_2dp(value: Decimal) -> Decimal:
    """金额精度规则 (文档第五节): 直接截去后续小数, 不四舍五入."""
    return value.quantize(Decimal("0.01"), rounding=ROUND_DOWN)


def team_level(member_count: int, total_holding: Decimal) -> int:
    """人数与金额同时达标的最高等级; 都不满足为 0 级."""
    for level, min_members, min_holding, *_ in TEAM_TABLE:
        if level == 0:
            return 0
        if member_count >= min_members and total_holding >= Decimal(min_holding):
            return level
    return 0


def rebate_rate(team_lv: int, gen: int) -> Decimal | None:
    """接收人适用比例. gen∈{1,2,3}; 比例为空/0 表示该份额不发放 (不越级转移)."""
    if gen not in (1, 2, 3):
        return None
    row = next((r for r in TEAM_TABLE if r[0] == team_lv), TEAM_TABLE[-1])
    rate = Decimal(row[3 + gen - 1])
    return rate if rate > 0 else None


def commission(income_2dp: Decimal, team_lv: int, gen: int) -> Decimal | None:
    """单笔佣金 = 本期已截断收益 × 适用比例, 各自截断至 2 位小数 (文档第五节).
    无资格 (比例为 0/空) 返回 None, 不发放."""
    rate = rebate_rate(team_lv, gen)
    if rate is None:
        return None
    return truncate_2dp(income_2dp * rate)


# 三代下线 (递归 CTE, sqlite/postgres 通用, 深度≤3)
_DOWNLINE_3GEN_SQL = text(
    """
    WITH RECURSIVE dl AS (
        SELECT i.user_id AS user_id, 1 AS depth
        FROM hk_invites i WHERE i.inviter_id = :uid
        UNION ALL
        SELECT i.user_id, dl.depth + 1
        FROM hk_invites i JOIN dl ON i.inviter_id = dl.user_id
        WHERE dl.depth < 3
    )
    SELECT user_id FROM dl
    """
)


async def three_gen_downline(db: AsyncSession, user_id: int) -> list[int]:
    """直系+二代+三代下线用户 id (不含本人, 不含第四代及更深)."""
    result = await db.execute(_DOWNLINE_3GEN_SQL, {"uid": user_id})
    return [row[0] for row in result.all()]


async def uplines(db: AsyncSession, user_id: int, max_gen: int = 3) -> list[tuple[int, int]]:
    """上级链 [(代数, 用户id)], 一代=直接上级, 最多 max_gen 代."""
    chain: list[tuple[int, int]] = []
    current = user_id
    for gen in range(1, max_gen + 1):
        result = await db.execute(
            select(HkInvite.inviter_id).where(HkInvite.user_id == current)
        )
        inviter = result.scalar_one_or_none()
        if inviter is None:
            break
        chain.append((gen, inviter))
        current = inviter
    return chain


async def team_stats(db: AsyncSession, user_id: int) -> tuple[int, Decimal]:
    """(三代有效成员数, 三代有效持仓总额)."""
    member_ids = await three_gen_downline(db, user_id)
    if not member_ids:
        return 0, Decimal(0)
    now = utc_now()
    result = await db.execute(
        select(HkOrder.user_id, func.coalesce(func.sum(HkOrder.amount), 0))
        .where(
            HkOrder.user_id.in_(member_ids),
            HkOrder.status == "effective",
            or_(HkOrder.expires_at.is_(None), HkOrder.expires_at > now),
        )
        .group_by(HkOrder.user_id)
    )
    rows = result.all()
    member_count = sum(1 for _uid, holding in rows if Decimal(holding) >= EFFECTIVE_MEMBER_HOLDING)
    total_holding = sum((Decimal(h) for _u, h in rows), Decimal(0))
    return member_count, total_holding


async def current_team(db: AsyncSession, user_id: int) -> dict:
    """我的团队: 三代有效人数 / 有效持仓 / 团队等级 / 返佣比例 / 距下一级两项差额 (文档 8.1)."""
    member_count, total_holding = await team_stats(db, user_id)
    level = team_level(member_count, total_holding)
    rates = {
        f"gen{g}_rate": (str(r) if (r := rebate_rate(level, g)) is not None else None)
        for g in (1, 2, 3)
    }
    out = {
        "team_level": level,
        "member_count": member_count,
        "total_holding": total_holding,
        **rates,
        "next_level": None,
        "next_member_gap": None,
        "next_holding_gap": None,
    }
    if level < 10:
        nl, n_members, n_holding, *_ = next(r for r in TEAM_TABLE if r[0] == level + 1)
        out["next_level"] = nl
        out["next_member_gap"] = max(n_members - member_count, 0)
        out["next_holding_gap"] = max(Decimal(n_holding) - total_holding, Decimal(0))
    return out
