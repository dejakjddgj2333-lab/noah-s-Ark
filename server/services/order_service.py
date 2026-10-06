"""订单服务: 购买下单 (Phase 2.3-2.5).

拍板结论 (2026-10-02, 用户): "购买了就成功" —— 本金扣款成功即 status='effective',
无支付/审核等待。订单创建与余额扣减在同一事务内完成。
"""
from __future__ import annotations

from datetime import timedelta
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import desc, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkAccount  # noqa: F401 注册元数据
from models.hk import HkUser, utc_now
from models.order import HkOrder
from models.product import HkProduct
from services import concurrency, level_log_service, settlement_service, team_service, vip_service
from services.account_service import get_or_create_account
from services.balance_log_service import log as log_balance

RULE_VERSION = "v0.7"


async def create_order(
    db: AsyncSession, user: HkUser, product_id: int, amount: Decimal,
    idempotency_key: str | None = None,
) -> HkOrder:
    """下单购买: 与补绑互斥 (防"检查等级/资格"与"写入绑定"竞态绕过, 文档第八节)."""
    async with concurrency.bind_purchase_lock:
        return await _create_order_locked(
            db, user, product_id, amount, idempotency_key
        )


async def _create_order_locked(
    db: AsyncSession, user: HkUser, product_id: int, amount: Decimal,
    idempotency_key: str | None = None,
) -> HkOrder:
    """下单购买: 校验产品/金额/等级/余额后扣减本金并生成生效订单.

    调用方负责 commit. 行锁防并发超扣 (sqlite 事务串行天然安全).
    idempotency_key: 可选幂等键 (客户端生成), 双击/超时重试/脚本重放
    只扣一次款, 直接返回首次订单.
    """
    if idempotency_key:
        existing = (
            await db.execute(
                select(HkOrder).where(
                    HkOrder.user_id == user.id,
                    HkOrder.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing  # 幂等: 同键重试返回首次订单, 不重复扣款

    result = await db.execute(
        select(HkProduct)
        .where(HkProduct.id == product_id)
        .with_for_update()
    )
    product = result.scalar_one_or_none()
    if product is None or product.status != "published":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "产品不存在或已下架")

    amount = Decimal(amount)
    if not amount.is_finite() or amount <= 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "购买金额必须为正数")
    if amount != amount.quantize(Decimal("0.01")):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "购买金额最多两位小数")
    if amount < Decimal(product.min_amount) or amount > Decimal(product.max_amount):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"购买金额须在 {product.min_amount} ~ {product.max_amount} USDT 之间",
        )

    # 生效前个人VIP: 按"本笔购买之前"的仍有效持仓定级 (文档: 本笔购买触发的升级
    # 不能用于满足该笔订单自身门槛, 也不能锁定到本笔订单)
    holding = await vip_service.effective_holding(db, user.id)
    user_vip = vip_service.level_for_holding(holding)
    # 生效前团队等级: 同样按本笔购买之前的三代统计定级
    _members, _team_holding = await team_service.team_stats(db, user.id)
    user_team = team_service.team_level(_members, _team_holding)
    if product.vip_level_req is not None and user_vip < product.vip_level_req:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, f"需要个人 VIP{product.vip_level_req} 及以上"
        )
    if product.team_level_req is not None and user_team < product.team_level_req:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            f"需要团队等级 {product.team_level_req} 及以上",
        )

    now = utc_now()
    order = HkOrder(
        user_id=user.id,
        product_id=str(product.id),
        amount=amount,
        status="effective",  # 拍板: 扣款成功即生效
        effective_at=now,
        product_name=product.name,
        base_daily_rate=product.base_daily_rate,
        duration_days=product.duration_days,
        return_method=product.return_method,
        vip_level=user_vip,
        team_level=user_team,
        lock_bonus_rate=vip_service.bonus_for_level(user_vip),
        rule_version=RULE_VERSION,
        expires_at=now + timedelta(days=product.duration_days),
        settled_periods=0,
        next_settle_at=settlement_service.first_settle_at(
            now, product.duration_days, product.return_method
        ),
        idempotency_key=idempotency_key,
    )
    db.add(order)
    try:
        await db.flush()
    except IntegrityError:
        # 并发同键 (跨进程绕过了锁): 撤销本次写入, 返回首次订单 (只扣一次)
        await db.rollback()
        return (
            await db.execute(
                select(HkOrder).where(
                    HkOrder.user_id == user.id,
                    HkOrder.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one()

    # 本金扣款: 条件原子 UPDATE (余额充足才扣), 行级并发安全 (sqlite/postgres 通用).
    # 不能用"先查余额再减"——并发下所有事务都读到旧余额, 会超扣 (测试已抓到).
    try:
        await get_or_create_account(db, user.id)
    except IntegrityError:
        # 并发开户竞争: 回滚后重查即可 (此前的产品校验/订单插入随回滚撤销)
        await db.rollback()
        db.add(order)
        await get_or_create_account(db, user.id)
    result = await db.execute(
        update(HkAccount)
        .where(
            HkAccount.user_id == user.id,
            HkAccount.principal_balance >= amount,
        )
        .values(principal_balance=HkAccount.principal_balance - amount)
    )
    await db.flush()
    if result.rowcount != 1:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "本金账户余额不足，请先充值"
        )
    # 资金明细: 购买扣款 ← 本金
    await log_balance(
        db, user.id, "principal", "purchase", -amount,
        ref_type="order", ref_id=order.id,
    )

    # 等级变动日志: 购买可能改变本人 VIP 与各级上级的团队等级, 记录事件后等级
    await level_log_service.record_event(db, user.id, source="purchase")
    return order


async def list_my_orders(db: AsyncSession, user_id: int) -> list[HkOrder]:
    """我的订单, 最新在前."""
    result = await db.execute(
        select(HkOrder)
        .where(HkOrder.user_id == user_id)
        .order_by(desc(HkOrder.created_at))
    )
    return list(result.scalars().all())
