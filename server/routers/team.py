"""团队等级路由 (用户侧, 需登录)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from services import auth_service, team_service

router = APIRouter(prefix="/team", tags=["团队等级"])


@router.get("/me")
async def my_team(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """我的团队: 三代有效人数 / 有效持仓 / 团队等级 / 各级返佣比例 / 距下一级差额."""
    info = await team_service.current_team(db, user.id)
    info["total_holding"] = Decimal(info["total_holding"])
    if info["next_holding_gap"] is not None:
        info["next_holding_gap"] = Decimal(info["next_holding_gap"])
    return info
