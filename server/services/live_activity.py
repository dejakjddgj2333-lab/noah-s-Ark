"""Live Activities 服务端循环: 定时把盯盘币种最新价推给活跃 activity token.

数据源: Binance 24hr ticker (含 priceChangePercent, 一次请求拿价+涨跌幅).
清理策略: 发送失败 (token 失效) 即删; updated_at 超 48h 未刷新 (App 已结束 activity) 即删.
"""
from __future__ import annotations

from collections import defaultdict
from datetime import timedelta

import httpx
import structlog
from sqlalchemy import delete, select

from database import SessionLocal
from models.hk import HkLiveActivityToken, utc_now
from services import push_service

logger = structlog.get_logger("hk.live_activity")

_TICKER_URL = "https://api.binance.com/api/v3/ticker/24hr"
_STALE_HOURS = 48


def _pair(symbol: str) -> str:
    return symbol if symbol.endswith("USDT") else f"{symbol}USDT"


async def _fetch_24h(symbol: str) -> tuple[float, float] | None:
    """拿单币最新价 + 24h 涨跌幅; 失败返回 None."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(_TICKER_URL, params={"symbol": _pair(symbol)})
            r.raise_for_status()
            d = r.json()
            return float(d["lastPrice"]), round(float(d["priceChangePercent"]), 2)
    except Exception as exc:
        logger.warning("live_price_fetch_failed", symbol=symbol, err=str(exc)[:200])
        return None


async def push_updates() -> None:
    """一轮更新: 按 symbol 分组查价, 逐 token 推 content-state."""
    async with SessionLocal() as db:
        # 先清理过期 token (App 结束 activity 后不会再刷新 updated_at)
        cutoff = utc_now() - timedelta(hours=_STALE_HOURS)
        await db.execute(
            delete(HkLiveActivityToken).where(
                HkLiveActivityToken.updated_at < cutoff
            )
        )
        result = await db.execute(select(HkLiveActivityToken))
        tokens = result.scalars().all()
        if not tokens:
            await db.commit()
            return

        by_symbol: dict[str, list[HkLiveActivityToken]] = defaultdict(list)
        for t in tokens:
            by_symbol[t.symbol].append(t)

        for symbol, rows in by_symbol.items():
            got = await _fetch_24h(symbol)
            if got is None:
                continue
            price, change_pct = got
            state = {"price": price, "changePct": change_pct}
            for row in rows:
                ok = await push_service.send_live_activity(row.push_token, state)
                if not ok:
                    await db.delete(row)
        await db.commit()
