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
from models.hk import HkEmailCode, HkLoginDevice, HkUser, utc_now
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
    device_name: str | None = None  # 登录设备名 (前端上报)
    platform: str | None = None  # ios / android / web


class UserOut(BaseModel):
    id: int
    username: str
    email: str
    nickname: str | None = None
    avatar_url: str | None = None
    has_fund_password: bool = False
    has_2fa: bool = False
    anti_phishing_code: str | None = None

    model_config = {"from_attributes": True}

    @classmethod
    def from_user(cls, user: HkUser) -> "UserOut":
        """从 ORM 构造: has_fund_password/has_2fa 由列是否为 NULL 推出."""
        return cls(
            id=user.id,
            username=user.username,
            email=user.email,
            nickname=user.nickname,
            avatar_url=user.avatar_url,
            has_fund_password=user.fund_password_hash is not None,
            has_2fa=user.totp_secret is not None,
            anti_phishing_code=user.anti_phishing_code,
        )


class ProfileIn(BaseModel):
    nickname: str | None = Field(default=None, max_length=32)


class ChangePasswordIn(BaseModel):
    old_password: str
    new_password: str = Field(min_length=8)


def _fund_password_6(v: str) -> str:
    if not (len(v) == 6 and v.isdigit()):
        raise ValueError("资金密码须为6位数字")
    return v


class FundPasswordSetIn(BaseModel):
    fund_password: str
    login_password: str

    _check_fund = field_validator("fund_password")(_fund_password_6)


class FundPasswordChangeIn(BaseModel):
    old_fund_password: str
    new_fund_password: str

    _check_new = field_validator("new_fund_password")(_fund_password_6)


class TwoFACodeIn(BaseModel):
    code: str


class TwoFASetupOut(BaseModel):
    secret: str
    otpauth_url: str


class AntiPhishingIn(BaseModel):
    code: str = Field(default="", max_length=32)


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
    return TokenOut(token=token, user=UserOut.from_user(user))


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
    # 设备会话: 生成 jti, 记录登录设备, 签发带 jti 的 token (设备下线即失效)
    jti = uuid4().hex
    ip = rate_limit_service.client_ip(request)
    db.add(
        HkLoginDevice(
            user_id=user.id,
            jti=jti,
            device_name=(data.device_name or "").strip()[:128],
            platform=(data.platform or "").strip()[:32],
            ip=ip,
        )
    )
    await db.commit()
    token = auth_service.create_access_token(user, jti=jti)
    return TokenOut(token=token, user=UserOut.from_user(user))


# ---------- 登录设备管理 ----------


class DeviceOut(BaseModel):
    id: int
    device_name: str
    platform: str
    ip: str
    created_at: str
    last_seen_at: str
    current: bool


def _device_out(d: HkLoginDevice, current_jti: str | None) -> DeviceOut:
    def _iso(v):
        return v.isoformat() if v is not None else ""

    return DeviceOut(
        id=d.id,
        device_name=d.device_name,
        platform=d.platform,
        ip=d.ip,
        created_at=_iso(d.created_at),
        last_seen_at=_iso(d.last_seen_at),
        current=(current_jti is not None and d.jti == current_jti),
    )


