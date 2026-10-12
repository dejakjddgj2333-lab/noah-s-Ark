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
_TYPES = ("price", "percent")


def _out(a: HkPriceAlert) -> dict:
    return {
        "id": a.id,
        "symbol": a.symbol,
        "alert_type": a.alert_type or "price",
        "direction": a.direction,
        "target_price": a.target_price,
        "percent": a.percent,
        "baseline_price": a.baseline_price,
        "triggered": a.triggered,
        "created_at": a.created_at.isoformat() if a.created_at else None,
    }


class PriceAlertIn(BaseModel):
    symbol: str = Field(min_length=1, max_length=32)
    alert_type: str = "price"  # price=目标价 / percent=涨跌幅
    direction: str
    target_price: float = 0
    percent: float = 0


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
    alert_type = data.alert_type.strip().lower()
    if alert_type not in _TYPES:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="alert_type 必须是 price/percent"
        )
    percent = None
    baseline = None
    target = 0.0
    if alert_type == "percent":
        if not (0 < data.percent <= 100):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail="percent 须在 0~100 之间"
            )
        # 基准价 = 创建时最新价, 监测引擎按 涨/跌幅 >= percent 判定
        from services import price_alert_monitor

        baseline = await price_alert_monitor.fetch_price(symbol)
        if baseline is None or baseline <= 0:
            raise HTTPException(
                status.HTTP_502_BAD_GATEWAY, detail="获取当前价失败, 请稍后重试"
            )
        percent = data.percent
    else:
        if data.target_price <= 0:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail="target_price 必须大于 0"
            )
        target = data.target_price
    alert = HkPriceAlert(
        user_id=me.id,
        symbol=symbol,
        alert_type=alert_type,
        direction=direction,
        target_price=target,
        percent=percent,
        baseline_price=baseline,
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
