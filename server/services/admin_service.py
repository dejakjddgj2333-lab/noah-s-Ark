"""后台管理员鉴权 (RBAC): 用户绑角色, 角色含权限码; ['*']=超管.

兼容期: config.admin_usernames 白名单用户视为超管 (启动时自动绑 superadmin 角色).
"""
from __future__ import annotations

import json

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import get_db
from models.account import HkAdminActionLog
from models.hk import HkRole, HkUser
from services.auth_service import get_current_user
from services.permissions import BUILTIN_ROLES


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
