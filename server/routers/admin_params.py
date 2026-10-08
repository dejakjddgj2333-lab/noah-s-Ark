"""运营参数后台路由 (管理员): 参数配置页查看/修改, 保存即生效无需重启."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from services import admin_service, param_service

router = APIRouter(prefix="/admin/params", tags=["后台-参数配置"])


class ConfigUpdateIn(BaseModel):
    updates: dict[str, str]


@router.get("")
async def list_config(
    user: HkUser = Depends(admin_service.require_perm("page:config")),
):
    """全部运营参数: 当前生效值/默认值/范围/是否被后台改过 (按注册表分组顺序)."""
    return {"items": param_service.view()}


@router.put("")
async def update_config(
    data: ConfigUpdateIn,
    user: HkUser = Depends(admin_service.require_perm("btn:config:edit")),
    db: AsyncSession = Depends(get_db),
):
    """批量保存参数: 全部合法才落库, 任一非法整体拒绝; 保存后即时生效."""
    if not data.updates:
        return {"changed": []}
    changed = await param_service.update(db, data.updates, user.username)
    await db.commit()
    return {"changed": changed}
