"""市场总览: 双数据源.

- coinglass: CoinGlass v4 透传 (需续费 key), 带内存 TTL 缓存
- free: 免费源直连 (alternative.me / Binance / OKX / Bybit / HL / 自建爆仓聚合),
  返回结构对齐 CoinGlass, 前端零改动

切换: MARKET_DATA_SOURCE=coinglass|free; coinglass 模式无 key 时自动回落 free.
"""
from __future__ import annotations

import time
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Query

from config import config
from services import hl_whale, liq_aggregator, market_free

router = APIRouter(prefix="/market-overview", tags=["市场总览"])

_BASE = "https://open-api-v4.coinglass.com"
_TIMEOUT = 15


def _use_coinglass() -> bool:
    """coinglass 模式且 key 存在才走 CoinGlass."""
    return (
        config.market_data_source.lower() == "coinglass"
        and bool(config.coinglass_api_key)
    )


@router.get("/source")
async def get_source():
    """当前数据源标识. 前端据此隐藏 CoinGlass 独有内容 (链上转账类巨鲸异动)."""
    return {"source": "coinglass" if _use_coinglass() else "free"}

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
    """恐慌贪婪指数(最新). free=alternative.me, coinglass=fear-greed-history 末位."""
    if not _use_coinglass():
        r = await market_free.fear_greed()
        if r is None:
            raise HTTPException(status_code=502, detail="alternative.me 上游错误")
        return r
    data = await _cg_get("/api/index/fear-greed-history", ttl=300)
    values = data.get("data_list") if isinstance(data, dict) else data
    return {"fear_greed": values[-1] if values else None}


@router.get("/liquidations/exchange-list")
async def get_liq_exchange_list(range: str = Query("24h")):
    """各交易所爆仓统计. range: 1h/4h/12h/24h.
    free=自建聚合 (Binance/Bybit WS 实时流), coinglass=CoinGlass."""
    if not _use_coinglass():
        return {"range": range, "data": await liq_aggregator.exchange_list(range)}
    data = await _cg_get("/api/futures/liquidation/exchange-list", {"range": range}, ttl=60)
    return {"range": range, "data": data}


@router.get("/funding/exchange-rates")
async def get_funding_exchange_rates(symbol: str = Query("BTC")):
    """单币种各所实时费率. free=Binance/OKX/Bybit 聚合."""
    if not _use_coinglass():
        data = await market_free.funding_exchange_rates(symbol)
        return {"symbol": symbol.upper(), "data": data or []}
    data = await _cg_get(
        "/api/futures/funding-rate/exchange-list", {"symbol": symbol.upper()}, ttl=60
    )
    return {"symbol": symbol.upper(), "data": data}


@router.get("/funding/history")
async def get_funding_history(symbol: str = Query("BTC")):
    """资金费率近 7 日历史 (8H 一期, 升序). free=OKX funding-rate-history."""
    if not _use_coinglass():
        data = await market_free.funding_history(symbol)
        return {"symbol": symbol.upper(), "history": data or []}
    data = await _cg_get(
        "/api/futures/funding-rate/history",
        {"exchange": "Binance", "symbol": f"{symbol.upper()}USDT", "interval": "8h", "limit": 21},
        ttl=600,
    )
    # CoinGlass 升序时间列, 对齐 free 结构
    hist = [
        {"ts": d.get("time"), "rate": d.get("close")}
        for d in (data or []) if isinstance(d, dict)
    ]
    return {"symbol": symbol.upper(), "history": hist}


@router.get("/open-interest")
async def get_open_interest():
    """未平仓合约名义额. free=OKX BTC+ETH 永续 oiUsd 合计."""
    if not _use_coinglass():
        data = await market_free.open_interest()
        return data or {"oi_usd": None}
    data = await _cg_get("/api/futures/open-interest/aggregated-history",
                         {"symbol": "BTC", "interval": "1d", "limit": 1}, ttl=300)
    latest = data[-1] if isinstance(data, list) and data else {}
    return {"oi_usd": latest.get("close")}


@router.get("/whale-alerts")
async def get_whale_alerts():
    """巨鲸异动. 固定走 Hyperliquid 大额成交流 (免费源):
    直连 HL WS 数据比 CoinGlass hyperliquid/whale-alert 更全, 两种模式统一."""
    return {"alerts": hl_whale.whale_alerts()}


