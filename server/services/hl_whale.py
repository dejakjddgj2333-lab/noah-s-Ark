"""Hyperliquid 大额成交流 (免费模式巨鲸异动源).

订 HL 官方 WS trades 频道 (BTC/ETH/SOL/XRP/DOGE), 过滤 >= $300K 的大额单,
视为合约巨鲸异动. 内存环形缓冲 (最新 100 条), 接口直接读内存.

CoinGlass 的 hyperliquid/whale-alert 本质也是 HL 数据, 此为直连替代.
仅在 MARKET_DATA_SOURCE=free 时由 lifespan 启动.
"""
from __future__ import annotations

import asyncio
import json
import logging
from collections import deque

import websockets

logger = logging.getLogger(__name__)

_COINS = ["BTC", "ETH", "SOL", "XRP", "DOGE"]
_MIN_USD = 300_000  # 大额阈值

_buf: deque[dict] = deque(maxlen=100)  # 最新在前


async def _loop() -> None:
    url = "wss://api.hyperliquid.xyz/ws"
    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                for coin in _COINS:
                    await ws.send(json.dumps({
                        "method": "subscribe",
                        "subscription": {"type": "trades", "coin": coin},
                    }))
                logger.info("hl_ws_connected")
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                        if msg.get("channel") != "trades":
                            continue
                        for t in msg.get("data") or []:
                            usd = float(t.get("px") or 0) * float(t.get("sz") or 0)
                            if usd < _MIN_USD:
                                continue
                            # 结构对齐 CoinGlass whale-alert, 前端 _parseAlerts 直接消费
                            _buf.appendleft({
                                "symbol": t.get("coin"),
                                "side": "Buy" if t.get("side") == "B" else "Sell",
                                "positionSize": round(usd, 2),
                                "time": t.get("time"),
                                "user": "HL 大户",
                            })
                    except Exception:
                        continue
        except Exception as exc:
            logger.warning("hl_ws_down: %s", str(exc)[:200])
            await asyncio.sleep(10)


def start() -> asyncio.Task:
    return asyncio.create_task(_loop(), name="hl_whale_ws")


def whale_alerts() -> list:
    """最新大额成交 (新->旧), 接口直接透传."""
    return list(_buf)
