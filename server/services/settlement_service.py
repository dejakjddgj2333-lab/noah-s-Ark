"""结算引擎 (Phase 5, 需求文档第二/五/八节).

四套返还节奏, 按订单生效时间精确到分钟:
- daily=每满24小时; period_7d=每隔7天; period_30d=每隔30天; expiry=到期一次性

精度 (第五节): 每个结算期收益先各自截断至 2 位小数 (不四舍五入), 再以已截断收益
按各上级比例计算佣金并各自截断; 禁止跨期/跨用户合并后截断.

到期顺序 (第二节): 结最后一期收益及佣金 → 返还本金至本金账户 → 订单完结移除持仓
→ 个人 VIP / 团队等级由动态计算自动重算, 无需额外处理.

幂等 (第八节): 结算流水 (order_id, period_no) 唯一、佣金流水 (settlement_id, receiver_id)
唯一; 入账全部使用原子 UPDATE, 与购买扣款并发互不丢失更新; 引擎重跑/重启安全.

⚠️ Phase 0.1 未拍板项: 结算延迟时的历史团队等级还原. 当前实现按"实际结算时点"取等级
(引擎正常每分钟运行, 延迟 ≈ 一轮间隔); 若要求按"应结算时点"还原历史等级需补快照机制.
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime, timedelta
from decimal import Decimal

from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkAccount
from models.hk import utc_now
from models.order import HkOrder
from models.settlement import HkCommissionRecord, HkSettlementRecord
from services import level_log_service, team_service
from services.account_service import get_or_create_account
from services.balance_log_service import log as log_balance
from services.team_service import truncate_2dp

log = logging.getLogger("settlement")

# 返还节奏 → 每期天数 (expiry 单独处理: 一期 = 整个周期)
PERIOD_DAYS = {"daily": 1, "period_7d": 7, "period_30d": 30}


def period_days(order: HkOrder) -> int:
    if order.return_method == "expiry":
        return order.duration_days
    return PERIOD_DAYS[order.return_method]


def total_periods(order: HkOrder) -> int:
    if order.return_method == "expiry":
        return 1
    return max(1, order.duration_days // PERIOD_DAYS[order.return_method])


def period_income(order: HkOrder, days: int) -> Decimal:
    """本期收益 = 本金 × 订单锁定实际日收益率 × 天数, 截断 2 位小数."""
    rate = order.actual_daily_rate
    if rate is None:  # Phase 1 旧订单无锁定加成
        rate = Decimal(order.base_daily_rate)
    return truncate_2dp(Decimal(order.amount) * rate * days)


def first_settle_at(effective_at: datetime, duration_days: int, return_method: str) -> datetime:
    """首期应结算时点 = 生效时间 + 一期天数."""
    if return_method == "expiry":
        days = duration_days
    else:
        days = PERIOD_DAYS[return_method]
    return effective_at + timedelta(days=days)


async def _credit(
    db: AsyncSession,
    user_id: int,
    amount: Decimal,
    field: str,
    change_type: str,
    ref_type: str,
    ref_id: int,
) -> None:
    """原子入账 (income_balance / principal_balance) 并留资金明细, 与购买扣款并发不丢更新."""
    try:
        await get_or_create_account(db, user_id)
    except IntegrityError:
        pass  # 并发开户, 行已存在
    col = getattr(HkAccount, field)
    await db.execute(
        update(HkAccount)
        .where(HkAccount.user_id == user_id)
        .values(**{field: col + amount})
    )
    await db.flush()
    account = "income" if field == "income_balance" else "principal"
    await log_balance(
        db, user_id, account, change_type, amount,
        ref_type=ref_type, ref_id=ref_id,
    )


async def _settle_commissions(
    db: AsyncSession, order: HkOrder, record: HkSettlementRecord, income: Decimal
) -> None:
    """按接收人**应结算时点**的团队等级 + 代数结算佣金 (无资格份额不发放, 不越级转移)."""
    for gen, receiver_id in await team_service.uplines(db, order.user_id):
        members, holding = await team_service.team_stats(db, receiver_id)
        lv = team_service.team_level(members, holding)
        rate = team_service.rebate_rate(lv, gen)
        if rate is None:
            continue
        amount = team_service.commission(income, lv, gen)
        if amount is None or amount <= 0:
            continue
        exists = (
            await db.execute(
                select(HkCommissionRecord.id).where(
                    HkCommissionRecord.settlement_id == record.id,
                    HkCommissionRecord.receiver_id == receiver_id,
                )
            )
        ).scalar_one_or_none()
        if exists is not None:
            continue
        db.add(
            HkCommissionRecord(
                settlement_id=record.id,
                order_id=order.id,
                buyer_id=order.user_id,
                receiver_id=receiver_id,
                gen=gen,
                receiver_team_level=lv,  # 结算依据留存 (文档第八节)
                rate=rate,
                amount=amount,
            )
        )
        await db.flush()
        await _credit(db, receiver_id, amount, "income_balance",
                      "commission", "commission", record.id)


async def settle_order(db: AsyncSession, order: HkOrder, now: datetime) -> int:
    """结算一笔订单所有到期期数. 调用方 commit; 返回新结算期数."""
    pd = period_days(order)
    total = total_periods(order)
    if order.next_settle_at is None:  # 兼容 Phase 1 旧订单
        order.next_settle_at = order.effective_at + timedelta(days=pd)
        if order.next_settle_at > now:
            await db.flush()
            return 0

    settled = 0
    while order.settled_periods < total and order.status == "effective":
        period_no = order.settled_periods + 1
        due_at = order.effective_at + timedelta(days=pd * period_no)
        if due_at > now:
            break
        exists = (
            await db.execute(
                select(HkSettlementRecord.id).where(
                    HkSettlementRecord.order_id == order.id,
                    HkSettlementRecord.period_no == period_no,
                )
            )
        ).scalar_one_or_none()
        if exists is None:
            income = period_income(order, pd)
            record = HkSettlementRecord(
                order_id=order.id,
                user_id=order.user_id,
                period_no=period_no,
                period_days=pd,
                income_amount=income,
            )
            db.add(record)
            await db.flush()
            await _credit(db, order.user_id, income, "income_balance",
                          "income_settled", "settlement", record.id)
            await _settle_commissions(db, order, record, income)
            settled += 1
        order.settled_periods = period_no
        if period_no >= total:
            # 到期: 返本入本金账户 + 完结移除持仓 (收益/佣金已在上方同事务结算)
            stl_id = record.id if exists is None else exists
            await _credit(db, order.user_id, Decimal(order.amount), "principal_balance",
                          "principal_returned", "settlement", stl_id)
            await db.execute(
                update(HkSettlementRecord)
                .where(
                    HkSettlementRecord.order_id == order.id,
                    HkSettlementRecord.period_no == period_no,
                )
                .values(principal_amount=Decimal(order.amount))
            )
            order.status = "finished"
            order.next_settle_at = None
            # 等级变动日志: 到期移除持仓, 记录本人与上级们的最新等级 (自动降级留痕)
            await level_log_service.record_event(db, order.user_id, source="settle")
        else:
            order.next_settle_at = order.effective_at + timedelta(days=pd * (period_no + 1))
    await db.flush()
    return settled


async def settle_due(
    db: AsyncSession, now: datetime | None = None, limit: int = 200
) -> int:
    """结算所有到期待结算订单 (引擎每轮调用). 返回新结算期数."""
    now = now or utc_now()
    result = await db.execute(
        select(HkOrder)
        .where(
            HkOrder.status == "effective",
            HkOrder.next_settle_at.is_not(None),
            HkOrder.next_settle_at <= now,
        )
        .order_by(HkOrder.next_settle_at.asc())
        .limit(limit)
    )
    total = 0
    for order in result.scalars():
        total += await settle_order(db, order, now)
    return total


async def run_forever() -> None:
    """结算循环: 每分钟扫一轮到期订单."""
    from config import config
    from database import SessionLocal

    while True:
        try:
            async with SessionLocal() as db:
                settled = await settle_due(db)
                await db.commit()
                if settled:
                    log.info("结算完成 %d 期", settled)
        except Exception:
            log.exception("结算循环异常, 5 秒后重试")
            await asyncio.sleep(5)
        await asyncio.sleep(config.settlement_interval_sec)