# ---------- 横幅全局数据 (CoinGecko) ----------

# path -> (data, expire_at); 独立于 CoinGlass 的小缓存
_gecko_cache: dict[str, tuple[Any, float]] = {}

_GECKO_GLOBAL_NULL = {
    "total_market_cap_usd": None,
    "total_volume_usd": None,
    "market_cap_change_pct_24h": None,
    "btc_dominance": None,
    "eth_dominance": None,
}


@router.get("/global-stats")
async def get_global_stats():
    """横幅全局数据(市值/成交/占比). 失败返回全 null + 200, 前端回退 mock."""
    now = time.time()
    hit = _gecko_cache.get("global")
    if hit and hit[1] > now:
        return hit[0]

    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get("https://api.coingecko.com/api/v3/global")
            body = resp.json()
        d = body["data"]
        out = {
            "total_market_cap_usd": (d.get("total_market_cap") or {}).get("usd"),
            "total_volume_usd": (d.get("total_volume") or {}).get("usd"),
            "market_cap_change_pct_24h": d.get("market_cap_change_percentage_24h_usd"),
            "btc_dominance": (d.get("market_cap_percentage") or {}).get("btc"),
            "eth_dominance": (d.get("market_cap_percentage") or {}).get("eth"),
        }
    except Exception:
        out = dict(_GECKO_GLOBAL_NULL)

    _gecko_cache["global"] = (out, now + 600)
    return out


# ---------- 链上流动性异动总览 (DefiLlama) ----------

# key -> (data, expire_at); 独立于 CoinGlass/Gecko 的小缓存
_llama_cache: dict[str, tuple[Any, float]] = {}

_STABLE_NULL = {"stable_total_usd": None, "stable_change_1d_pct": None, "top_stables": []}
_TVL_NULL = {"tvl_total_usd": None, "tvl_change_1d_pct": None}


def _pct(cur: Any, prev: Any) -> float | None:
    """(cur-prev)/prev*100, 任一缺失/除零返回 None."""
    if not isinstance(cur, (int, float)) or not isinstance(prev, (int, float)):
        return None
    if not prev:
        return None
    return (cur - prev) / prev * 100.0


async def _fetch_stables() -> dict:
    """稳定币总流通 + 24h 变化 + Top5. 失败返回全 null."""
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get(
                "https://stablecoins.llama.fi/stablecoins",
                params={"includePrices": "true"},
            )
            body = resp.json()
        assets = body.get("peggedAssets") or []
        usd = [a for a in assets if isinstance(a, dict) and a.get("pegType") == "peggedUSD"]

        total = 0.0
        prev_total = 0.0
        rows = []
        for a in usd:
            cur = (a.get("circulating") or {}).get("peggedUSD")
            prev = (a.get("circulatingPrevDay") or {}).get("peggedUSD")
            if isinstance(cur, (int, float)):
                total += cur
                if isinstance(prev, (int, float)):
                    prev_total += prev
                # 上游给了 change_1d 直接用, 否则用昨值推算
                chg = a.get("change_1d")
                if not isinstance(chg, (int, float)):
                    chg = _pct(cur, prev)
                rows.append({
                    "name": a.get("symbol") or a.get("name") or "?",
                    "circulating_usd": cur,
                    "change_1d_pct": chg,
                })
        rows.sort(key=lambda r: r["circulating_usd"], reverse=True)
        return {
            "stable_total_usd": total or None,
            "stable_change_1d_pct": _pct(total, prev_total),
            "top_stables": rows[:5],
        }
    except Exception:
        return dict(_STABLE_NULL)


async def _fetch_tvl() -> dict:
    """DeFi 全网 TVL + 24h 变化 (取末两点). 失败返回全 null."""
    try:
        async with httpx.AsyncClient(timeout=_TIMEOUT) as client:
            resp = await client.get("https://api.llama.fi/v2/historicalChainTvl")
            body = resp.json()
        pts = [p for p in body if isinstance(p, dict) and isinstance(p.get("tvl"), (int, float))]
        if len(pts) < 2:
            return dict(_TVL_NULL)
        last, prev = pts[-1]["tvl"], pts[-2]["tvl"]
        return {"tvl_total_usd": last, "tvl_change_1d_pct": _pct(last, prev)}
    except Exception:
        return dict(_TVL_NULL)


