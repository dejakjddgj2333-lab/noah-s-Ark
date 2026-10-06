"""推送 token 注册/注销 + 行情预警 CRUD."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkPushToken, HkUser
from services import auth_service

router = APIRouter(prefix="/push", tags=["推送"])


class PushTokenIn(BaseModel):
    token: str = Field(min_length=8, max_length=128)
    platform: str = "ios"


@router.post("/token", status_code=201)
async def register_token(
    data: PushTokenIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """上报 APNs device_token. 已存在则更新归属/时间 (幂等)."""
    result = await db.execute(
        select(HkPushToken).where(HkPushToken.token == data.token)
    )
    row = result.scalar_one_or_none()
    if row is None:
        db.add(
            HkPushToken(
                user_id=me.id, token=data.token, platform=data.platform
            )
        )
    else:
        row.user_id = me.id  # token 换账号登录, 改绑到新用户
        row.platform = data.platform
    await db.commit()
    return {"ok": True}


@router.delete("/token")
async def unregister_token(
    token: str,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """注销 device_token (通知关闭/登出时). token 走 query 参数."""
    result = await db.execute(
        select(HkPushToken).where(
            HkPushToken.token == token, HkPushToken.user_id == me.id
        )
    )
    row = result.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()
    return {"ok": True}
