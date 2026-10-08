"""行情路由: 代理 OKX 公开 REST, 原样透传 {code, data}."""
from __future__ import annotations

import time
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Query
from tenacity import retry, retry_if_exception_type, stop_after_attempt

from config import config

router = APIRouter(prefix="/market", tags=["行情"])

_TIMEOUT = 10

# 复用连接池: 避免每个请求重新 TCP+TLS 握手 (OKX 海外, 握手开销大).
_client: httpx.AsyncClient | None = None


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(
            base_url=config.okx_base_url, timeout=_TIMEOUT
        )
    return _client


# 简单内存 TTL 缓存: 高频行情接口短缓存, 削峰 + 首屏秒开.
_cache: dict[str, tuple[Any, float]] = {}

# 各接口缓存秒数 (0 = 不缓存)
_CACHE_TTL = {
    "/api/v5/market/tickers": 10,
    "/api/v5/market/ticker": 5,
    "/api/v5/market/candles": 5,
    "/api/v5/market/books": 2,
    "/api/v5/market/trades": 2,
    "/api/v5/public/funding-rate": 5,
}


@retry(
    retry=retry_if_exception_type(httpx.HTTPError),
    stop=stop_after_attempt(2),
    reraise=True,
)
async def _okx_get(path: str, params: dict | None = None) -> dict:
    """GET OKX 公开接口 (复用连接池), 网络错误重试 1 次. 返回原始 JSON."""
    resp = await _get_client().get(path, params=params or {})
    resp.raise_for_status()
    return resp.json()


async def _proxy(path: str, params: dict | None = None) -> dict:
    ttl = _CACHE_TTL.get(path, 0)
    if ttl > 0:
        key = f"{path}|{sorted((params or {}).items())}"
        now = time.time()
        hit = _cache.get(key)
        if hit and hit[1] > now:
            return hit[0]
    try:
        data = await _okx_get(path, params)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"OKX 上游错误: {exc}") from exc
    if ttl > 0:
        _cache[key] = (data, time.time() + ttl)
    return data


@router.get("/tickers")
async def tickers(inst_type: str = Query("SPOT", pattern="^(SPOT|SWAP)$")):
    """某类交易对全部 ticker."""
    return await _proxy("/api/v5/market/tickers", {"instType": inst_type})


@router.get("/ticker/{inst_id}")
async def ticker(inst_id: str):
    """单交易对最新行情."""
    return await _proxy("/api/v5/market/ticker", {"instId": inst_id})


@router.get("/candles/{inst_id}")
async def candles(
    inst_id: str,
    bar: str = Query("1H"),
    limit: int = Query(100, ge=1, le=300),
):
    """K 线数据."""
    return await _proxy(
        "/api/v5/market/candles",
        {"instId": inst_id, "bar": bar, "limit": str(limit)},
    )


@router.get("/books/{inst_id}")
async def books(inst_id: str, sz: int = Query(20, ge=1, le=400)):
    """盘口深度 (App 详情页轮询; 手机直连 OKX WS 常被墙, 走服务端代理)."""
    return await _proxy("/api/v5/market/books", {"instId": inst_id, "sz": str(sz)})


@router.get("/trades/{inst_id}")
async def trades(inst_id: str, limit: int = Query(60, ge=1, le=500)):
    """最近逐笔成交 (新在前)."""
    return await _proxy(
        "/api/v5/market/trades", {"instId": inst_id, "limit": str(limit)}
    )


@router.get("/funding-rate/{inst_id}")
async def funding_rate(inst_id: str):
    """永续合约资金费率."""
    return await _proxy("/api/v5/public/funding-rate", {"instId": inst_id})
