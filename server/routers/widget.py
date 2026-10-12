"""iOS 桌面小组件数据端点: 公开小 JSON, 无需登录.

供 WidgetKit 扩展直接拉取 (App 端 widget_bridge 写 App Group 为辅,
widget 自身 timeline 也可以直接打这两个接口兜底).
"""
from __future__ import annotations

from fastapi import APIRouter

from routers import market
from services import hl_whale

router = APIRouter(prefix="/widget", tags=["小组件"])

_WIDGET_COINS = ["BTC", "ETH", "SOL", "XRP", "DOGE"]


@router.get("/prices")
async def widget_prices():
    """固定五币最新价 + 24h 涨跌幅 (OKX USDT 永续, 走行情代理 TTL 缓存)."""
    out = []
    for coin in _WIDGET_COINS:
        inst = f"{coin}-USDT-SWAP"
        try:
            data = await market.ticker(inst)
            rows = data.get("data") or []
            if not rows:
                continue
            t = rows[0]
            last = float(t.get("last") or 0)
            open24h = float(t.get("open24h") or 0)
            change_pct = (
                round((last - open24h) / open24h * 100, 2) if open24h else 0.0
            )
            out.append({
                "symbol": coin,
                "price": last,
                "change_pct": change_pct,
                "ts": int(t.get("ts") or 0),
            })
        except Exception:
            continue  # 单币失败不影响其它
    return {"prices": out}


@router.get("/whale-alerts")
async def widget_whale_alerts():
    """最新 5 条巨鲸异动 (内存环形缓冲直读)."""
    return {"alerts": hl_whale.whale_alerts()[:5]}
