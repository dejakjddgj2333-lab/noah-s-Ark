"""提现路由 (用户侧, 需登录): 报价 / 申请 / 我的提现记录."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, status
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkWithdrawal  # noqa: F401 注册元数据
from models.hk import HkUser
from services import auth_service, withdraw_service

router = APIRouter(prefix="/withdrawals", tags=["提现"])


class WithdrawQuoteOut(BaseModel):
    account: str
    network: str
    amount: Decimal
    service_fee: Decimal
    network_fee: Decimal
    total_deduction: Decimal
    arrive_amount: Decimal


class WithdrawIn(BaseModel):
    account: str  # principal / income
    network: str  # trc20
    address: str
    amount: Decimal
    idempotency_key: str | None = Field(
        default=None, max_length=64
    )  # 可选: 防重复提交, 同键返回首次申请


class WithdrawOut(BaseModel):
    id: int
    account: str
    network: str
    address: str
    amount: Decimal
    service_fee: Decimal
    network_fee: Decimal
    arrive_amount: Decimal
    status: str
    txid: str | None
    remark: str | None
    created_at: datetime
    processed_at: datetime | None

    model_config = {"from_attributes": True}


@router.get("/networks")
async def withdraw_networks():
    """支持提现的网络清单 + 费用与收益账户规则 (提现页渲染用, 无需登录也可报价)."""
    return {"networks": withdraw_service.list_networks()}


@router.get("/quote", response_model=WithdrawQuoteOut)
async def withdraw_quote(account: str, amount: Decimal, network: str = "trc20"):
    """提交前费用报价 (展示用; 提交时服务端重算, 以服务端为准, 确认后不追加扣费)."""
    return withdraw_service.quote(account, amount, network)


@router.post("", response_model=WithdrawOut, status_code=status.HTTP_201_CREATED)
async def create_withdrawal(
    data: WithdrawIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """申请提现: 余额原子占用 (金额+费用), 申请金额转处理中."""
    w = await withdraw_service.create_request(
        db, user.id, data.account, data.network, data.address, data.amount,
        idempotency_key=data.idempotency_key,
    )
    await db.commit()
    return w


@router.get("", response_model=list[WithdrawOut])
async def my_withdrawals(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await withdraw_service.list_mine(db, user.id)
