"""购买订单后台路由 (管理员): 全部订单列表 + 每单已产生收益明细.

收益口径: hk_settlement_records 按 order_id 聚合 (已入账才计入);
佣金为平台额外支出, 单独列示, 不混入购买人收益.
"""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import desc, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkAdminUser, HkUser
from models.order import HkOrder
from models.settlement import HkCommissionRecord, HkSettlementRecord
from services import admin_service, settlement_service

router = APIRouter(prefix="/admin/orders", tags=["后台-订单"])

RETURN_METHOD_LABELS = {
    "daily": "每日返还",
    "period_7d": "每7天返还",
    "period_30d": "每30天返还",
    "period_1h": "每小时返还",
    "expiry": "到期一次性返还",
}


@router.get("")
async def list_orders(
    username: str | None = Query(default=None),
    status_filter: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=100, le=500),
    offset: int = Query(default=0, ge=0),
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:orders")),
    db: AsyncSession = Depends(get_db),
):
    """全部购买订单 (最新在前), 附每单已结算收益/已返本金/佣金支出聚合."""
    q = (
        select(HkOrder, HkUser.username)
        .join(HkUser, HkUser.id == HkOrder.user_id)
    )
    if username:
        q = q.where(HkUser.username.contains(username.strip()))
    if status_filter:
        q = q.where(HkOrder.status == status_filter)
    q = q.order_by(desc(HkOrder.id)).limit(limit).offset(offset)
    rows = (await db.execute(q)).all()
    order_ids = [o.id for o, _ in rows]

    # 聚合: 每单已结算收益 / 已返本金 / 平台佣金支出
    income_map: dict[int, tuple] = {}
    comm_map: dict[int, tuple] = {}
    if order_ids:
        inc = await db.execute(
            select(
                HkSettlementRecord.order_id,
                func.count(HkSettlementRecord.id),
                func.coalesce(func.sum(HkSettlementRecord.income_amount), 0),
                func.coalesce(func.sum(HkSettlementRecord.principal_amount), 0),
            )
            .where(HkSettlementRecord.order_id.in_(order_ids))
            .group_by(HkSettlementRecord.order_id)
        )
        income_map = {r[0]: r[1:] for r in inc.all()}
        com = await db.execute(
            select(
                HkCommissionRecord.order_id,
                func.coalesce(func.sum(HkCommissionRecord.amount), 0),
            )
            .where(HkCommissionRecord.order_id.in_(order_ids))
            .group_by(HkCommissionRecord.order_id)
        )
        comm_map = {r[0]: r[1] for r in com.all()}

    total = (
        await db.execute(
            select(func.count(HkOrder.id)).select_from(HkOrder)
        )
    ).scalar_one()

    items = []
    for o, uname in rows:
        periods, income, principal = income_map.get(o.id, (0, 0, 0))
        items.append({
            "id": o.id,
            "user_id": o.user_id,
            "username": uname,
            "product_name": o.product_name,
            "amount": str(o.amount),
            "base_daily_rate": str(o.base_daily_rate),
            "actual_daily_rate": (
                str(o.actual_daily_rate) if o.actual_daily_rate is not None else None
            ),
            "lock_bonus_rate": (
                str(o.lock_bonus_rate) if o.lock_bonus_rate is not None else None
            ),
            "vip_level": o.vip_level,
            "team_level": o.team_level,
            "duration_days": o.duration_days,
            "return_method": o.return_method,
            "return_method_label": RETURN_METHOD_LABELS.get(
                o.return_method, o.return_method
            ),
            "status": o.status,
            "total_periods": settlement_service.total_periods(o),
            "settled_periods": periods,
            "settled_income": str(income),
            "principal_returned": str(principal),
            "commission_paid": str(comm_map.get(o.id, 0)),
            "effective_at": str(o.effective_at) if o.effective_at else None,
            "expires_at": str(o.expires_at) if o.expires_at else None,
            "created_at": str(o.created_at),
        })
    return {"total": total, "items": items}


@router.get("/{order_id}/settlements")
async def order_settlements(
    order_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:orders")),
    db: AsyncSession = Depends(get_db),
):
    """某订单的逐期收益结算明细 + 该单触发的佣金流水."""
    order = (
        await db.execute(select(HkOrder).where(HkOrder.id == order_id))
    ).scalar_one_or_none()
    if order is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "订单不存在")

    stls = (
        await db.execute(
            select(HkSettlementRecord)
            .where(HkSettlementRecord.order_id == order_id)
            .order_by(HkSettlementRecord.period_no)
        )
    ).scalars().all()
    comms = (
        await db.execute(
            select(HkCommissionRecord, HkUser.username)
            .join(HkUser, HkUser.id == HkCommissionRecord.receiver_id)
            .where(HkCommissionRecord.order_id == order_id)
            .order_by(HkCommissionRecord.id)
        )
    ).all()
    return {
        "order_id": order_id,
        "settlements": [
            {
                "period_no": s.period_no,
                "period_days": str(s.period_days),
                "income_amount": str(s.income_amount),
                "principal_amount": str(s.principal_amount),
                "due_at": str(s.due_at) if s.due_at else None,
                "created_at": str(s.created_at),
            }
            for s in stls
        ],
        "commissions": [
            {
                "receiver_id": cm.receiver_id,
                "receiver_username": uname,
                "gen": cm.gen,
                "rate": str(cm.rate),
                "base_amount": str(cm.base_amount),
                "amount": str(cm.amount),
                "created_at": str(cm.created_at),
            }
            for cm, uname in comms
        ],
    }
