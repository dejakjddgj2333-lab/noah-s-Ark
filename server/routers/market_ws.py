"""行情 WebSocket 网关: 客户端 <-> OKX 公共频道中转 (复用 hub 单连接).

行情 REST 本就匿名公开, WS 同样免鉴权; 仅做频道白名单 + 每客户端订阅数上限.
客户端协议 (JSON 文本帧):
  {"op": "subscribe",   "args": [{"channel": "tickers", "instId": "BTC-USDT"}]}
  {"op": "unsubscribe", "args": [...]}
服务端原样转发 OKX 数据帧; 入站的 "ping" 文本回 "pong".
"""
from __future__ import annotations

import asyncio
import json
import re

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from services.market_ws_hub import hub, hub_candle

router = APIRouter(tags=["行情WS"])

ALLOWED_CHANNELS = {"tickers", "books5", "trades"}
# K线蜡烛频道: candle15m / candle1H / candle4H / candle1D / candle1W 等
CANDLE_RE = re.compile(r"^candle\d+[mHDWM]$")
INST_RE = re.compile(r"^[A-Z0-9][A-Z0-9-]{2,31}$")
MAX_SUBS_PER_CLIENT = 40


def _hub_for(channel: str):
    # 蜡烛频道走 OKX business 端点, 其余走 public
    return hub_candle if CANDLE_RE.match(channel) else hub


@router.websocket("/market/ws")
async def market_gateway(websocket: WebSocket):
    await websocket.accept()
    forwards: dict[tuple[str, str], tuple[asyncio.Queue, asyncio.Task]] = {}

    async def forward(q: asyncio.Queue) -> None:
        while True:
            raw = await q.get()
            await websocket.send_text(raw)

    async def add_sub(channel: str, inst_id: str) -> None:
        key = (channel, inst_id)
        if key in forwards or len(forwards) >= MAX_SUBS_PER_CLIENT:
            return
        q: asyncio.Queue = asyncio.Queue(maxsize=200)
        task = asyncio.create_task(forward(q))
        forwards[key] = (q, task)
        await _hub_for(channel).subscribe(channel, inst_id, q)

    async def drop_sub(channel: str, inst_id: str) -> None:
        key = (channel, inst_id)
        entry = forwards.pop(key, None)
        if entry is None:
            return
        q, task = entry
        task.cancel()
        await _hub_for(channel).unsubscribe(channel, inst_id, q)

    try:
        while True:
            raw = await websocket.receive_text()
            if raw == "ping":
                await websocket.send_text("pong")
                continue
            try:
                frame = json.loads(raw)
            except (TypeError, ValueError):
                continue
            op = frame.get("op")
            args = frame.get("args")
            if op not in ("subscribe", "unsubscribe") or not isinstance(args, list):
                continue
            for a in args[:10]:
                if not isinstance(a, dict):
                    continue
                channel = str(a.get("channel") or "")
                inst_id = str(a.get("instId") or "").upper()
                if channel not in ALLOWED_CHANNELS and not CANDLE_RE.match(channel):
                    continue
                if not INST_RE.match(inst_id):
                    continue
                if op == "subscribe":
                    await add_sub(channel, inst_id)
                else:
                    await drop_sub(channel, inst_id)
    except WebSocketDisconnect:
        pass
    finally:
        for (channel, inst_id), (q, task) in list(forwards.items()):
            task.cancel()
            await _hub_for(channel).unsubscribe(channel, inst_id, q)
