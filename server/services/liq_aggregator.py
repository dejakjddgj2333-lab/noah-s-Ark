"""爆仓自建聚合 (免费模式): Binance + Bybit + OKX 强平 WS -> hk_liq_events 表.

- Binance: wss !forceOrder@arr 全市场强平推送 (部分网络被静默黑洞, 保留兜底)
- Bybit: v5 allLiquidation.<symbol> 按主流币订阅 (无全市场频道)
- OKX: liquidation-orders 全 SWAP (主力源, 连通性最好)
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
                            # 强平成交价/量: ap(均价)*z(成交量) 优先, 市价单 ap 可能 0, 兜底 p*q
                            price = float(o.get("ap") or 0) or float(o.get("p") or 0)
                            qty = float(o.get("z") or 0) or float(o.get("q") or 0)
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
                        # Bybit v5 allLiquidation 字段: s=symbol, S=仓位方向, v=量, p=价
                        price = float(data.get("p") or 0)
                        qty = float(data.get("v") or 0)
                        # S=仓位方向: "Sell"=空头仓位被强平 -> 空头爆仓
                        side = "short" if data.get("S") == "Sell" else "long"
                        await _add(HkLiqEvent(
                            ts=utc_now(),
                            exchange="Bybit",
                            symbol=str(data.get("s") or ""),
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


async def _okx_loop() -> None:
    """OKX 公共强平频道 (全 SWAP). 服务器到 OKX 通畅 (行情/费率同源).

    sz 为合约张数, 名义额 = px * sz * ctVal (合约面值, 启动时拉一次).
    """
    import httpx

    url = "wss://ws.okx.com:8443/ws/v5/public"
    ct_val: dict[str, float] = {}
    try:
        async with httpx.AsyncClient(timeout=12) as client:
            resp = await client.get(
                "https://www.okx.com/api/v5/public/instruments",
                params={"instType": "SWAP"},
            )
            for it in (resp.json().get("data") or []):
                v = float(it.get("ctVal") or 1)
                ct_val[str(it.get("instId") or "")] = v
        logger.info("liq_okx_instruments: %d", len(ct_val))
    except Exception as exc:
        logger.warning("liq_okx_instruments_failed: %s", str(exc)[:200])

    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                await ws.send(json.dumps({
                    "op": "subscribe",
                    "args": [{"channel": "liquidation-orders", "instType": "SWAP"}],
                }))
                logger.info("liq_ws_connected: okx")
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                        data = msg.get("data")
                        if not isinstance(data, list):
                            continue
                        for d in data:
                            inst_id = str(d.get("instId") or "")
                            ct = ct_val.get(inst_id, 1.0)
                            # 强平明细在外层 details 数组: bkPx=破产价, sz=张数
                            for det in (d.get("details") or []):
                                price = float(det.get("bkPx") or 0)
                                qty = float(det.get("sz") or 0) * ct
                                # posSide=被强平仓位方向; net 按吃单方向推: sell=平多
                                pos = det.get("posSide") or "net"
                                if pos in ("long", "short"):
                                    side = pos
                                else:
                                    side = "long" if det.get("side") == "sell" else "short"
                                await _add(HkLiqEvent(
                                    ts=utc_now(),
                                    exchange="OKX",
                                    symbol=inst_id.replace("-SWAP", ""),
                                    side=side,
                                    price=price,
                                    qty=qty,
                                    notional_usd=price * qty,
                                ))
                    except Exception:
                        continue
        except Exception as exc:
            logger.warning("liq_ws_okx_down: %s", str(exc)[:200])
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
        asyncio.create_task(_okx_loop(), name="liq_ws_okx"),
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
