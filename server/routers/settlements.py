"""结算与佣金流水查询 (用户侧, 需登录)."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from models.level_log import HkLevelLog
from models.settlement import HkCommissionRecord, HkSettlementRecord
from services import auth_service, level_log_service

router = APIRouter(tags=["结算"])


class SettlementOut(BaseModel):
    id: int
    order_id: int
    period_no: int
    period_days: int
    income_amount: Decimal
    principal_amount: Decimal
    created_at: datetime

    model_config = {"from_attributes": True}


class CommissionOut(BaseModel):
    id: int
    settlement_id: int
    order_id: int
    buyer_id: int
    gen: int
    receiver_team_level: int
    rate: Decimal
    amount: Decimal
    created_at: datetime

    model_config = {"from_attributes": True}


class LevelLogOut(BaseModel):
    id: int
    kind: str
    level: int
    holding: Decimal | None
    member_count: int | None
    source: str
    created_at: datetime

    model_config = {"from_attributes": True}


@router.get("/settlements", response_model=list[SettlementOut])
async def my_settlements(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """我的收益结算流水 (每期一条, 最后一期带 principal_amount 返本记录)."""
    result = await db.execute(
        select(HkSettlementRecord)
        .where(HkSettlementRecord.user_id == user.id)
        .order_by(desc(HkSettlementRecord.created_at))
        .limit(200)
    )
    return result.scalars().all()


@router.get("/commissions", response_model=list[CommissionOut])
async def my_commissions(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """我收到的佣金流水 (含应结算时点团队等级/代数/比例依据)."""
    result = await db.execute(
        select(HkCommissionRecord)
        .where(HkCommissionRecord.receiver_id == user.id)
        .order_by(desc(HkCommissionRecord.created_at))
        .limit(200)
    )
    return result.scalars().all()


@router.get("/level-logs", response_model=list[LevelLogOut])
async def my_level_logs(
    kind: str | None = None,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """我的等级变动日志 (vip/team 可选过滤): 等级 / 当时持仓依据 / 变动来源 / 时间."""
    return await level_log_service.list_logs(db, user.id, kind=kind)


class BalanceLogOut(BaseModel):
    id: int
    account: str
    change_type: str
    amount: Decimal
    balance_after: Decimal
    ref_type: str
    ref_id: int | None
    created_at: datetime

    model_config = {"from_attributes": True}


@router.get("/account/logs", response_model=list[BalanceLogOut])
async def my_balance_logs(
    account: str | None = None,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """我的资金明细 (本金/收益分类, 最新在前): 每笔记来源+关联单据+变动后余额."""
    from services import balance_log_service

    return await balance_log_service.list_logs(db, user.id, account=account)
