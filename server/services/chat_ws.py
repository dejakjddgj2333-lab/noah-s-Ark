"""聊天 WebSocket 连接管理: user_id -> 多连接, 内存态."""
from __future__ import annotations

import asyncio
from typing import Any

from fastapi import WebSocket


class ChatWsManager:
    """内存连接表: 每用户多设备, 按 user_id 投递."""

    def __init__(self) -> None:
        self._conns: dict[int, set[WebSocket]] = {}
        self._lock = asyncio.Lock()

    async def connect(self, user_id: int, ws: WebSocket) -> None:
        async with self._lock:
            self._conns.setdefault(user_id, set()).add(ws)

    async def disconnect(self, user_id: int, ws: WebSocket) -> None:
        async with self._lock:
            conns = self._conns.get(user_id)
            if conns:
                conns.discard(ws)
                if not conns:
                    self._conns.pop(user_id, None)

    async def deliver_to_user(self, user_id: int, payload: dict[str, Any]) -> None:
        async with self._lock:
            conns = list(self._conns.get(user_id, ()))
        dead = []
        for ws in conns:
            try:
                await ws.send_json(payload)
            except Exception:
                dead.append(ws)
        if dead:
            async with self._lock:
                for ws in dead:
                    self._conns.get(user_id, set()).discard(ws)

    async def deliver_to_users(
        self, user_ids: list[int], payload: dict[str, Any]
    ) -> None:
        await asyncio.gather(
            *(self.deliver_to_user(uid, payload) for uid in user_ids),
            return_exceptions=True,
        )


chat_ws = ChatWsManager()
