"""账户互转路由: 收益→本金转化 (2026-10-06 拍板, 收服务费防绕过提现收费)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, Query, status
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from services import auth_service, convert_service

router = APIRouter(prefix="/account", tags=["账户互转"])


class ConvertIn(BaseModel):
    amount: Decimal  # 转化金额 (收益账户出账全额)
    idempotency_key: str | None = None  # 幂等键: 网络重试/重复点击只扣一次


@router.get("/convert/quote")
async def convert_quote(
    amount: Decimal = Query(...),
    user: HkUser = Depends(auth_service.get_current_user),
):
    """转化报价: 服务费 / 实际到账本金 (提交时服务端重算, 以此为准)."""
    return convert_service.quote(amount)


@router.post("/convert", status_code=status.HTTP_201_CREATED)
async def convert(
    data: ConvertIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """收益→本金: 收益扣全额, 本金入 (金额−服务费). 同幂等键只扣一次."""
    q = await convert_service.convert(db, user.id, data.amount, data.idempotency_key)
    await db.commit()
    return q
