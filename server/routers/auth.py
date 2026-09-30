"""认证路由: 邮箱验证码、注册、登录、当前用户."""
from __future__ import annotations

import random
import re
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import get_db
from models.hk import HkEmailCode, HkUser, utc_now
from services import auth_service, email_service

router = APIRouter(prefix="/auth", tags=["认证"])

_USERNAME_RE = re.compile(r"^[a-zA-Z0-9_]{3,32}$")
_EMAIL_RE = re.compile(r"^[^@\s]+@[^@\s]+\.[^@\s]+$")


def _valid_email(v: str) -> str:
    v = v.strip().lower()
    if not _EMAIL_RE.match(v):
        raise ValueError("邮箱格式不正确")
    return v


# ---------- Schemas ----------


class SendEmailCodeIn(BaseModel):
    email: str
    purpose: str = "register"

    _check_email = field_validator("email")(_valid_email)


class RegisterIn(BaseModel):
    username: str
    password: str = Field(min_length=8)
    email: str
    code: str

    _check_email = field_validator("email")(_valid_email)


class LoginIn(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    email: str

    model_config = {"from_attributes": True}


class TokenOut(BaseModel):
    token: str
    user: UserOut


# ---------- Helpers ----------


async def _latest_code(
    db: AsyncSession, email: str, purpose: str
) -> HkEmailCode | None:
    result = await db.execute(
        select(HkEmailCode)
        .where(
            HkEmailCode.email == email,
            HkEmailCode.purpose == purpose,
            HkEmailCode.used.is_(False),
        )
        .order_by(HkEmailCode.created_at.desc(), HkEmailCode.id.desc())
        .limit(1)
    )
    return result.scalar_one_or_none()


# ---------- Endpoints ----------


@router.post("/send-email-code")
async def send_email_code(data: SendEmailCodeIn, db: AsyncSession = Depends(get_db)):
    if data.purpose == "register":
        existing = await db.execute(
            select(HkUser).where(HkUser.email == data.email)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT, detail="该邮箱已注册"
            )

    latest = await _latest_code(db, data.email, data.purpose)
    if latest is not None:
        elapsed = (utc_now() - latest.created_at).total_seconds()
        if elapsed < config.email_code_interval_sec:
            raise HTTPException(
                status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                detail="发送过于频繁, 请稍后再试",
            )

    code = f"{random.randint(0, 999999):06d}"
    record = HkEmailCode(
        email=data.email,
        code=code,
        purpose=data.purpose,
        used=False,
        expires_at=utc_now() + timedelta(seconds=config.email_code_ttl_sec),
    )
    db.add(record)
    await db.commit()

    ttl_minutes = config.email_code_ttl_sec // 60
    sent = await email_service.send_email(
        to=data.email,
        subject="Noah's Ark 验证码",
        text=(
            f"您好, 您的 Noah's Ark 验证码为: {code}\n\n"
            f"验证码 {ttl_minutes} 分钟内有效, 请勿泄露给他人。"
        ),
    )
    resp: dict = {"ok": True}
    # 回显验证码: 测试关闭邮箱验证, 或开发模式 SMTP 未配置
    if not config.email_verify_enabled or (not sent and not config.smtp_host):
        resp["debug_code"] = code
    return resp


@router.post("/register", response_model=TokenOut)
async def register(data: RegisterIn, db: AsyncSession = Depends(get_db)):
    if not _USERNAME_RE.match(data.username):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="用户名需为 3~32 位字母、数字或下划线",
        )

    existing = await db.execute(
        select(HkUser).where(
            (HkUser.username == data.username) | (HkUser.email == data.email)
        )
    )
    if existing.scalar_one_or_none():
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="用户名或邮箱已被占用"
        )

    if config.email_verify_enabled:
        record = await _latest_code(db, data.email, "register")
        if (
            record is None
            or record.code != data.code
            or record.expires_at < utc_now()
        ):
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="验证码错误或已过期"
            )
        record.used = True

    user = HkUser(
        username=data.username,
        password_hash=auth_service.hash_password(data.password),
        email=data.email,
        email_verified=True,
        status="active",
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)

    token = auth_service.create_access_token(user)
    return TokenOut(token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
async def login(data: LoginIn, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(HkUser).where(HkUser.username == data.username)
    )
    user = result.scalar_one_or_none()
    if user is None or not auth_service.verify_password(
        data.password, user.password_hash
    ):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED, detail="用户名或密码错误"
        )
    if user.status != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="账号已被禁用"
        )
    token = auth_service.create_access_token(user)
    return TokenOut(token=token, user=UserOut.model_validate(user))


@router.get("/me", response_model=UserOut)
async def me(user: HkUser = Depends(auth_service.get_current_user)):
    return UserOut.model_validate(user)
