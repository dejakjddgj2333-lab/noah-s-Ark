"""爆仓自建聚合 (免费模式): Binance + Bybit 强平 WS -> hk_liq_events 表.

- Binance: wss !forceOrder@arr 全市场强平推送
- Bybit: v5 allLiquidation.<symbol> 按主流币订阅 (无全市场频道)
- 内存批量缓冲 5s 一写; 每小时清理 48h 前数据
- 供 overview 路由按 range (1h/4h/12h/24h) 聚合查询

仅在 MARKET_DATA_SOURCE=free 时由 lifespan 启动.
"""
from __future__ import annotations

import asyncio
import json
import logging
from datetime import datetime, timedelta

import websockets
from sqlalchemy import delete

from database import SessionLocal
from models.hk import HkLiqEvent

logger = logging.getLogger(__name__)

_BYBIT_SYMBOLS = [
    "BTCUSDT", "ETHUSDT", "SOLUSDT", "XRPUSDT", "DOGEUSDT",
    "BNBUSDT", "ADAUSDT", "AVAXUSDT", "LINKUSDT", "LTCUSDT",
]

_buf: list[HkLiqEvent] = []
_lock = asyncio.Lock()


def utc_now() -> datetime:
    return datetime.utcnow()


# ---------- WS 采集 ----------

async def _binance_loop() -> None:
    url = "wss://fstream.binance.com/ws/!forceOrder@arr"
    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                logger.info("liq_ws_connected: binance")
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                        for item in msg if isinstance(msg, list) else [msg]:
                            o = item.get("o") or {}
                            price = float(o.get("p") or 0)
                            qty = float(o.get("q") or 0)
                            # SELL 平多 = 多头爆仓; BUY 平空 = 空头爆仓
                            side = "long" if o.get("S") == "SELL" else "short"
                            await _add(HkLiqEvent(
                                ts=utc_now(),
                                exchange="Binance",
                                symbol=str(o.get("s") or ""),
                                side=side,
                                price=price,
                                qty=qty,
                                notional_usd=price * qty,
                            ))
                    except Exception:
                        continue
        except Exception as exc:
            logger.warning("liq_ws_binance_down: %s", str(exc)[:200])
            await asyncio.sleep(10)


async def _bybit_loop() -> None:
    url = "wss://stream.bybit.com/v5/public/linear"
    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                await ws.send(json.dumps({
                    "op": "subscribe",
                    "args": [f"allLiquidation.{s}" for s in _BYBIT_SYMBOLS],
                }))
                logger.info("liq_ws_connected: bybit")
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                        data = msg.get("data")
                        if not isinstance(data, dict):
                            continue
                        price = float(data.get("price") or 0)
                        qty = float(data.get("size") or 0)
                        # Bybit side=被强平仓位的持仓方向: Sell=空头持有? v5: side 为吃单方向
                        # allLiquidation 推送 side=仓位方向: "Sell"=做空仓位被平 -> 空头爆仓
                        side = "short" if data.get("side") == "Sell" else "long"
                        await _add(HkLiqEvent(
                            ts=utc_now(),
                            exchange="Bybit",
                            symbol=str(data.get("symbol") or ""),
                            side=side,
                            price=price,
                            qty=qty,
                            notional_usd=price * qty,
                        ))
                    except Exception:
                        continue
        except Exception as exc:
            logger.warning("liq_ws_bybit_down: %s", str(exc)[:200])
            await asyncio.sleep(10)


async def _add(ev: HkLiqEvent) -> None:
    async with _lock:
        _buf.append(ev)


# ---------- 落库 / 清理 ----------

async def _flush_loop() -> None:
    while True:
        await asyncio.sleep(5)
        async with _lock:
            batch, _buf[:] = _buf[:], []
        if not batch:
            continue
        try:
            async with SessionLocal() as db:
                db.add_all(batch)
                await db.commit()
        except Exception as exc:
            logger.warning("liq_flush_failed: %s", str(exc)[:200])


async def _prune_loop() -> None:
    while True:
        await asyncio.sleep(3600)
        try:
            async with SessionLocal() as db:
                await db.execute(
                    delete(HkLiqEvent).where(
                        HkLiqEvent.ts < utc_now() - timedelta(hours=48)
                    )
                )
                await db.commit()
        except Exception as exc:
            logger.warning("liq_prune_failed: %s", str(exc)[:200])


def start() -> list[asyncio.Task]:
    """lifespan 调用: 启动采集+落库+清理任务."""
    return [
        asyncio.create_task(_binance_loop(), name="liq_ws_binance"),
        asyncio.create_task(_bybit_loop(), name="liq_ws_bybit"),
        asyncio.create_task(_flush_loop(), name="liq_flush"),
        asyncio.create_task(_prune_loop(), name="liq_prune"),
    ]


# ---------- 聚合查询 (供路由) ----------

_RANGES = {"1h": 1, "4h": 4, "12h": 12, "24h": 24}


async def exchange_list(range_: str) -> list:
    """按时段聚合各所爆仓, 结构对齐 CoinGlass liquidation/exchange-list."""
    from sqlalchemy import func, select

    hours = _RANGES.get(range_, 24)
    since = utc_now() - timedelta(hours=hours)
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(
                    HkLiqEvent.exchange,
                    HkLiqEvent.side,
                    func.sum(HkLiqEvent.notional_usd),
                )
                .where(HkLiqEvent.ts >= since)
                .group_by(HkLiqEvent.exchange, HkLiqEvent.side)
            )
        ).all()

    agg: dict[str, dict[str, float]] = {}
    for exchange, side, total in rows:
        a = agg.setdefault(exchange, {"long": 0.0, "short": 0.0})
        a[side] = float(total or 0)

    return [
        {
            "exchange": ex,
            "longLiquidation_usd": a["long"],
            "shortLiquidation_usd": a["short"],
            "liquidation_usd": a["long"] + a["short"],
        }
        for ex, a in agg.items()
        if a["long"] + a["short"] > 0
    ]
