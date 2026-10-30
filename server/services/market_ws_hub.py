"""OKX 公共行情 WS 中转枢纽: 全站单连接, 订阅引用计数, 本地队列扇出.

- 每个 (channel, instId) 只在 OKX 侧订阅一次, N 个客户端共享
- OKX 断线指数退避重连, 重连后按当前引用集合全量重订阅
- 客户端队列满即丢帧 (慢客户端不拖垮枢纽)
"""
from __future__ import annotations

import asyncio
import json
import logging

import websockets

log = logging.getLogger("market_ws_hub")

OKX_WS = "wss://ws.okx.com:8443/ws/v5/public"


class MarketHub:
    def __init__(self) -> None:
        self._subs: dict[tuple[str, str], set[asyncio.Queue]] = {}
        self._ws = None
        self._lock = asyncio.Lock()
        self._runner: asyncio.Task | None = None

    def _ensure_runner(self) -> None:
        if self._runner is None or self._runner.done():
            self._runner = asyncio.create_task(self._run())

    async def subscribe(self, channel: str, inst_id: str, q: asyncio.Queue) -> None:
        key = (channel, inst_id)
        async with self._lock:
            targets = self._subs.setdefault(key, set())
            first = not targets
            targets.add(q)
        self._ensure_runner()
        if first:
            await self._send_op("subscribe", channel, inst_id)

    async def unsubscribe(self, channel: str, inst_id: str, q: asyncio.Queue) -> None:
        key = (channel, inst_id)
        empty = False
        async with self._lock:
            targets = self._subs.get(key)
            if targets is not None and q in targets:
                targets.discard(q)
                if not targets:
                    self._subs.pop(key, None)
                    empty = True
        if empty:
            await self._send_op("unsubscribe", channel, inst_id)

    async def _send_op(self, op: str, channel: str, inst_id: str) -> None:
        ws = self._ws
        if ws is None:
            return  # 断线中: 重连后按 _subs 全量重订阅, 不丢
        try:
            await ws.send(
                json.dumps({"op": op, "args": [{"channel": channel, "instId": inst_id}]})
            )
        except Exception:
            pass  # 发送失败等同断线, 重连全量恢复

    async def _run(self) -> None:
        backoff = 1
        while True:
            try:
                async with websockets.connect(OKX_WS, ping_interval=None) as ws:
                    self._ws = ws
                    backoff = 1
                    async with self._lock:
                        args = [
                            {"channel": c, "instId": i} for (c, i) in self._subs.keys()
                        ]
                    if args:
                        await ws.send(json.dumps({"op": "subscribe", "args": args}))
                    pinger = asyncio.create_task(self._ping(ws))
                    try:
                        async for raw in ws:
                            self._fanout(raw)
                    finally:
                        pinger.cancel()
            except asyncio.CancelledError:
                raise
            except Exception as e:  # 断线/握手失败: 退避重连
                log.warning("okx ws disconnected: %s", e)
            finally:
                self._ws = None
            # 没有任何订阅时停摆, 等新订阅唤醒
            async with self._lock:
                idle = not self._subs
            if idle:
                return
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, 30)

    @staticmethod
    async def _ping(ws) -> None:
        while True:
            await asyncio.sleep(25)
            await ws.send("ping")

    def _fanout(self, raw: str) -> None:
        try:
            arg = (json.loads(raw).get("arg") or {})
        except (TypeError, ValueError):
            return
        targets = self._subs.get((arg.get("channel"), arg.get("instId")))
        if not targets:
            return
        for q in list(targets):
            try:
                q.put_nowait(raw)
            except asyncio.QueueFull:
                pass  # 慢客户端丢帧


hub = MarketHub()
