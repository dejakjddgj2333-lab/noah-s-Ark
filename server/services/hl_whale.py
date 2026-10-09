"""大额成交流 (免费模式巨鲸异动源).

主源: Hyperliquid 官方 WS trades 频道 (BTC/ETH/SOL/XRP/DOGE).
备源: Binance 合约 aggTrade WS — HL 连续失败时自动启用, 恢复后停用.

过滤 >= $300K 的大额单, 视为合约巨鲸异动. 内存环形缓冲 (最新 100 条),
接口直接读内存. /whale-status 暴露连接状态便于排障.
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from collections import deque

import websockets

logger = logging.getLogger(__name__)

_COINS = ["BTC", "ETH", "SOL", "XRP", "DOGE"]
_MIN_USD = 300_000  # 大额阈值

_buf: deque[dict] = deque(maxlen=100)  # 最新在前
_seen: deque[tuple[str, int]] = deque(maxlen=300)  # (来源+symbol, time) 去重

# 连接状态 (whale-status 诊断用)
_hl_fails = 0
_hl_connected = False
_last_err = ""
_last_msg_at = 0.0


def _push(source: str, symbol: str, side: str, usd: float, ts: int) -> None:
    global _last_msg_at
    key = (f"{source}:{symbol}", ts)
    if key in _seen:
        return
    _seen.append(key)
    _last_msg_at = time.time()
    _buf.appendleft({
        "symbol": symbol,
        "side": side,
        "positionSize": round(usd, 2),
        "time": ts,
        "user": "HL 大户" if source == "hl" else "BN 大户",
    })


async def _hl_loop() -> None:
    """Hyperliquid trades WS; 连续失败置标, 由备源接管."""
    global _hl_fails, _hl_connected, _last_err
    url = "wss://api.hyperliquid.xyz/ws"
    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                for coin in _COINS:
                    await ws.send(json.dumps({
                        "method": "subscribe",
                        "subscription": {"type": "trades", "coin": coin},
                    }))
                _hl_connected = True
                _hl_fails = 0
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
                            _push("hl", t.get("coin") or "",
                                  "Buy" if t.get("side") == "B" else "Sell",
                                  usd, int(t.get("time") or 0))
                    except Exception:
                        continue
        except Exception as exc:
            _hl_connected = False
            _hl_fails += 1
            _last_err = str(exc)[:200]
            logger.warning("hl_ws_down(%d): %s", _hl_fails, _last_err)
            await asyncio.sleep(10)


async def _bn_loop() -> None:
    """Binance 合约 aggTrade WS 备源: HL 连续失败 >=3 次才启用, HL 恢复后闲置."""
    global _last_err
    symbols = [c.lower() + "usdt" for c in _COINS]
    url = "wss://fstream.binance.com/stream?streams=" + "/".join(
        f"{s}@aggTrade" for s in symbols)
    while True:
        if _hl_fails < 3:
            await asyncio.sleep(15)
            continue
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                logger.info("bn_whale_ws_connected (hl 备用源启用)")
                async for raw in ws:
                    try:
                        msg = json.loads(raw)
                        d = msg.get("data") or {}
                        if msg.get("stream", "").endswith("@aggTrade") is False:
                            continue
                        usd = float(d.get("p") or 0) * float(d.get("q") or 0)
                        if usd < _MIN_USD:
                            continue
                        sym = (d.get("s") or "").replace("USDT", "")
                        # m=True: 买方是做市方 → 主动卖
                        _push("bn", sym, "Sell" if d.get("m") else "Buy",
                              usd, int(d.get("T") or 0))
                    except Exception:
                        continue
        except Exception as exc:
            _last_err = f"bn: {str(exc)[:180]}"
            logger.warning("bn_whale_ws_down: %s", _last_err)
            await asyncio.sleep(10)


def start() -> list[asyncio.Task]:
    return [
        asyncio.create_task(_hl_loop(), name="hl_whale_ws"),
        asyncio.create_task(_bn_loop(), name="bn_whale_ws"),
    ]


def whale_alerts() -> list:
    """最新大额成交 (新->旧), 接口直接透传."""
    return list(_buf)


def status() -> dict:
    """连接诊断: /whale-status 用."""
    return {
        "buffered": len(_buf),
        "hl_connected": _hl_connected,
        "hl_fails": _hl_fails,
        "backup_active": _hl_fails >= 3,
        "last_error": _last_err,
        "last_msg_age_s": round(time.time() - _last_msg_at, 1) if _last_msg_at else None,
    }
