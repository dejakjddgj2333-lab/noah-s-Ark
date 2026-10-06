"""APNs 远程推送: JWT(ES256) 签名 + HTTP/2 发送, 仅对 WS 离线用户发.

设计:
- 在线(App WS 长连接活着)走 chat_ws 实时投递 + App 端本地通知, 不经 APNs.
- 离线才发 APNs 远程推送 (穿透到锁屏).
- APNs provider token (JWT) 有效期 1h, 缓存复用, 过期前重建.
"""
from __future__ import annotations

import time
from pathlib import Path

import httpx
import structlog
from jose import jwt as jose_jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from models.hk import HkPushToken
from services.chat_ws import chat_ws

logger = structlog.get_logger("hk.push")

# provider token 缓存 (APNs 要求复用, 频繁重建会被拒)
_cached_jwt: str | None = None
_cached_at: float = 0.0
_JWT_TTL = 50 * 60  # 官方上限 1h, 提前 10min 重建


def _load_key() -> str | None:
    """读 p8 私钥: 文件路径优先, 其次 env 文本."""
    if config.apns_key_path:
        try:
            return Path(config.apns_key_path).read_text().strip()
        except OSError:
            logger.warning("apns_key_path_read_failed", path=config.apns_key_path)
            return None
    if config.apns_key_text:
        text = config.apns_key_text.strip()
        # 优先按 base64 单行解码 (GitHub Secrets 多行私钥存 base64 最稳);
        # 解码失败/不像 PEM 则按字面 \n 还原多行.
        import base64 as _b64
        try:
            decoded = _b64.b64decode(text).decode("utf-8")
            if "PRIVATE KEY" in decoded:
                return decoded.strip()
        except Exception:
            pass
        return text.replace("\\n", "\n").strip()
    return None


def _provider_jwt() -> str | None:
    """构造/复用 APNs provider token (ES256, iss=team_id, kid=key_id)."""
    global _cached_jwt, _cached_at
    now = time.time()
    if _cached_jwt and now - _cached_at < _JWT_TTL:
        return _cached_jwt
    key = _load_key()
    if not key or not config.apns_key_id or not config.apns_team_id:
        return None
    token = jose_jwt.encode(
        {"iss": config.apns_team_id, "iat": int(now)},
        key,
        algorithm="ES256",
        headers={"kid": config.apns_key_id},
    )
    _cached_jwt = token
    _cached_at = now
    return token


def _apns_host() -> str:
    return (
        "https://api.sandbox.push.apple.com"
        if config.apns_use_sandbox
        else "https://api.push.apple.com"
    )


async def _send_one(token: str, title: str, body: str, data: dict | None) -> bool:
    """给单个 device_token 发一条推送. 返回是否成功."""
    jwt_token = _provider_jwt()
    if jwt_token is None:
        return False
    payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
            "badge": 1,
        }
    }
    if data:
        payload.update(data)
    try:
        async with httpx.AsyncClient(http2=True, timeout=10) as client:
            resp = await client.post(
                f"{_apns_host()}/3/device/{token}",
                json=payload,
                headers={
                    "authorization": f"bearer {jwt_token}",
                    "apns-topic": config.apns_bundle_id,
                    "apns-push-type": "alert",
                    "apns-priority": "10",
                },
            )
        if resp.status_code == 200:
            return True
        # 400 BadDeviceToken / 410 Unregistered: token 失效, 由调用方清理
        logger.warning(
            "apns_send_failed", status=resp.status_code, body=resp.text[:200]
        )
        return False
    except Exception as e:  # 网络异常等, 不影响主流程
        logger.warning("apns_send_error", error=str(e))
        return False


async def push_to_user(
    db: AsyncSession,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
) -> None:
    """给用户的所有 APNs 设备发推送 (不判断在线, 调用方决定)."""
    if not config.apns_enabled:
        return
    result = await db.execute(
        select(HkPushToken).where(HkPushToken.user_id == user_id)
    )
    tokens = result.scalars().all()
    for t in tokens:
        ok = await _send_one(t.token, title, body, data)
        if not ok:
            # 简单策略: 发送失败的 token 删除 (多为已卸载/失效)
            await db.delete(t)
    if tokens:
        await db.commit()


async def push_if_offline(
    db: AsyncSession,
    user_id: int,
    title: str,
    body: str,
    data: dict | None = None,
) -> None:
    """仅当用户 WS 离线时发 APNs 推送 (在线走 WS + 本地通知)."""
    if not config.apns_enabled:
        return
    online = await chat_ws.online_user_ids()
    if user_id in online:
        return
    await push_to_user(db, user_id, title, body, data)
