"""认证路由: 邮箱验证码、注册、登录、当前用户、个人资料 (昵称/头像)."""
from __future__ import annotations

import random
import re
from datetime import timedelta
from pathlib import Path
from uuid import uuid4

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Request,
    UploadFile,
    status,
)
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import get_db
from models.hk import HkEmailCode, HkUser, utc_now
from services import auth_service, email_service, invite_service, rate_limit_service

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
    invite_code: str | None = None  # 可选: 注册时绑定上级

    _check_email = field_validator("email")(_valid_email)


class LoginIn(BaseModel):
    username: str
    password: str


class UserOut(BaseModel):
    id: int
    username: str
    email: str
    nickname: str | None = None
    avatar_url: str | None = None

    model_config = {"from_attributes": True}


class ProfileIn(BaseModel):
    nickname: str | None = Field(default=None, max_length=32)


class ChangePasswordIn(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)


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
async def send_email_code(
    data: SendEmailCodeIn, request: Request, db: AsyncSession = Depends(get_db)
):
    ip = rate_limit_service.client_ip(request)
    rate_limit_service.check(
        f"emailcode:{ip}",
        config.email_code_rate_limit,
        config.email_code_rate_window_sec,
    )
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
async def register(
    data: RegisterIn, request: Request, db: AsyncSession = Depends(get_db)
):
    ip = rate_limit_service.client_ip(request)
    rate_limit_service.check(
        f"register:{ip}",
        config.register_rate_limit,
        config.register_rate_window_sec,
    )
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
        if record is None or record.expires_at < utc_now():
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST, detail="验证码错误或已过期"
            )
        if record.attempts >= config.email_code_max_attempts:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail="验证码错误次数过多, 请重新获取",
            )
        if record.code != data.code:
            record.attempts += 1  # 累计失败次数, 超限作废防枚举
            await db.commit()
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
    try:
        await db.flush()
    except IntegrityError:
        # 并发注册同名同邮箱: 唯一键兜底, 明确 409 (避免 500)
        await db.rollback()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail="用户名或邮箱已被占用"
        )

    # 每名用户注册即拥有专属邀请码; 填写了邀请码则当场绑定上级 (约束校验在 service 内)
    await invite_service.get_or_create_invite(db, user.id)
    if data.invite_code:
        await invite_service.bind_inviter(db, user.id, data.invite_code)

    await db.commit()
    await db.refresh(user)

    token = auth_service.create_access_token(user)
    return TokenOut(token=token, user=UserOut.model_validate(user))


@router.post("/login", response_model=TokenOut)
async def login(
    data: LoginIn, request: Request, db: AsyncSession = Depends(get_db)
):
    result = await db.execute(
        select(HkUser).where(HkUser.username == data.username)
    )
    user = result.scalar_one_or_none()
    if user is None or not auth_service.verify_password(
        data.password, user.password_hash
    ):
        # 仅失败尝试计数, 成功登录不占额度; 超限抛 429 防暴力破解
        ip = rate_limit_service.client_ip(request)
        rate_limit_service.check(
            f"login:{ip}:{data.username.lower()}",
            config.login_rate_limit,
            config.login_rate_window_sec,
        )
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


@router.post("/change-password")
async def change_password(
    data: ChangePasswordIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """改登录密码: 校验旧密码, 通过则更新. 失败计入限流防暴力破解."""
    if not auth_service.verify_password(data.old_password, me.password_hash):
        ip = rate_limit_service.client_ip(request)
        rate_limit_service.check(
            f"changepw:{ip}:{me.username.lower()}",
            config.login_rate_limit,
            config.login_rate_window_sec,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="原密码不正确"
        )
    if data.old_password == data.new_password:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="新密码不能与原密码相同"
        )
    me.password_hash = auth_service.hash_password(data.new_password)
    await db.commit()
    return {"ok": True}


# ---------- 个人资料 (昵称/头像) ----------

AVATAR_DIR = Path(config.upload_dir) / "avatars"
_AVATAR_EXTS = {"jpg", "jpeg", "png", "webp", "gif"}
_AVATAR_MAX = 10 * 1024 * 1024


@router.put("/profile", response_model=UserOut)
async def update_profile(
    data: ProfileIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """改昵称: 传 None/空串 = 清除昵称回退 username."""
    if data.nickname is not None:
        me.nickname = data.nickname.strip() or None
    await db.commit()
    await db.refresh(me)
    return UserOut.model_validate(me)


@router.post("/avatar", status_code=201)
async def upload_avatar(
    request: Request,
    file: UploadFile = File(...),
    me: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """头像上传: multipart 字段名 file, 10MB, 仅图片. 独立目录, 不走聊天 7 天清理."""
    cl = request.headers.get("content-length")
    if cl and cl.isdigit() and int(cl) > _AVATAR_MAX:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="图片超过 10MB",
        )
    ext = ""
    if file.filename and "." in file.filename:
        ext = file.filename.rsplit(".", 1)[-1].lower()
    if ext not in _AVATAR_EXTS:
        raise HTTPException(status_code=400, detail="仅支持 jpg/png/webp/gif")
    name = f"{uuid4().hex}.{ext}"
    AVATAR_DIR.mkdir(parents=True, exist_ok=True)
    dest = AVATAR_DIR / name
    size = 0
    try:
        with open(dest, "wb") as f:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > _AVATAR_MAX:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="图片超过 10MB",
                    )
                f.write(chunk)
    except Exception:
        dest.unlink(missing_ok=True)
        raise
    # 旧头像文件顺手清掉 (仅本服务生成的无扩展名引用)
    old = me.avatar_url or ""
    if old.startswith("/api/auth/avatars/"):
        old_name = old.rsplit("/", 1)[-1]
        if re.fullmatch(r"[A-Za-z0-9]+", old_name):
            for p in AVATAR_DIR.glob(f"{old_name}.*"):
                p.unlink(missing_ok=True)
    # URL 不带扩展名: 宝塔/nginx 按 .png 等后缀拦截静态请求, 会绕过代理 404
    me.avatar_url = f"/api/auth/avatars/{name.split('.')[0]}"
    await db.commit()
    return {"avatar_url": me.avatar_url}


@router.get("/avatars/{name}")
async def get_avatar(name: str):
    """头像读取: URL 无扩展名, 按 glob 找回磁盘文件."""
    safe = name.rsplit("/", 1)[-1]
    if not re.fullmatch(r"[A-Za-z0-9]+", safe):
        raise HTTPException(status_code=400, detail="非法文件名")
    matches = sorted(AVATAR_DIR.glob(f"{safe}.*"))
    if not matches:
        raise HTTPException(status_code=404, detail="头像不存在")
    return FileResponse(matches[0])
