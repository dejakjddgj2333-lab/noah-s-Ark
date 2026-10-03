"""个人 VIP 路由 (用户侧, 需登录)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from services import auth_service, vip_service

router = APIRouter(prefix="/vip", tags=["个人VIP"])


@router.get("/me")
async def my_vip(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """我的 VIP: 等级 / 有效持仓 / 加成比例 / 距下一级金额 (需求文档 8.1)."""
    info = await vip_service.current_vip(db, user.id)
    info["effective_holding"] = Decimal(info["effective_holding"])
    info["bonus_rate"] = Decimal(info["bonus_rate"])
    if info["gap_to_next"] is not None:
        info["gap_to_next"] = Decimal(info["gap_to_next"])
    return info
