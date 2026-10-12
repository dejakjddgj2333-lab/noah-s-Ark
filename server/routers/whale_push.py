"""巨鲸异动推送订阅: 每人一条配置, 命中的大额成交走 APNs 推给订阅者."""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser, HkWhaleSubscription
from services import auth_service

router = APIRouter(prefix="/whale-push", tags=["巨鲸推送"])

_MIN_USD_FLOOR = 100_000  # 订阅阈值下限, 低于此会被大额流淹没
_MAX_MIN_USD = 100_000_000


def _out(s: HkWhaleSubscription | None) -> dict:
    """无记录时返回默认配置 (未开启)."""
    if s is None:
        return {
            "enabled": False,
            "min_usd": 500_000,
            "symbols": [],
        }
    try:
        symbols = json.loads(s.symbols or "[]")
    except ValueError:
        symbols = []
    return {
        "enabled": s.enabled,
        "min_usd": s.min_usd,
        "symbols": symbols,
    }


class WhaleSubIn(BaseModel):
    enabled: bool
    min_usd: float = Field(default=500_000)
    symbols: list[str] = Field(default_factory=list, max_length=20)


@router.get("/subscription")
async def get_subscription(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    result = await db.execute(
        select(HkWhaleSubscription).where(HkWhaleSubscription.user_id == me.id)
    )
    return _out(result.scalar_one_or_none())


@router.put("/subscription")
async def put_subscription(
    data: WhaleSubIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """幂等 upsert. symbols 空数组 = 订阅全部币种."""
    if not (_MIN_USD_FLOOR <= data.min_usd <= _MAX_MIN_USD):
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"min_usd 须在 {_MIN_USD_FLOOR}~{_MAX_MIN_USD} 之间",
        )
    symbols = sorted({s.strip().upper().replace("/", "") for s in data.symbols if s.strip()})
    result = await db.execute(
        select(HkWhaleSubscription).where(HkWhaleSubscription.user_id == me.id)
    )
    row = result.scalar_one_or_none()
    if row is None:
        row = HkWhaleSubscription(user_id=me.id)
        db.add(row)
    row.enabled = data.enabled
    row.min_usd = data.min_usd
    row.symbols = json.dumps(symbols)
    await db.commit()
    return _out(row)
