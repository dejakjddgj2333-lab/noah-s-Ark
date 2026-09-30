"""市场总览: CoinGlass v4 透传, 带内存 TTL 缓存. 未配置 API Key 返回 503."""
from __future__ import annotations

import time
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Query

from config import config

router = APIRouter(prefix="/market-overview", tags=["市场总览"])

_BASE = "https://open-api-v4.coinglass.com"
_TIMEOUT = 15

# path+params -> (data, expire_at)
_cache: dict[str, tuple[Any, float]] = {}


def _require_key() -> str:
    if not config.coinglass_api_key:
        raise HTTPException(status_code=503, detail="CoinGlass 未配置")
    return config.coinglass_api_key


async def _cg_get(path: str, params: dict | None = None, ttl: int = 60) -> Any:
    """GET + TTL 缓存; 上游错误返回 502."""
    _require_key()
    key = f"{path}|{sorted((params or {}).items())}"
    now = time.time()
    hit = _cache.get(key)
    if hit and hit[1] > now:
        return hit[0]

    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(
                _BASE + path,
                headers={"accept": "application/json", "CG-API-KEY": config.coinglass_api_key},
                params=params or {},
            )
            body = resp.json()
    except Exception as exc:
        raise HTTPException(status_code=502, detail=f"CoinGlass 上游错误: {exc}") from exc

    if str(body.get("code")) != "0":
        raise HTTPException(status_code=502, detail=f"CoinGlass 错误: {body.get('msg')}")

    data = body.get("data")
    _cache[key] = (data, now + ttl)
    return data


@router.get("/sentiment")
async def get_sentiment():
    """恐慌贪婪指数(最新). data_list 时间升序, 取末位."""
    data = await _cg_get("/api/index/fear-greed-history", ttl=300)
    values = data.get("data_list") if isinstance(data, dict) else data
    return {"fear_greed": values[-1] if values else None}


@router.get("/liquidations/exchange-list")
async def get_liq_exchange_list(range: str = Query("24h")):
    """各交易所爆仓统计. range: 1h/4h/12h/24h."""
    data = await _cg_get("/api/futures/liquidation/exchange-list", {"range": range}, ttl=60)
    return {"range": range, "data": data}


@router.get("/funding/exchange-rates")
async def get_funding_exchange_rates(symbol: str = Query("BTC")):
    """单币种各所实时费率."""
    data = await _cg_get(
        "/api/futures/funding-rate/exchange-list", {"symbol": symbol.upper()}, ttl=60
    )
    return {"symbol": symbol.upper(), "data": data}


@router.get("/whale-alerts")
async def get_whale_alerts():
    """Hyperliquid 鲸鱼仓位变动."""
    data = await _cg_get("/api/hyperliquid/whale-alert", ttl=60)
    return {"alerts": data}
