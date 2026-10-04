"""充值后台管理路由 (需管理员)."""
from __future__ import annotations

from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, Query
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkDepositAddress, HkDepositRecord
from models.hk import HkUser
from services import admin_service

router = APIRouter(prefix="/admin/deposit", tags=["后台-充值"])


class PageOut(BaseModel):
    total: int
    list: list[dict]


class GenerateIn(BaseModel):
    network: str = "trc20"
    count: int = Field(default=10, ge=1, le=200)


@router.get("/records")
async def admin_records(
    status: str | None = Query(default=None),
    network: str | None = Query(default=None),
    username: str | None = Query(default=None),
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    _: HkUser = Depends(admin_service.require_perm("page:deposit-records")),
    db: AsyncSession = Depends(get_db),
):
    """充值流水 (全用户), 支持状态/网络/用户名过滤."""
    stmt = (
        select(
            HkDepositRecord.id,
            HkDepositRecord.network,
            HkDepositRecord.address,
            HkDepositRecord.txid,
            HkDepositRecord.amount,
            HkDepositRecord.confirmations,
            HkDepositRecord.required_confirmations,
            HkDepositRecord.status,
            HkDepositRecord.block_time,
            HkDepositRecord.credited_at,
            HkUser.username,
        )
        .join(HkUser, HkUser.id == HkDepositRecord.user_id)
        .order_by(HkDepositRecord.id.desc())
    )
    count_stmt = select(func.count()).select_from(HkDepositRecord)
    if status:
        stmt = stmt.where(HkDepositRecord.status == status)
        count_stmt = count_stmt.where(HkDepositRecord.status == status)
    if network:
        stmt = stmt.where(HkDepositRecord.network == network)
        count_stmt = count_stmt.where(HkDepositRecord.network == network)
    if username:
        stmt = stmt.where(HkUser.username.contains(username))
        count_stmt = count_stmt.where(
            HkDepositRecord.user_id.in_(
                select(HkUser.id).where(HkUser.username.contains(username))
            )
        )

    total = (await db.execute(count_stmt)).scalar_one()
    rows = (
        await db.execute(stmt.offset((page - 1) * page_size).limit(page_size))
    ).all()
    return PageOut(
        total=total,
        list=[
            {
                "id": r.id,
                "username": r.username,
                "network": r.network,
                "address": r.address,
                "txid": r.txid,
                "amount": str(r.amount),
                "confirmations": r.confirmations,
                "required_confirmations": r.required_confirmations,
                "status": r.status,
                "block_time": r.block_time.isoformat() if r.block_time else None,
                "credited_at": r.credited_at.isoformat() if r.credited_at else None,
            }
            for r in rows
        ],
    )


@router.get("/addresses")
async def admin_addresses(
    network: str | None = Query(default=None),
    state: str | None = Query(default=None),  # free | assigned
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=20, ge=1, le=100),
    _: HkUser = Depends(admin_service.require_perm("page:deposit-pool")),
    db: AsyncSession = Depends(get_db),
):
    """地址池列表与统计."""
    stmt = (
        select(
            HkDepositAddress.id,
            HkDepositAddress.network,
            HkDepositAddress.address,
            HkDepositAddress.user_id,
            HkDepositAddress.assigned_at,
            HkDepositAddress.created_at,
            HkUser.username,
        )
        .outerjoin(HkUser, HkUser.id == HkDepositAddress.user_id)
        .order_by(HkDepositAddress.id.desc())
    )
    count_stmt = select(func.count()).select_from(HkDepositAddress)
    if network:
        stmt = stmt.where(HkDepositAddress.network == network)
        count_stmt = count_stmt.where(HkDepositAddress.network == network)
    if state == "free":
        stmt = stmt.where(HkDepositAddress.user_id.is_(None))
        count_stmt = count_stmt.where(HkDepositAddress.user_id.is_(None))
    elif state == "assigned":
        stmt = stmt.where(HkDepositAddress.user_id.isnot(None))
        count_stmt = count_stmt.where(HkDepositAddress.user_id.isnot(None))

    total = (await db.execute(count_stmt)).scalar_one()
    rows = (
        await db.execute(stmt.offset((page - 1) * page_size).limit(page_size))
    ).all()
    return PageOut(
        total=total,
        list=[
            {
                "id": r.id,
                "network": r.network,
                "address": r.address,
                "username": r.username,
                "assigned_at": r.assigned_at.isoformat() if r.assigned_at else None,
                "created_at": r.created_at.isoformat() if r.created_at else None,
            }
            for r in rows
        ],
    )


@router.get("/stats")
async def admin_stats(
    _: HkUser = Depends(admin_service.require_perm("page:deposit-records")),
    db: AsyncSession = Depends(get_db),
):
    """充值概览: 地址池/今日入账/确认中/异常."""
    free = (
        await db.execute(
            select(func.count())
            .select_from(HkDepositAddress)
            .where(HkDepositAddress.user_id.is_(None))
        )
    ).scalar_one()
    assigned = (
        await db.execute(
            select(func.count())
            .select_from(HkDepositAddress)
            .where(HkDepositAddress.user_id.isnot(None))
        )
    ).scalar_one()
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    credited_today = (
        await db.execute(
            select(func.coalesce(func.sum(HkDepositRecord.amount), 0))
            .where(
                HkDepositRecord.status == "credited",
                HkDepositRecord.credited_at >= today,
            )
        )
    ).scalar_one()
    confirming = (
        await db.execute(
            select(func.count())
            .select_from(HkDepositRecord)
            .where(HkDepositRecord.status == "confirming")
        )
    ).scalar_one()
    unmatched = (
        await db.execute(
            select(func.count())
            .select_from(HkDepositRecord)
            .where(HkDepositRecord.status == "unmatched")
        )
    ).scalar_one()
    return {
        "pool_free": free,
        "pool_assigned": assigned,
        "credited_today": str(credited_today),
        "confirming": confirming,
        "unmatched": unmatched,
    }


@router.post("/addresses/generate")
async def admin_generate(
    data: GenerateIn,
    _: HkUser = Depends(admin_service.require_perm("btn:deposit:generate")),
):
    """生成充值地址并加入地址池 (调用脚本逻辑, 同步返回生成数量)."""
    from scripts.keygen import generate_addresses

    created = await generate_addresses(data.network.lower(), data.count)
    return {"ok": True, "created": created, "network": data.network.lower()}
