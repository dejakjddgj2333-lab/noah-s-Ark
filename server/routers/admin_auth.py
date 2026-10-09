"""后台管理员认证: 独立登录 (密码+谷歌验证) / TOTP 绑定 / 修改密码.

管理员与 App 注册用户完全隔离 (hk_admin_users 表); 除超管外必须绑定谷歌验证.
"""
from __future__ import annotations

import urllib.parse

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkAdminUser
from services import admin_service, auth_service

router = APIRouter(prefix="/admin", tags=["后台-管理员认证"])


class AdminLoginIn(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    password: str = Field(min_length=1, max_length=128)
    totp_code: str = Field(default="", max_length=8)


@router.post("/login")
async def admin_login(
    data: AdminLoginIn,
    db: AsyncSession = Depends(get_db),
):
    """管理员登录. 非超管: 已绑验证器则校验 totp_code, 未绑则下发短期 token 去绑定."""
    admin = (
        await db.execute(
            select(HkAdminUser).where(HkAdminUser.username == data.username.lower())
        )
    ).scalar_one_or_none()
    # 统一报错文案, 防用户名探测
    bad = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED, detail="用户名或密码错误"
    )
    if admin is None or not auth_service.verify_password(
        data.password, admin.password_hash
    ):
        raise bad
    if admin.status != "active":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="账号已被禁用"
        )
    if admin.username != "admin":
        # 除超管账号 admin 外, 一律强制谷歌验证; 未绑定直接拒登,
        # 须由其他管理员在管理页完成绑定后才能登录.
        if not admin.totp_bound:
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="该账号尚未绑定谷歌验证器, 请联系其他管理员在管理页完成绑定",
            )
        if not auth_service.verify_totp(admin.totp_secret or "", data.totp_code):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="谷歌验证码错误或缺失",
            )
    return {"token": auth_service.create_admin_token(admin), "need_totp": False}


class TotpConfirmIn(BaseModel):
    code: str = Field(min_length=6, max_length=8)


@router.post("/totp/setup")
async def totp_setup(
    db: AsyncSession = Depends(get_db),
    admin: HkAdminUser = Depends(auth_service.get_current_admin_raw),
):
    """生成/重取绑定密钥: 返回 otpauth URI 供生成二维码."""
    if not admin.totp_secret:
        admin.totp_secret = auth_service.generate_totp_secret()
        await db.commit()
    label = urllib.parse.quote(f"NoahAdmin:{admin.username}")
    uri = (
        f"otpauth://totp/{label}?secret={admin.totp_secret}"
        f"&issuer=NoahAdmin&algorithm=SHA1&digits=6&period=30"
    )
    return {"secret": admin.totp_secret, "uri": uri}


@router.post("/totp/confirm")
async def totp_confirm(
    data: TotpConfirmIn,
    db: AsyncSession = Depends(get_db),
    admin: HkAdminUser = Depends(auth_service.get_current_admin_raw),
):
    """验证一次动态码, 确认绑定."""
    if not admin.totp_secret:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="请先生成绑定密钥"
        )
    if not auth_service.verify_totp(admin.totp_secret, data.code):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="验证码错误, 请重试"
        )
    admin.totp_bound = True
    await db.commit()
    await admin_service.audit_admin(
        db, admin, "admin_totp_bind", "admin_user", admin.id
    )
    await db.commit()
    return {"ok": True}


class PasswordChangeIn(BaseModel):
    old_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)
    totp_code: str = Field(default="", max_length=8)


@router.post("/password")
async def change_password(
    data: PasswordChangeIn,
    db: AsyncSession = Depends(get_db),
    admin: HkAdminUser = Depends(auth_service.get_current_admin),
):
    """管理员改自己密码: 已绑验证器的须带动态码."""
    if not auth_service.verify_password(data.old_password, admin.password_hash):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="原密码错误"
        )
    if admin.totp_bound and not auth_service.verify_totp(
        admin.totp_secret or "", data.totp_code
    ):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="谷歌验证码错误"
        )
    admin.password_hash = auth_service.hash_password(data.new_password)
    await db.commit()
    await admin_service.audit_admin(
        db, admin, "admin_password_change", "admin_user", admin.id
    )
    await db.commit()
    return {"ok": True}
