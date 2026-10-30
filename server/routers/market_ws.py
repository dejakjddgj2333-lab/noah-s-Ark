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

from services.market_ws_hub import hub

router = APIRouter(tags=["行情WS"])

ALLOWED_CHANNELS = {"tickers", "books5", "trades"}
INST_RE = re.compile(r"^[A-Z0-9][A-Z0-9-]{2,31}$")
MAX_SUBS_PER_CLIENT = 40


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
        await hub.subscribe(channel, inst_id, q)

    async def drop_sub(channel: str, inst_id: str) -> None:
        key = (channel, inst_id)
        entry = forwards.pop(key, None)
        if entry is None:
            return
        q, task = entry
        task.cancel()
        await hub.unsubscribe(channel, inst_id, q)

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
                if channel not in ALLOWED_CHANNELS or not INST_RE.match(inst_id):
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
            await hub.unsubscribe(channel, inst_id, q)
