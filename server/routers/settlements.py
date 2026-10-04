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
    buyer_username: str | None  # 来源下级
    gen: int
    receiver_team_level: int
    rate: Decimal
    amount: Decimal
    base_amount: Decimal | None  # 返佣基数 = 该期已截断收益
    period_no: int | None  # 关联结算期数
    settle_at: datetime | None  # 应结算时点 (结算流水时间)
    created_at: datetime  # 实际入账时间

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
    """我收到的佣金流水: 来源代数/下级、返佣基数、比例、金额、应结算时点、实际入账时间
    (文档 8.1 佣金记录字段)."""
    result = await db.execute(
        select(HkCommissionRecord, HkSettlementRecord, HkUser.username)
        .join(
            HkSettlementRecord,
            HkSettlementRecord.id == HkCommissionRecord.settlement_id,
        )
        .join(HkUser, HkUser.id == HkCommissionRecord.buyer_id)
        .where(HkCommissionRecord.receiver_id == user.id)
        .order_by(desc(HkCommissionRecord.created_at))
        .limit(200)
    )
    out = []
    for comm, stl, buyer_name in result.all():
        out.append(
            CommissionOut(
                id=comm.id,
                settlement_id=comm.settlement_id,
                order_id=comm.order_id,
                buyer_id=comm.buyer_id,
                buyer_username=buyer_name,
                gen=comm.gen,
                receiver_team_level=comm.receiver_team_level,
                rate=comm.rate,
                amount=comm.amount,
                base_amount=stl.income_amount,
                period_no=stl.period_no,
                settle_at=stl.created_at,
                created_at=comm.created_at,
            )
        )
    return out


@router.get("/commissions/summary")
async def my_commission_summary(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """佣金汇总: 累计 / 今日 / 按代数分组 (分佣页头部卡)."""
    from sqlalchemy import func

    from models.hk import utc_now

    today = utc_now().replace(hour=0, minute=0, second=0, microsecond=0)
    total = (
        await db.execute(
            select(func.coalesce(func.sum(HkCommissionRecord.amount), 0)).where(
                HkCommissionRecord.receiver_id == user.id
            )
        )
    ).scalar_one()
    today_sum = (
        await db.execute(
            select(func.coalesce(func.sum(HkCommissionRecord.amount), 0)).where(
                HkCommissionRecord.receiver_id == user.id,
                HkCommissionRecord.created_at >= today,
            )
        )
    ).scalar_one()
    rows = (
        await db.execute(
            select(
                HkCommissionRecord.gen,
                func.coalesce(func.sum(HkCommissionRecord.amount), 0),
                func.count(),
            )
            .where(HkCommissionRecord.receiver_id == user.id)
            .group_by(HkCommissionRecord.gen)
        )
    ).all()
    return {
        "total": str(total),
        "today": str(today_sum),
        "by_gen": [
            {"gen": g, "amount": str(a), "count": c} for g, a, c in rows
        ],
    }


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
