"""大额成交流 (免费模式巨鲸异动源).

主源: Hyperliquid 官方 WS trades 频道 (BTC/ETH/SOL/XRP/DOGE).
备源: Binance 合约 aggTrade WS — HL 连续失败时自动启用, 恢复后停用.

过滤 >= $300K 的大额单, 视为合约巨鲸异动. 内存环形缓冲 (最新 100 条),
接口直接读内存. /whale-status 暴露连接状态便于排障.
命中订阅 (hk_whale_subscriptions) 的大额单会异步 fan-out APNs 推送.
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
_PUSH_COOLDOWN_SEC = 300  # 同用户同币种推送冷却, 防刷屏

_buf: deque[dict] = deque(maxlen=100)  # 最新在前
_seen: deque[tuple[str, int]] = deque(maxlen=300)  # (来源+symbol, time) 去重
_push_cooldown: dict[tuple[int, str], float] = {}  # (user_id, symbol) -> 上次推送时间

# 连接状态 (whale-status 诊断用)
_hl_fails = 0
_hl_connected = False
_last_err = ""
_last_msg_at = 0.0


async def _notify_subscribers(alert: dict) -> None:
    """大额成交 fan-out: 命中订阅条件的用户推 APNs (在线用户跳过, App 内走 WS 刷新)."""
    from sqlalchemy import select

    from database import SessionLocal
    from models.hk import HkWhaleSubscription
    from services import push_service

    symbol = alert["symbol"]
    usd = alert["positionSize"]
    try:
        async with SessionLocal() as db:
            result = await db.execute(
                select(HkWhaleSubscription).where(
                    HkWhaleSubscription.enabled.is_(True),
                    HkWhaleSubscription.min_usd <= usd,
                )
            )
            subs = result.scalars().all()
            if not subs:
                return
            side_zh = "买入" if alert["side"] == "Buy" else "卖出"
            title = f"{symbol} 巨鲸异动"
            body = (
                f"{alert['user']}{side_zh} {symbol} "
                f"约 {usd / 10_000:,.1f} 万美元"
            )
            now = time.time()
            for s in subs:
                try:
                    symbols = json.loads(s.symbols or "[]")
                except ValueError:
                    symbols = []
                if symbols and symbol not in symbols:
                    continue
                key = (s.user_id, symbol)
                if now - _push_cooldown.get(key, 0) < _PUSH_COOLDOWN_SEC:
                    continue
                _push_cooldown[key] = now
                await push_service.push_if_offline(
                    db, s.user_id, title, body,
                    {"type": "whale", "symbol": symbol},
                )
    except Exception as exc:
        logger.warning("whale_fanout_error: %s", str(exc)[:200])


def _push(source: str, symbol: str, side: str, usd: float, ts: int) -> None:
    global _last_msg_at
    key = (f"{source}:{symbol}", ts)
    if key in _seen:
        return
    _seen.append(key)
    _last_msg_at = time.time()
    alert = {
        "symbol": symbol,
        "side": side,
        "positionSize": round(usd, 2),
        "time": ts,
        "user": "HL 大户" if source == "hl" else "BN 大户",
    }
    _buf.appendleft(alert)
    try:
        asyncio.get_running_loop().create_task(_notify_subscribers(alert))
    except RuntimeError:
        pass  # 无事件循环 (测试直调), 跳过推送


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
    """Binance 合约 aggTrade WS: 常开双源 (HL 清淡期也能持续供数), 按 (源,symbol,ts) 去重."""
    global _last_err
    symbols = [c.lower() + "usdt" for c in _COINS]
    url = "wss://fstream.binance.com/stream?streams=" + "/".join(
        f"{s}@aggTrade" for s in symbols)
    while True:
        try:
            async with websockets.connect(url, ping_interval=20) as ws:
                logger.info("bn_whale_ws_connected")
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
        "dual_source": True,  # HL + Binance 常开双源
        "last_error": _last_err,
        "last_msg_age_s": round(time.time() - _last_msg_at, 1) if _last_msg_at else None,
    }
