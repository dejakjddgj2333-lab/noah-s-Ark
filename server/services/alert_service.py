"""轻量告警: 扫链异常邮件通知. 同类告警 1 小时内只发一次, 防轰炸."""
from __future__ import annotations

import asyncio
import logging
import time

from config import config
from services import email_service

logger = logging.getLogger(__name__)

DEDUP_WINDOW_SEC = 3600  # 同一 category 1 小时内只发一次

_last_sent: dict[str, float] = {}
_lock = asyncio.Lock()


async def alert(category: str, subject: str, body: str) -> None:
    """发告警邮件 (按 category 去重). 未配 ALERT_EMAIL 时只记日志."""
    logger.warning("ALERT [%s] %s: %s", category, subject, body)
    if not config.alert_email:
        return
    async with _lock:
        now = time.monotonic()
        if now - _last_sent.get(category, 0) < DEDUP_WINDOW_SEC:
            return
        _last_sent[category] = now
    ok = await email_service.send_email(
        config.alert_email,
        f"[Noah's Ark 告警] {subject}",
        body,
    )
    if not ok:
        logger.error("alert email send failed: %s", subject)
