"""订单路由 (用户侧, 需登录): 购买下单 + 我的订单."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from services import auth_service, order_service

router = APIRouter(prefix="/orders", tags=["订单"])


class OrderIn(BaseModel):
    product_id: int
    amount: Decimal


class OrderOut(BaseModel):
    id: int
    product_id: str
    product_name: str
    amount: Decimal
    status: str
    base_daily_rate: Decimal
    duration_days: int
    return_method: str
    vip_level: int | None
    lock_bonus_rate: Decimal | None
    actual_daily_rate: Decimal | None
    rule_version: str
    effective_at: datetime | None
    expires_at: datetime | None
    created_at: datetime

    model_config = {"from_attributes": True}


@router.post(
    "", response_model=OrderOut, status_code=status.HTTP_201_CREATED
)
async def buy(
    data: OrderIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """购买产品: 从本金账户扣款, 扣款成功订单即生效 (拍板: 购买了就成功)."""
    order = await order_service.create_order(db, user, data.product_id, data.amount)
    await db.commit()
    return order


@router.get("", response_model=list[OrderOut])
async def my_orders(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await order_service.list_my_orders(db, user.id)
