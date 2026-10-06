"""认证服务: bcrypt 哈希、JWT 签发/解析、当前用户依赖."""
from __future__ import annotations

import base64
import hashlib
import hmac
import logging
import secrets
import struct
import time
from datetime import datetime, timedelta, timezone

import bcrypt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import get_db
from models.hk import HkLoginDevice, HkUser

logger = logging.getLogger(__name__)

_ALGORITHM = "HS256"

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def hash_password(password: str) -> str:
    # 直接用 bcrypt: passlib 1.7.4 与 bcrypt 4.1+ 版本解析有兼容问题
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    try:
        return bcrypt.checkpw(
            plain_password.encode("utf-8"), hashed_password.encode("utf-8")
        )
    except ValueError:
        return False


# ---------- TOTP (谷歌验证, 纯标准库) ----------


def generate_totp_secret() -> str:
    return base64.b32encode(secrets.token_bytes(20)).decode("ascii").rstrip("=")


def _totp_at(secret: str, counter: int) -> str:
    padding = "=" * (-len(secret) % 8)
    key = base64.b32decode(secret + padding)
    msg = struct.pack(">Q", counter)
    digest = hmac.new(key, msg, hashlib.sha1).digest()
    off = digest[-1] & 0x0F
    code = (struct.unpack(">I", digest[off : off + 4])[0] & 0x7FFFFFFF) % 1_000_000
    return str(code).zfill(6)


def verify_totp(secret: str, code: str, window: int = 1) -> bool:
    code = (code or "").strip()
    if not code.isdigit():
        return False
    counter = int(time.time() // 30)
    return any(
        hmac.compare_digest(_totp_at(secret, counter + d), code)
        for d in range(-window, window + 1)
    )


def create_access_token(user: HkUser, jti: str | None = None) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=config.jwt_expire_hours)
    payload = {"sub": str(user.id), "username": user.username, "exp": expire}
    if jti:
        payload["jti"] = jti  # 登录设备会话标识, 设备下线即 token 失效
    return jwt.encode(payload, config.secret_key, algorithm=_ALGORITHM)


def decode_token(token: str) -> dict | None:
    try:
        return jwt.decode(token, config.secret_key, algorithms=[_ALGORITHM])
    except JWTError as e:
        logger.warning("jwt_decode_failed", extra={"error": str(e)})
        return None


async def get_current_user(
    token: str = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)
) -> HkUser:
    """OAuth2 bearer → HkUser; 无效/过期/不存在一律 401."""
    credentials_exc = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="未登录或登录已过期",
        headers={"WWW-Authenticate": "Bearer"},
    )
    payload = decode_token(token)
    if not payload:
        raise credentials_exc
    sub = payload.get("sub")
    if not sub:
        raise credentials_exc
    result = await db.execute(select(HkUser).where(HkUser.id == int(sub)))
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exc
    if user.status != "active":
        # 封禁/冻结后旧 token 立即失效, 不再放行任何业务接口
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="账号已被禁用"
        )
    # 设备会话校验: token 带 jti 时, 对应设备记录必须存在(被下线则拒绝)
    jti = payload.get("jti")
    if jti:
        dev = await db.execute(
            select(HkLoginDevice).where(HkLoginDevice.jti == jti)
        )
        if dev.scalar_one_or_none() is None:
            raise credentials_exc
    return user
