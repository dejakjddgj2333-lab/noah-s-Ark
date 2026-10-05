"""提现后台路由 (管理员): 查询 / 审核通过 / 拒绝."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkWithdrawal
from models.hk import HkUser
from services import admin_service, auth_service, withdraw_service

router = APIRouter(prefix="/admin/withdrawals", tags=["后台-提现"])


class WithdrawOut(BaseModel):
    id: int
    user_id: int
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


class ApproveIn(BaseModel):
    # 打款交易号: 通过必须登记, 留审计依据; 链上哈希格式 (0x 可选, 64 位十六进制)
    txid: str = Field(min_length=1, max_length=66)

    @field_validator("txid")
    @classmethod
    def _txid_format(cls, v: str) -> str:
        import re
        if not re.fullmatch(r"(0x)?[0-9a-fA-F]{64}", v.strip()):
            raise ValueError("txid 格式不正确 (应为 64 位十六进制链上交易哈希)")
        return v.strip()


class RejectIn(BaseModel):
    remark: str | None = None


@router.get("", response_model=list[WithdrawOut])
async def list_withdrawals(
    status: str | None = Query(default=None),
    limit: int = Query(default=100, le=500),
    user: HkUser = Depends(admin_service.require_perm("page:withdrawals")),
    db: AsyncSession = Depends(get_db),
):
    q = select(HkWithdrawal)
    if status:
        q = q.where(HkWithdrawal.status == status)
    result = await db.execute(q.order_by(desc(HkWithdrawal.id)).limit(limit))
    return result.scalars().all()


@router.post("/{withdrawal_id}/approve", response_model=WithdrawOut)
async def approve_withdrawal(
    withdrawal_id: int,
    data: ApproveIn,
    user: HkUser = Depends(admin_service.require_perm("btn:withdrawal:audit")),
    db: AsyncSession = Depends(get_db),
):
    """审核通过: 处理中金额转出; 平台完成链上打款后登记 txid."""
    w = await withdraw_service.get(db, withdrawal_id)
    await withdraw_service.approve(db, w, data.txid)
    w.processed_by = user.username
    await admin_service.audit(
        db, user, "withdraw_approve", "withdrawal", w.id,
        detail=f"amount={w.amount} account={w.account} txid={data.txid}",
    )
    await db.commit()
    return w


@router.post("/{withdrawal_id}/reject", response_model=WithdrawOut)
async def reject_withdrawal(
    withdrawal_id: int,
    data: RejectIn,
    user: HkUser = Depends(admin_service.require_perm("btn:withdrawal:audit")),
    db: AsyncSession = Depends(get_db),
):
    """拒绝: 全额退回 (金额+服务费+网络费)."""
    w = await withdraw_service.get(db, withdrawal_id)
    await withdraw_service.reject(db, w, data.remark)
    w.processed_by = user.username
    await admin_service.audit(
        db, user, "withdraw_reject", "withdrawal", w.id,
        detail=f"amount={w.amount} account={w.account} remark={data.remark}",
    )
    await db.commit()
    return w
