"""邀请绑定路由: 我的邀请信息 + 补填绑定 (需登录)."""
from __future__ import annotations

from fastapi import APIRouter, Depends
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from models.invite import HkInvite
from services import auth_service, invite_service

router = APIRouter(prefix="/invite", tags=["邀请"])


class InviteMeOut(BaseModel):
    invite_code: str
    inviter_id: int | None
    inviter_username: str | None
    can_bind: bool  # 未绑定且满足补绑资格
    bind_block_reason: str | None  # 不可补绑的原因说明


class BindIn(BaseModel):
    invite_code: str


async def _build_me_out(db: AsyncSession, user_id: int) -> InviteMeOut:
    mine = await invite_service.get_or_create_invite(db, user_id)
    inviter_id = mine.inviter_id
    inviter_username = None
    if inviter_id is not None:
        result = await db.execute(
            select(HkUser.username).where(HkUser.id == inviter_id)
        )
        inviter_username = result.scalar_one_or_none()
    reason = await invite_service.bind_block_reason(db, user_id)
    return InviteMeOut(
        invite_code=mine.invite_code,
        inviter_id=inviter_id,
        inviter_username=inviter_username,
        can_bind=inviter_id is None and reason is None,
        bind_block_reason=None if inviter_id is not None else reason,
    )


@router.get("/me", response_model=InviteMeOut)
async def invite_me(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    return await _build_me_out(db, user.id)


@router.post("/bind", response_model=InviteMeOut)
async def bind(
    data: BindIn,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    await invite_service.bind_inviter(db, user.id, data.invite_code)
    await db.commit()
    return await _build_me_out(db, user.id)
