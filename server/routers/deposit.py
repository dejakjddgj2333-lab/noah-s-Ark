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


class ClaimIn(BaseModel):
    txid: str
    network: str = "trc20"


class PrepareTransferIn(BaseModel):
    owner_address: str
    amount: Decimal
    network: str = "trc20"


class BroadcastIn(BaseModel):
    signed_tx: dict


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


@router.post("/claim", response_model=DepositRecordOut)
async def claim_deposit(
    data: ClaimIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """txid 补单: 链上已转未到账时自助核销 (钱包连接到账也走这里)."""
    return await deposit_service.claim_by_txid(
        db, user.id, data.network, data.txid
    )


@router.post("/prepare-transfer")
async def prepare_transfer(
    data: PrepareTransferIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """构造未签名 USDT 转账交易 (钱包连接支付第一步)."""
    return await deposit_service.prepare_transfer(
        db, user.id, data.network, data.owner_address, data.amount
    )


@router.post("/broadcast")
async def broadcast(
    data: BroadcastIn,
    user: HkUser = Depends(auth_service.get_current_user),
):
    """广播钱包签名后的交易, 返回 txid (随后前端调 claim 核销)."""
    txid = await deposit_service.broadcast_tx(data.signed_tx)
    return {"txid": txid}


@router.get("/account", response_model=AccountOut)
async def my_account(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """双账户余额 (本金/收益, 各含提现处理中)."""
    account = await account_service.get_or_create_account(db, user.id)
    return AccountOut.model_validate(account)
