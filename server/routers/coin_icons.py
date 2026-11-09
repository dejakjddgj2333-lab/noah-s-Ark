"""币种图标: 服务端代取 + 落盘缓存 (图标本地化).

背景: 客户端直连 static.okx.com 在国内网络不稳定 (大量图标加载失败),
改为由服务端从 OKX CDN 拉取并持久缓存, 客户端只请求自有域名:

  GET /api/coin-icon/{base}.png   base = 小写币种代码 (btc/eth/...)

- 命中磁盘缓存直接返回 (7 天 immutable 缓存头)
- 未命中服务端回源 OKX, 原子写盘后返回; 同币种并发只回源一次
- 回源失败 404 + 内存负缓存 10 分钟防打爆上游, 客户端回退首字母圆

持久化: 生产由 docker-compose 把宿主机 ./coin-icons 挂到 /data/coin-icons
(COIN_ICON_DIR 指定), rsync --delete / 容器重建均不丢; 本地开发默认
server/static/coin-icons.
"""
from __future__ import annotations

import asyncio
import os
import re
import time
from pathlib import Path

import httpx
from fastapi import APIRouter, Response
from fastapi.responses import FileResponse

router = APIRouter(prefix="/coin-icon", tags=["币种图标"])

_BASE_RE = re.compile(r"^[a-z0-9]{1,20}$")
_UPSTREAM = "https://static.okx.com/cdn/oksupport/asset/currency/icon/{}.png"
_TIMEOUT = 8
_NEG_TTL = 600  # 回源失败负缓存秒数
_OK_HEADERS = {"Cache-Control": "public, max-age=604800, immutable"}
_MISS_HEADERS = {"Cache-Control": "public, max-age=60"}

_ICON_DIR = Path(
    os.getenv("COIN_ICON_DIR")
    or Path(__file__).resolve().parent.parent / "static" / "coin-icons"
)

_client: httpx.AsyncClient | None = None
_lock = asyncio.Lock()
_neg: dict[str, float] = {}


def _get_client() -> httpx.AsyncClient:
    global _client
    if _client is None or _client.is_closed:
        _client = httpx.AsyncClient(timeout=_TIMEOUT, follow_redirects=True)
    return _client


@router.get("/{base}.png", include_in_schema=False)
async def coin_icon(base: str) -> Response:
    if not _BASE_RE.fullmatch(base):
        return Response(status_code=404)
    path = _ICON_DIR / f"{base}.png"
    if path.is_file():
        return FileResponse(path, headers=_OK_HEADERS)
    if _neg.get(base, 0) > time.time():
        return Response(status_code=404, headers=_MISS_HEADERS)
    async with _lock:  # 串行回源: 并发同币种只拉一次; 图标请求量小, 无瓶颈
        if path.is_file():
            return FileResponse(path, headers=_OK_HEADERS)
        try:
            resp = await _get_client().get(_UPSTREAM.format(base))
            if resp.status_code == 200 and resp.headers.get(
                "content-type", ""
            ).startswith("image/"):
                _ICON_DIR.mkdir(parents=True, exist_ok=True)
                tmp = _ICON_DIR / f".{base}.png.tmp"
                tmp.write_bytes(resp.content)
                os.replace(tmp, path)
                return Response(
                    content=resp.content, media_type="image/png", headers=_OK_HEADERS
                )
        except httpx.HTTPError:
            pass
        _neg[base] = time.time() + _NEG_TTL
        return Response(status_code=404, headers=_MISS_HEADERS)
