"""充值路由 (用户侧, 需登录)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkAccount, HkDepositRecord  # noqa: F401 注册元数据
from models.hk import HkUser
from services import account_service, auth_service, deposit_service

router = APIRouter(prefix="/deposit", tags=["充值"])


class DepositAddressOut(BaseModel):
    network: str
    address: str
    required_confirmations: int
    min_deposit: Decimal


class DepositRecordOut(BaseModel):
    id: int
    network: str
    address: str
    txid: str
    amount: Decimal
    confirmations: int
    required_confirmations: int
    status: str
    block_time: str | None
    credited_at: str | None

    model_config = {"from_attributes": True}


class AccountOut(BaseModel):
    principal_balance: Decimal
    income_balance: Decimal
    principal_pending: Decimal
    income_pending: Decimal

    model_config = {"from_attributes": True}


@router.get("/address", response_model=DepositAddressOut)
async def deposit_address(
    network: str = Query(default="trc20"),
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """查询我的充值地址, 首次访问时自动从地址池分配."""
    addr = await deposit_service.get_or_assign_address(db, user.id, network)
    cfg = deposit_service.get_network(network)
    return DepositAddressOut(
        network=addr.network,
        address=addr.address,
        required_confirmations=cfg["confirmations_required"],
        min_deposit=Decimal(cfg["min_deposit"]),
    )


@router.get("/records", response_model=list[DepositRecordOut])
async def deposit_records(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await deposit_service.list_my_records(db, user.id)


@router.get("/account", response_model=AccountOut)
async def my_account(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """双账户余额 (本金/收益, 各含提现处理中)."""
    account = await account_service.get_or_create_account(db, user.id)
    return AccountOut.model_validate(account)
