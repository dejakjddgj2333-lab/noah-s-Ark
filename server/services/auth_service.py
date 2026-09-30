"""认证服务: bcrypt 哈希、JWT 签发/解析、当前用户依赖."""
from __future__ import annotations

import logging
from datetime import datetime, timedelta, timezone

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from passlib.context import CryptContext
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

# bcrypt 4.1+ 不再暴露 __about__, passlib 1.7.4 初始化会误报; 做兼容补丁
try:
    import bcrypt

    if not hasattr(bcrypt, "__about__"):
        bcrypt.__about__ = type(
            "about", (), {"__version__": bcrypt.__version__}
        )()
except Exception:
    pass

from config import config
from database import get_db
from models.hk import HkUser

logger = logging.getLogger(__name__)

_pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")
_ALGORITHM = "HS256"

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/login")


def hash_password(password: str) -> str:
    return _pwd_context.hash(password)


def verify_password(plain_password: str, hashed_password: str) -> bool:
    return _pwd_context.verify(plain_password, hashed_password)


def create_access_token(user: HkUser) -> str:
    expire = datetime.now(timezone.utc) + timedelta(hours=config.jwt_expire_hours)
    payload = {"sub": str(user.id), "username": user.username, "exp": expire}
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
    return user