@router.get("/liquidity")
async def get_liquidity():
    """链上流动性总览 (DefiLlama): 稳定币流通 + DeFi TVL, 各带 24h 变化.

    任一来源失败仅该块字段为 null, 永不 500; 前端回退 mock. 缓存 300s.
    """
    now = time.time()
    hit = _llama_cache.get("liquidity")
    if hit and hit[1] > now:
        return hit[0]

    stables, tvl = await _fetch_stables(), await _fetch_tvl()
    out = {**stables, **tvl}
    _llama_cache["liquidity"] = (out, now + 300)
    return out


# ---------- 多空比 ----------

@router.get("/long-short-ratio")
async def get_long_short_ratio(symbol: str = Query("BTC")):
    """多头主导: 全局账户多空占比.
    free=Binance 5m 实时, coinglass=CoinGlass history 最新一日."""
    if not _use_coinglass():
        return await market_free.long_short_ratio(symbol)
    try:
        data = await _cg_get(
            "/api/futures/global-long-short-account-ratio/history",
            {
                "exchange": "Binance",
                "symbol": f"{symbol.upper()}USDT",
                "interval": "1d",
                "limit": 2,
            },
            ttl=300,
        )
        latest = data[-1] if isinstance(data, list) and data else None
        return {
            "long_pct": (latest or {}).get("global_account_long_percent"),
            "short_pct": (latest or {}).get("global_account_short_percent"),
        }
    except HTTPException:
        return {"long_pct": None, "short_pct": None}


# ---------- 多维指数卡 ----------

# key -> (中文名, path, 值字段); 数据均为时间升序列表, 最新在末位
_INDICATORS: dict[str, tuple[str, str, str]] = {
    "ahr999": ("AHR999 抄底指标", "/api/index/ahr999", "ahr999_value"),
    "pi_cycle": ("Pi Cycle 顶部指标", "/api/index/pi-cycle-indicator", "price"),
    "puell": ("Puell 倍数", "/api/index/puell-multiple", "puell_multiple"),
    "btc_dominance": ("BTC 市值占比", "/api/index/bitcoin-dominance", "bitcoin_dominance"),
    "altcoin_season": ("山寨季指数", "/api/index/altcoin-season", "altcoin_index"),
    "cgdi": ("CGDI 衍生品指数", "/api/futures/cgdi-index/history", "cgdi_index_value"),
    "cdri": ("CDRI 衍生品风险指数", "/api/futures/cdri-index/history", "cdri_index_value"),
}


@router.get("/indicators")
async def get_indicators():
    """多维指数卡: 最新值 + 1d 变化 + 近 30 值 sparkline. 单项失败跳过该项.
    free 模式仅山寨季 (blockchaincenter), 其余指标为 CoinGlass 独有."""
    if not _use_coinglass():
        alt = await market_free.altcoin_season()
        return {"indicators": [alt] if alt else []}
    out = []
    for key, (name, path, field) in _INDICATORS.items():
        try:
            data = await _cg_get(path, ttl=300)
        except HTTPException:
            continue
        if not isinstance(data, list) or not data:
            continue
        series = [x.get(field) for x in data if isinstance(x, dict) and x.get(field) is not None]
        if not series:
            continue
        latest = series[-1]
        prev = series[-2] if len(series) > 1 else None
        change = (latest - prev) if (latest is not None and prev is not None) else None
        out.append({
            "key": key,
            "name": name,
            "value": latest,
            "change_1d": change,
            "sparkline": series[-30:],
        })
    return {"indicators": out}


# ---------- 实时爆仓 / 爆仓补充 ----------

@router.get("/liquidations/orders")
async def get_liq_orders(
    min_amount: int = Query(100000),
    limit: int = Query(50),
):
    """实时大额爆仓单(最新在前), 原始字段透传前端解析. 仅 coinglass 模式."""
    if not _use_coinglass():
        return {"orders": []}
    data = await _cg_get(
        "/api/futures/liquidation/order",
        {"min_liquidation_amount": min_amount, "limit": limit},
        ttl=20,
    )
    return {"orders": data}


@router.get("/liquidations/coin-list")
async def get_liq_coin_list():
    """各币 24h 爆仓(人数/多空明细), 原始字段透传. 仅 coinglass 模式."""
    if not _use_coinglass():
        return {"coins": []}
    data = await _cg_get("/api/futures/liquidation/coin-list", ttl=60)
    return {"coins": data}
