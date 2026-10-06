"""资金归集后台路由: 主钱包设置 / 地址余额 / 手动归集 / 归集记录."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkSweepRecord
from models.hk import HkUser
from services import admin_service, sweep_service
from services.deposit_service import NETWORKS

router = APIRouter(prefix="/admin/sweep", tags=["后台-归集"])


@router.get("/targets")
async def get_targets(
    user: HkUser = Depends(admin_service.require_perm("page:sweep")),
    db: AsyncSession = Depends(get_db),
):
    return await sweep_service.get_targets(db)


class TargetIn(BaseModel):
    network: str
    target: str = Field(min_length=20, max_length=64)
    threshold: Decimal = Field(default=Decimal("500"), ge=1)


@router.put("/targets")
async def set_target(
    body: TargetIn,
    user: HkUser = Depends(admin_service.require_perm("btn:sweep:target")),
    db: AsyncSession = Depends(get_db),
):
    """设置某网络主钱包 + 归集阈值. 地址格式按链校验.

    独立权限码 btn:sweep:target (与执行归集 btn:sweep:run 分离):
    改地址和动钱不得是同一个权限, 防单账号改地址后卷走池内资金.
    """
    if body.network not in NETWORKS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不支持的网络")
    cfg = NETWORKS[body.network]
    addr = body.target.strip()
    if cfg["chain"] == "tron":
        if not addr.startswith("T") or len(addr) != 34:
            raise HTTPException(status.HTTP_400_BAD_REQUEST,
                                "TRON 地址须 T 开头 34 位")
    else:
        import re

        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", addr):
            raise HTTPException(status.HTTP_400_BAD_REQUEST,
                                "EVM 地址须 0x 开头 42 位")
    await sweep_service.set_setting(db, f"sweep_target_{body.network}", addr)
    await sweep_service.set_setting(
        db, f"sweep_threshold_{body.network}", str(body.threshold)
    )
    await admin_service.audit(
        db, user, "sweep_set_target", "network", 0,
        f"{body.network} target={addr} threshold={body.threshold}")
    await db.commit()
    return {"ok": True}


@router.get("/balances")
async def balances(
    network: str = Query(default="trc20"),
    user: HkUser = Depends(admin_service.require_perm("page:sweep")),
    db: AsyncSession = Depends(get_db),
):
    """该网络已分配地址的 USDT/gas 余额 (有余额的才返回)."""
    if network not in NETWORKS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不支持的网络")
    return await sweep_service.address_balances(db, network)


class RunIn(BaseModel):
    network: str
    address: str | None = None  # 指定单个地址, 空=全部达阈值地址


@router.post("/run")
async def run(
    body: RunIn,
    user: HkUser = Depends(admin_service.require_perm("btn:sweep:run")),
    db: AsyncSession = Depends(get_db),
):
    """执行归集: 返回 {swept, gas_needed, failed, skipped}."""
    if body.network not in NETWORKS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不支持的网络")
    result = await sweep_service.run_sweep(db, body.network, user, body.address)
    await admin_service.audit(db, user, "sweep_run", "network", 0,
                              f"{body.network}: {result}")
    await db.commit()
    return result


@router.get("/records")
async def records(
    network: str | None = Query(default=None),
    limit: int = Query(default=100, le=500),
    user: HkUser = Depends(admin_service.require_perm("page:sweep")),
    db: AsyncSession = Depends(get_db),
):
    q = select(HkSweepRecord).order_by(desc(HkSweepRecord.id)).limit(limit)
    if network:
        q = select(HkSweepRecord).where(
            HkSweepRecord.network == network
        ).order_by(desc(HkSweepRecord.id)).limit(limit)
    rows = (await db.execute(q)).scalars().all()
    return [
        {
            "id": r.id, "network": r.network, "from_address": r.from_address,
            "to_address": r.to_address, "amount": str(r.amount),
            "txid": r.txid, "status": r.status, "error": r.error,
            "operator": r.operator_username, "created_at": str(r.created_at),
        }
        for r in rows
    ]
