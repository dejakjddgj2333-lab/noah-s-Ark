"""公开配置路由 (无需登录): app 启动拉功能开关."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from services import config_service

router = APIRouter(prefix="/config", tags=["配置"])


@router.get("")
async def get_config(db: AsyncSession = Depends(get_db)) -> dict:
    """公开功能开关 (白名单 key, bool). app 启动/进资产页拉取."""
    return await config_service.get_public(db)
