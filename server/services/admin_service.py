"""后台管理员鉴权 (RBAC): 用户绑角色, 角色含权限码; ['*']=超管.

兼容期: config.admin_usernames 白名单用户视为超管 (启动时自动绑 superadmin 角色).
"""
from __future__ import annotations

import json

from fastapi import Depends, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import get_db
from models.account import HkAdminActionLog
from models.hk import HkAdminUser, HkRole, HkUser
from services import auth_service
from services.auth_service import get_current_user
from services.permissions import BUILTIN_ROLES


async def get_admin_perms(db: AsyncSession, admin: HkAdminUser) -> list[str]:
    """管理员权限码集: 超管角色直通 ['*']."""
    role = (
        await db.execute(select(HkRole).where(HkRole.id == admin.role_id))
    ).scalar_one_or_none()
    if role is None:
        return []
    if role.code == "superadmin":
        return ["*"]
    try:
        return json.loads(role.perms)
    except (ValueError, TypeError):
        return []


def require_admin_perm(code: str | None = None):
    """后台接口依赖: 管理员会话 + 权限码 (code=None 仅校验登录)."""

    async def _check(
        admin: HkAdminUser = Depends(auth_service.get_current_admin),
        db: AsyncSession = Depends(get_db),
    ) -> HkAdminUser:
        if code is not None:
            perms = await get_admin_perms(db, admin)
            if not has_perm(perms, code):
                raise HTTPException(
                    status_code=status.HTTP_403_FORBIDDEN, detail="无此操作权限"
                )
        return admin

    return _check


async def audit_admin(
    db: AsyncSession,
    admin: HkAdminUser,
    action: str,
    target_type: str,
    target_id: int,
    detail: str | None = None,
) -> None:
    """管理员操作留痕: admin_id 存 'a{id}' 字符串前缀与用户 id 区分."""
    db.add(
        HkAdminActionLog(
            admin_id=admin.id,
            admin_username=f"admin:{admin.username}",
            action=action,
            target_type=target_type,
            target_id=target_id,
            detail=detail[:500] if detail else None,
        )
    )
    await db.flush()


async def seed_admin_users(db: AsyncSession) -> None:
    """首个超级管理员: 表为空时创建, 用户名取 ADMIN_USERNAMES 首个 (默认 admin).
    初始密码: 环境变量 ADMIN_INIT_PASSWORD > 同名注册用户密码哈希 (无缝迁移) > 随机生成."""
    import logging
    import os

    cnt = await db.scalar(select(func.count()).select_from(HkAdminUser))
    if cnt:
        return
    super_role = (
        await db.execute(select(HkRole).where(HkRole.code == "superadmin"))
    ).scalar_one_or_none()
    if super_role is None:
        return
    username = config.admin_usernames[0] if config.admin_usernames else "admin"

    init_password = None
    env_pwd = os.getenv("ADMIN_INIT_PASSWORD")
    password_hash = None
    if env_pwd:
        init_password = env_pwd
        password_hash = auth_service.hash_password(env_pwd)
    else:
        # 迁移: 复用同名 App 注册用户的密码哈希, 无需重置密码
        old = (
            await db.execute(select(HkUser).where(HkUser.username == username))
        ).scalar_one_or_none()
        if old is not None:
            password_hash = old.password_hash
            logging.getLogger(__name__).warning(
                "[管理员] 已复用注册用户 %s 的密码哈希作为超管初始密码", username
            )
    if password_hash is None:
        import secrets as _secrets
        import string

        alphabet = string.ascii_letters + string.digits
        init_password = "".join(_secrets.choice(alphabet) for _ in range(16))
        password_hash = auth_service.hash_password(init_password)

    db.add(
        HkAdminUser(
            username=username,
            password_hash=password_hash,
            role_id=super_role.id,
            status="active",
        )
    )
    await db.commit()
    logging.getLogger(__name__).warning(
        "[管理员] 首个超级管理员已创建: username=%s (初始密码%s)",
        username,
        "见日志上一行或环境变量" if env_pwd else "与旧后台一致",
    )


async def get_perms(db: AsyncSession, user: HkUser) -> list[str]:
    """用户后台权限码集. 白名单用户直通 ['*']."""
    if user.status != "active":
        return []  # 封禁/冻结用户即使命中白名单也不得进入后台
    if user.username in config.admin_usernames:
        return ["*"]
    if user.role_id is None:
        return []
    role = (
        await db.execute(select(HkRole).where(HkRole.id == user.role_id))
    ).scalar_one_or_none()
    if role is None:
        return []
    try:
        return json.loads(role.perms)
    except (ValueError, TypeError):
        return []


def has_perm(perms: list[str], code: str) -> bool:
    return "*" in perms or code in perms


async def require_admin(
    user: HkUser = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> HkUser:
    """任一后台页面权限即可进 (菜单交给前端按码过滤)."""
    perms = await get_perms(db, user)
    if not perms:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="无后台管理权限"
        )
    return user


def require_perm(code: str):
    """按钮/接口级权限依赖工厂."""

    async def _check(
        user: HkUser = Depends(get_current_user),
        db: AsyncSession = Depends(get_db),
    ) -> HkUser:
        perms = await get_perms(db, user)
        if not has_perm(perms, code):
            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN, detail="无此操作权限"
            )
        return user

    return _check


async def seed_roles(db: AsyncSession) -> None:
    """预置角色幂等 upsert + ADMIN_USERNAMES 用户自动绑超管 (启动时调用)."""
    for code, name, perms in BUILTIN_ROLES:
        role = (
            await db.execute(select(HkRole).where(HkRole.code == code))
        ).scalar_one_or_none()
        if role is None:
            db.add(HkRole(code=code, name=name, perms=json.dumps(perms),
                          builtin=True))
    await db.flush()

    super_role = (
        await db.execute(select(HkRole).where(HkRole.code == "superadmin"))
    ).scalar_one_or_none()
    if super_role is None:
        return
    for username in config.admin_usernames:
        u = (
            await db.execute(
                select(HkUser).where(HkUser.username == username)
            )
        ).scalar_one_or_none()
        if u is not None and u.role_id is None:
            u.role_id = super_role.id
    await db.commit()


async def audit(
    db: AsyncSession,
    admin: HkUser,
    action: str,
    target_type: str,
    target_id: int,
    detail: str | None = None,
) -> None:
    """后台关键操作留痕 (只增不改): 谁/何时/对谁/做了什么."""
    db.add(
        HkAdminActionLog(
            admin_id=admin.id,
            admin_username=admin.username,
            action=action,
            target_type=target_type,
            target_id=target_id,
            detail=detail[:500] if detail else None,
        )
    )
    await db.flush()
