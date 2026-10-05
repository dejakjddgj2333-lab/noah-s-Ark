"""请求限流 (内存滑动窗口, 单进程部署适用).

用于登录防暴力破解、注册防批量、发码防邮件轰炸.
多实例部署时需替换为 Redis 等共享存储 (见第九节待拍板项).
"""
from __future__ import annotations

import threading
import time

from fastapi import HTTPException, Request, status

_lock = threading.Lock()
# key -> (窗口开始时间, 已计次)
_buckets: dict[str, tuple[float, int]] = {}


def client_ip(request: Request) -> str:
    """客户端 IP. 仅当显式开启 TRUST_X_FORWARDED_FOR 时才采信 XFF 首跳
    (直连部署时客户端可伪造该头绕过限流); 否则用传输层对端地址."""
    from config import config

    if config.trust_x_forwarded_for:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def check(key: str, limit: int, window_sec: int) -> None:
    """滑动窗口限流: 窗口内超过 limit 次抛 429.

    key 建议含端点+IP (+用户名/邮箱), 例如 "login:1.2.3.4:alice".
    """
    now = time.monotonic()
    with _lock:
        start, count = _buckets.get(key, (now, 0))
        if now - start >= window_sec:
            start, count = now, 0
        count += 1
        _buckets[key] = (start, count)
        if count > limit:
            retry = int(window_sec - (now - start)) + 1
            raise HTTPException(
                status.HTTP_429_TOO_MANY_REQUESTS,
                f"操作过于频繁, 请 {retry} 秒后再试",
            )


def reset() -> None:
    """清空计数 (测试用)."""
    with _lock:
        _buckets.clear()
