"""自选股路由 (需登录): 列表 / 添加 / 删除."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from models.watchlist import HkWatchlist
from services import auth_service

router = APIRouter(prefix="/watchlist", tags=["自选股"])

MAX_WATCH = 200  # 防滥用上限


class AddIn(BaseModel):
    inst_id: str = Field(min_length=3, max_length=32)


@router.get("")
async def list_watch(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """我的自选列表: inst_id 数组, 按添加时间升序."""
    result = await db.execute(
        select(HkWatchlist.inst_id)
        .where(HkWatchlist.user_id == user.id)
        .order_by(HkWatchlist.created_at, HkWatchlist.id)
    )
    return {"items": [r[0] for r in result.all()]}


@router.post("", status_code=201)
async def add_watch(
    data: AddIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """添加自选. 幂等: 已存在直接返回当前列表."""
    inst_id = data.inst_id.strip().upper()
    exists = await db.scalar(
        select(HkWatchlist.id).where(
            HkWatchlist.user_id == user.id, HkWatchlist.inst_id == inst_id
        )
    )
    if exists is None:
        cnt_result = await db.execute(
            select(HkWatchlist.id).where(HkWatchlist.user_id == user.id)
        )
        if len(cnt_result.all()) >= MAX_WATCH:
            raise HTTPException(status_code=400, detail="自选数量已达上限")
        db.add(HkWatchlist(user_id=user.id, inst_id=inst_id))
        await db.commit()
    return await list_watch(user, db)


@router.delete("/{inst_id}")
async def remove_watch(
    inst_id: str,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """移除自选. 不存在也视为成功 (幂等)."""
    await db.execute(
        delete(HkWatchlist).where(
            HkWatchlist.user_id == user.id,
            HkWatchlist.inst_id == inst_id.strip().upper(),
        )
    )
    await db.commit()
    return await list_watch(user, db)
