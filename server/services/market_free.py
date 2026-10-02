"""免费市场数据源: 不依赖 CoinGlass, 返回结构对齐 CoinGlass v4, 前端零改动.

- 恐慌贪婪: alternative.me (日级, 与 CoinGlass 同粒度)
- 各所资金费率: Binance + OKX + Bybit 公开接口, 单 symbol 实时
- 多空比: Binance 全局账户多空比 (5m 粒度)
- 山寨季: blockchaincenter (日级, best-effort)

所有函数失败抛异常或返回 None, 由路由层回落 (前端保留 mock).
"""
from __future__ import annotations

import logging
import time
from typing import Any

import httpx

logger = logging.getLogger(__name__)

_TIMEOUT = 12
_cache: dict[str, tuple[Any, float]] = {}


async def _get(url: str, params: dict | None = None, ttl: int = 60) -> Any:
    """GET JSON + TTL 缓存; 失败抛异常."""
    key = f"{url}|{sorted((params or {}).items())}"
    now = time.time()
    hit = _cache.get(key)
    if hit and hit[1] > now:
        return hit[0]
    async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
        resp = await client.get(url, params=params or {})
        resp.raise_for_status()
        data = resp.json()
    _cache[key] = (data, now + ttl)
    return data


# ---------- 恐慌贪婪 (alternative.me) ----------

async def fear_greed() -> dict | None:
    """返回 {"fear_greed": <0-100 int>} — 对齐 overview.sentiment 消费方."""
    body = await _get("https://api.alternative.me/fng/", {"limit": 1}, ttl=300)
    items = body.get("data") if isinstance(body, dict) else None
    if not items:
        return None
    return {"fear_greed": int(items[0]["value"])}


# ---------- 各所资金费率 (Binance/OKX/Bybit) ----------

# CoinGlass 费率为百分数 (0.01 = 0.01%); 各所原始为小数比率, 统一 *100.

async def _binance_funding(symbol: str) -> tuple[str, float] | None:
    body = await _get(
        "https://fapi.binance.com/fapi/v1/premiumIndex",
        {"symbol": f"{symbol}USDT"}, ttl=45,
    )
    rate = body.get("lastFundingRate")
    if rate is None:
        return None
    return ("Binance", float(rate) * 100)


async def _okx_funding(symbol: str) -> tuple[str, float] | None:
    body = await _get(
        "https://www.okx.com/api/v5/public/funding-rate",
        {"instId": f"{symbol}-USDT-SWAP"}, ttl=45,
    )
    data = body.get("data") if isinstance(body, dict) else None
    if not data:
        return None
    return ("OKX", float(data[0]["fundingRate"]) * 100)


async def _bybit_funding(symbol: str) -> tuple[str, float] | None:
    body = await _get(
        "https://api.bybit.com/v5/market/tickers",
        {"category": "linear", "symbol": f"{symbol}USDT"}, ttl=45,
    )
    lst = (body.get("result") or {}).get("list") if isinstance(body, dict) else None
    if not lst or not lst[0].get("fundingRate"):
        return None
    return ("Bybit", float(lst[0]["fundingRate"]) * 100)


async def funding_exchange_rates(symbol: str) -> list | None:
    """单 symbol 三所费率, 结构对齐 CoinGlass funding-rate/exchange-list:

    [{"symbol": ..., "stablecoin_margin_list": [{"exchange": ..., "funding_rate": ...}]}]
    """
    import asyncio
    import contextlib

    async def _safe(fn):
        with contextlib.suppress(Exception):
            return await fn
        return None

    results = await asyncio.gather(
        _safe(_binance_funding(symbol)),
        _safe(_okx_funding(symbol)),
        _safe(_bybit_funding(symbol)),
    )
    rows = [
        {"exchange": name, "funding_rate": round(rate, 6)}
        for r in results if r for name, rate in [r]
    ]
    if not rows:
        return None
    return [{"symbol": symbol.upper(), "stablecoin_margin_list": rows}]


# ---------- 多空比 (Binance 全局账户) ----------

async def long_short_ratio(symbol: str) -> dict:
    """返回 {"long_pct": float|None, "short_pct": float|None}."""
    try:
        body = await _get(
            "https://fapi.binance.com/futures/data/globalLongShortAccountRatio",
            {"symbol": f"{symbol.upper()}USDT", "period": "5m", "limit": 1},
            ttl=120,
        )
        if not body:
            return {"long_pct": None, "short_pct": None}
        latest = body[-1]
        return {
            "long_pct": float(latest["longAccount"]) * 100,
            "short_pct": float(latest["shortAccount"]) * 100,
        }
    except Exception:
        return {"long_pct": None, "short_pct": None}


# ---------- 山寨季 (CoinGecko 自算) ----------

# 稳定币/ wrapped 资产, 不计入山寨季
_ALT_EXCLUDE = {
    "bitcoin", "tether", "usd-coin", "dai", "first-digital-usd", "ethena-usde",
    "paypal-usd", "usdd", "frax", "true-usd", "wrapped-bitcoin", "staked-ether",
    "wrapped-steth", "binance-usd", "usds", "susds", "usdtb", "figure-heloc",
}


async def altcoin_season() -> dict | None:
    """山寨季指数 = 前50山寨中 30 天涨幅跑赢 BTC 的比例 (CoinGecko 自算).

    标准算法为 90 天窗口, 但 CoinGecko 免费档不支持 90d, 用 30d 近似;
    排除 BTC 与稳定币/wrapped, index = 跑赢数 / 50 * 100.
    >=75 山寨季, <=25 比特币季. 失败返回 None (前端保留 mock).
    """
    try:
        body = await _get(
            "https://api.coingecko.com/api/v3/coins/markets",
            {
                "vs_currency": "usd",
                "order": "market_cap_desc",
                "per_page": 80,
                "page": 1,
                "price_change_percentage": "30d",
            },
            ttl=3600,
        )
        if not isinstance(body, list):
            return None
        btc_30d = next(
            (c.get("price_change_percentage_30d_in_currency")
             for c in body if c.get("id") == "bitcoin"),
            None,
        )
        if btc_30d is None:
            return None
        alts = [
            c for c in body
            if c.get("id") not in _ALT_EXCLUDE
            and isinstance(c.get("price_change_percentage_30d_in_currency"), (int, float))
        ][:50]
        if len(alts) < 30:
            return None
        beats = sum(
            1 for c in alts
            if c["price_change_percentage_30d_in_currency"] > btc_30d
        )
        v = beats / len(alts) * 100
        return {
            "key": "altcoin_season",
            "name": "山寨季指数",
            "value": round(v, 1),
            "change_1d": None,
            "sparkline": [],
        }
    except Exception:
        return None