@router.get("/devices", response_model=list[DeviceOut])
async def list_devices(
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """我的登录设备列表, 当前设备标 current=True."""
    # 从 Authorization 头解出当前 jti
    current_jti = None
    auth = request.headers.get("authorization", "")
    if auth.lower().startswith("bearer "):
        payload = auth_service.decode_token(auth[7:].strip())
        if payload:
            current_jti = payload.get("jti")
    result = await db.execute(
        select(HkLoginDevice)
        .where(HkLoginDevice.user_id == me.id)
        .order_by(HkLoginDevice.last_seen_at.desc())
    )
    return [_device_out(d, current_jti) for d in result.scalars().all()]


@router.delete("/devices/{device_id}")
async def remove_device(
    device_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """下线指定设备 (删除会话记录 → 该设备 token 立即失效)."""
    result = await db.execute(
        select(HkLoginDevice).where(
            HkLoginDevice.id == device_id, HkLoginDevice.user_id == me.id
        )
    )
    dev = result.scalar_one_or_none()
    if dev is None:
        raise HTTPException(status_code=404, detail="设备不存在")
    await db.delete(dev)
    await db.commit()
    return {"ok": True}


@router.get("/me", response_model=UserOut)
async def me(user: HkUser = Depends(auth_service.get_current_user)):
    return UserOut.from_user(user)


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


# ---------- 资金密码 ----------


@router.post("/fund-password/set")
async def set_fund_password(
    data: FundPasswordSetIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """首次设置资金密码: 需校验登录密码. 已设置则走 change."""
    if me.fund_password_hash is not None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="资金密码已设置"
        )
    if not auth_service.verify_password(data.login_password, me.password_hash):
        ip = rate_limit_service.client_ip(request)
        rate_limit_service.check(
            f"fundpw:{ip}:{me.username.lower()}",
            config.login_rate_limit,
            config.login_rate_window_sec,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="登录密码错误"
        )
    me.fund_password_hash = auth_service.hash_password(data.fund_password)
    await db.commit()
    return {"ok": True}


@router.post("/fund-password/change")
async def change_fund_password(
    data: FundPasswordChangeIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """改资金密码: 校验原资金密码."""
    if me.fund_password_hash is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="请先设置资金密码"
        )
    if not auth_service.verify_password(
        data.old_fund_password, me.fund_password_hash
    ):
        ip = rate_limit_service.client_ip(request)
        rate_limit_service.check(
            f"fundpw:{ip}:{me.username.lower()}",
            config.login_rate_limit,
            config.login_rate_window_sec,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="原资金密码错误"
        )
    me.fund_password_hash = auth_service.hash_password(data.new_fund_password)
    await db.commit()
    return {"ok": True}


# ---------- 谷歌验证 2FA (TOTP) ----------


@router.post("/2fa/setup", response_model=TwoFASetupOut)
async def twofa_setup(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """生成 TOTP secret 暂存并返回 otpauth_url; enable 校验通过后才生效."""
    secret = auth_service.generate_totp_secret()
    me.totp_secret = secret
    await db.commit()
    otpauth_url = (
        f"otpauth://totp/Mingce:{me.username}?secret={secret}&issuer=Mingce"
    )
    return TwoFASetupOut(secret=secret, otpauth_url=otpauth_url)


def _check_totp_or_400(me: HkUser, request: Request, code: str) -> None:
    """校验 TOTP; 失败计入限流并抛 400."""
    if not me.totp_secret or not auth_service.verify_totp(me.totp_secret, code):
        ip = rate_limit_service.client_ip(request)
        rate_limit_service.check(
            f"2fa:{ip}:{me.username.lower()}",
            config.login_rate_limit,
            config.login_rate_window_sec,
        )
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="验证码错误"
        )


@router.post("/2fa/enable")
async def twofa_enable(
    data: TwoFACodeIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """enable: 验证用户扫对了 secret (has_2fa 由 totp_secret 非 NULL 决定)."""
    _check_totp_or_400(me, request, data.code)
    await db.commit()
    return {"ok": True}


@router.post("/2fa/disable")
async def twofa_disable(
    data: TwoFACodeIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """disable: 验证通过则清除 secret 关闭 2FA."""
    _check_totp_or_400(me, request, data.code)
    me.totp_secret = None
    await db.commit()
    return {"ok": True}


# ---------- 防钓鱼码 ----------


@router.post("/anti-phishing")
async def set_anti_phishing(
    data: AntiPhishingIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """设置防钓鱼码; 空串/纯空格 = 清除."""
    code = data.code.strip()
    me.anti_phishing_code = code or None
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
    return UserOut.from_user(me)


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
