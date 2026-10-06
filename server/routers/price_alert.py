"""行情预警 CRUD: 用户给交易对设 涨破/跌破 目标价, 后台监测触发 APNs."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkPriceAlert, HkUser
from services import auth_service

router = APIRouter(prefix="/price-alerts", tags=["行情预警"])

_DIRECTIONS = ("up", "down")


def _out(a: HkPriceAlert) -> dict:
    return {
        "id": a.id,
        "symbol": a.symbol,
        "direction": a.direction,
        "target_price": a.target_price,
        "triggered": a.triggered,
        "created_at": a.created_at.isoformat() if a.created_at else None,
    }


class PriceAlertIn(BaseModel):
    symbol: str = Field(min_length=1, max_length=32)
    direction: str
    target_price: float


@router.get("")
async def list_alerts(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """我的预警列表: 未触发在前, 再按创建时间倒序."""
    result = await db.execute(
        select(HkPriceAlert)
        .where(HkPriceAlert.user_id == me.id)
        .order_by(HkPriceAlert.triggered.asc(), HkPriceAlert.created_at.desc())
    )
    return {"alerts": [_out(a) for a in result.scalars().all()]}


@router.post("", status_code=201)
async def create_alert(
    data: PriceAlertIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    symbol = data.symbol.strip().upper().replace("/", "")
    if not symbol:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="symbol 不能为空")
    direction = data.direction.strip().lower()
    if direction not in _DIRECTIONS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="direction 必须是 up/down"
        )
    if data.target_price <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="target_price 必须大于 0"
        )
    alert = HkPriceAlert(
        user_id=me.id,
        symbol=symbol,
        direction=direction,
        target_price=data.target_price,
    )
    db.add(alert)
    await db.commit()
    await db.refresh(alert)
    return _out(alert)


@router.delete("/{alert_id}")
async def delete_alert(
    alert_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    result = await db.execute(
        select(HkPriceAlert).where(
            HkPriceAlert.id == alert_id, HkPriceAlert.user_id == me.id
        )
    )
    alert = result.scalar_one_or_none()
    if alert is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="预警不存在")
    await db.delete(alert)
    await db.commit()
    return {"ok": True}
