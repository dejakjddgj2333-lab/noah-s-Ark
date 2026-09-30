"""行情路由: 代理 OKX 公开 REST, 原样透传 {code, data}."""
from __future__ import annotations

import httpx
from fastapi import APIRouter, HTTPException, Query
from tenacity import retry, retry_if_exception_type, stop_after_attempt

from config import config

router = APIRouter(prefix="/market", tags=["行情"])

_TIMEOUT = 10


@retry(
    retry=retry_if_exception_type(httpx.HTTPError),
    stop=stop_after_attempt(2),
    reraise=True,
)
async def _okx_get(path: str, params: dict | None = None) -> dict:
    """GET OKX 公开接口, 网络错误重试 1 次. 返回原始 JSON."""
    async with httpx.AsyncClient(base_url=config.okx_base_url, timeout=_TIMEOUT) as client:
        resp = await client.get(path, params=params or {})
        resp.raise_for_status()
        return resp.json()


async def _proxy(path: str, params: dict | None = None) -> dict:
    try:
        return await _okx_get(path, params)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"OKX 上游错误: {exc}") from exc


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


@router.get("/funding-rate/{inst_id}")
async def funding_rate(inst_id: str):
    """永续合约资金费率."""
    return await _proxy("/api/v5/public/funding-rate", {"instId": inst_id})
