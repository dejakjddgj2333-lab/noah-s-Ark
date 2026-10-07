"""后台功能开关路由: 读取/修改 HkConfig (充值提现等模块开关)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkConfig, HkUser
from services import admin_service, config_service

router = APIRouter(prefix="/admin/config", tags=["后台-功能开关"])


class ConfigIn(BaseModel):
    value: str  # "0"/"1"


def _row(r: HkConfig) -> dict:
    return {"key": r.key, "value": r.value, "label": r.label}


@router.get("")
async def list_configs(
    user: HkUser = Depends(admin_service.require_perm("page:feature")),
    db: AsyncSession = Depends(get_db),
) -> list[dict]:
    rows = (await db.execute(select(HkConfig))).scalars().all()
    return [_row(r) for r in rows]


@router.put("/{key}")
async def update_config(
    key: str,
    data: ConfigIn,
    user: HkUser = Depends(admin_service.require_perm("btn:feature:edit")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    ok = await config_service.set_value(db, key, data.value)
    if not ok:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="配置不存在")
    await admin_service.audit(
        db, user, "config_update", "config", 0, detail=f"{key}={data.value}"
    )
    row = (
        await db.execute(select(HkConfig).where(HkConfig.key == key))
    ).scalar_one()
    return _row(row)
