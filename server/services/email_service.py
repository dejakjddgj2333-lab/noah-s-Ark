"""邮件服务: SMTP 发送. aiosmtplib 未入依赖, 用 smtplib 包 asyncio.to_thread."""
from __future__ import annotations

import asyncio
import logging
import smtplib
from email.header import Header
from email.mime.text import MIMEText

from config import config

logger = logging.getLogger(__name__)


def _send_sync(to: str, subject: str, text: str) -> bool:
    msg = MIMEText(text, "plain", "utf-8")
    msg["From"] = config.smtp_from
    msg["To"] = to
    msg["Subject"] = Header(subject, "utf-8")

    if config.smtp_use_ssl:
        server = smtplib.SMTP_SSL(config.smtp_host, config.smtp_port, timeout=15)
    else:
        server = smtplib.SMTP(config.smtp_host, config.smtp_port, timeout=15)
        server.starttls()
    try:
        if config.smtp_user:
            server.login(config.smtp_user, config.smtp_password)
        server.sendmail(config.smtp_from, [to], msg.as_string())
    finally:
        server.quit()
    return True


async def send_email(to: str, subject: str, text: str) -> bool:
    """发送邮件. 未配置 smtp_host 时视为开发模式: 记日志并返回 False."""
    if not config.smtp_host:
        logger.warning(
            "smtp_not_configured_dev_mode",
            extra={"to": to, "subject": subject, "text": text},
        )
        return False
    try:
        return await asyncio.to_thread(_send_sync, to, subject, text)
    except Exception as e:
        logger.error("smtp_send_failed", extra={"to": to, "error": str(e)})
        return False
