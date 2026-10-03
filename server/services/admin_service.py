"""后台管理员鉴权: 复用用户登录态, 用户名须在 config.admin_usernames 中."""
from __future__ import annotations

from fastapi import Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from models.account import HkAdminActionLog
from models.hk import HkUser
from services.auth_service import get_current_user


async def require_admin(user: HkUser = Depends(get_current_user)) -> HkUser:
    if user.username not in config.admin_usernames:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="无后台管理权限"
        )
    return user


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
