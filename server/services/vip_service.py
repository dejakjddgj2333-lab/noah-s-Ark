"""个人 VIP 等级服务 (Phase 3, 需求文档第三节).

定级依据: 本人当前全部**仍有效**产品持仓金额合计:
- 仍有效 = 订单 status='effective' 且 (未到期 或 到期时间为空);
- 产品到期移除持仓后金额不足立即降级 —— 采用动态计算, 天然即时重算, 不存储等级列;
- 订单锁定: 购买瞬间快照 vip_level + lock_bonus_rate, 之后本人升降级均不改变已生效订单
  (实际每日收益率 = 基础每日收益率 × (1 + 锁定加成), 结算引擎 Phase 5 使用).
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import utc_now
from models.order import HkOrder

# (等级, 有效持仓门槛 USDT, 基础收益加成) —— 需求文档 V0.7 第三节, 门槛与加成均已确认
VIP_TABLE: tuple[tuple[int, Decimal, Decimal], ...] = (
    (10, Decimal("200000"), Decimal("0.24")),
    (9, Decimal("150000"), Decimal("0.21")),
    (8, Decimal("100000"), Decimal("0.18")),
    (7, Decimal("70000"), Decimal("0.15")),
    (6, Decimal("40000"), Decimal("0.12")),
    (5, Decimal("20000"), Decimal("0.09")),
    (4, Decimal("10000"), Decimal("0.08")),
    (3, Decimal("5000"), Decimal("0.07")),
    (2, Decimal("3000"), Decimal("0.06")),
    (1, Decimal("1000"), Decimal("0.05")),
    (0, Decimal("0"), Decimal("0")),
)


def level_for_holding(holding: Decimal) -> int:
    """按有效持仓取最高符合等级 (达到或高于门槛即符合)."""
    for level, threshold, _bonus in VIP_TABLE:
        if holding >= threshold:
            return level
    return 0


def bonus_for_level(level: int) -> Decimal:
    for lv, _threshold, bonus in VIP_TABLE:
        if lv == level:
            return bonus
    return Decimal("0")


async def effective_holding(
    db: AsyncSession, user_id: int, now: datetime | None = None
) -> Decimal:
    """仍有效持仓合计: 生效中且未到期 (NULL 到期时间视为仍有效, 兼容 Phase 1 旧数据)."""
    now = now or utc_now()
    result = await db.execute(
        select(func.coalesce(func.sum(HkOrder.amount), 0)).where(
            HkOrder.user_id == user_id,
            HkOrder.status == "effective",
            or_(HkOrder.expires_at.is_(None), HkOrder.expires_at > now),
        )
    )
    return Decimal(result.scalar_one())


async def current_vip(db: AsyncSession, user_id: int) -> dict:
    """当前 VIP: 等级 / 有效持仓 / 加成 / 距下一级."""
    holding = await effective_holding(db, user_id)
    level = level_for_holding(holding)
    bonus = bonus_for_level(level)
    next_level = next_threshold = gap = None
    if level < 10:
        nl, nt, _ = next(r for r in VIP_TABLE if r[0] == level + 1)
        next_level, next_threshold = nl, nt
        gap = max(nt - holding, Decimal(0))
    return {
        "vip_level": level,
        "effective_holding": holding,
        "bonus_rate": bonus,
        "next_level": next_level,
        "next_threshold": next_threshold,
        "gap_to_next": gap,
    }
