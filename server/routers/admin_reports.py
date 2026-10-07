"""后台举报管理路由: 举报列表/处理 (删消息/封号/驳回)."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkChatMessage, HkReport, HkUser, utc_now
from services import admin_service

router = APIRouter(prefix="/admin/reports", tags=["后台-举报"])


def _out(r: HkReport, reporter: str, target: str, msg: str | None) -> dict:
    return {
        "id": r.id,
        "reporter_id": r.reporter_id,
        "reporter": reporter,
        "target_user_id": r.target_user_id,
        "target": target,
        "message_id": r.message_id,
        "message_content": msg,
        "conversation_id": r.conversation_id,
        "reason": r.reason,
        "detail": r.detail,
        "status": r.status,
        "created_at": r.created_at.isoformat() if r.created_at else None,
        "handled_at": r.handled_at.isoformat() if r.handled_at else None,
    }


@router.get("")
async def list_reports(
    status_filter: str | None = Query(default=None, alias="status"),
    limit: int = Query(default=100, le=500),
    offset: int = Query(default=0, ge=0),
    user: HkUser = Depends(admin_service.require_perm("page:report")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    stmt = select(HkReport)
    if status_filter:
        stmt = stmt.where(HkReport.status == status_filter)
    total = (
        await db.execute(select(func.count()).select_from(stmt.subquery()))
    ).scalar_one()
    rows = (
        await db.execute(
            stmt.order_by(HkReport.id.desc()).limit(limit).offset(offset)
        )
    ).scalars().all()

    # 批量补用户名与消息内容
    uids = {r.reporter_id for r in rows} | {r.target_user_id for r in rows}
    users = {}
    if uids:
        for u in (
            (await db.execute(select(HkUser).where(HkUser.id.in_(uids))))
            .scalars().all()
        ):
            users[u.id] = u.username
    msg_ids = {r.message_id for r in rows if r.message_id}
    msgs = {}
    if msg_ids:
        for m in (
            (await db.execute(
                select(HkChatMessage).where(HkChatMessage.id.in_(msg_ids))
            )).scalars().all()
        ):
            msgs[m.id] = m.content[:100]

    return {
        "total": total,
        "items": [
            _out(
                r,
                users.get(r.reporter_id, str(r.reporter_id)),
                users.get(r.target_user_id, str(r.target_user_id)),
                msgs.get(r.message_id),
            )
            for r in rows
        ],
    }


class HandleIn(BaseModel):
    action: str  # delete_message / ban_user / dismiss
    ban: bool = False  # action=delete_message 时是否同时封号


@router.post("/{report_id}/handle")
async def handle_report(
    report_id: int,
    data: HandleIn,
    user: HkUser = Depends(admin_service.require_perm("btn:report:handle")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    r = (
        await db.execute(select(HkReport).where(HkReport.id == report_id))
    ).scalar_one_or_none()
    if r is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="举报不存在")

    if data.action == "delete_message":
        if r.message_id:
            msg = (
                await db.execute(
                    select(HkChatMessage).where(HkChatMessage.id == r.message_id)
                )
            ).scalar_one_or_none()
            if msg is not None:
                msg.status = "deleted"
        if data.ban:
            await _ban(db, r.target_user_id)
        r.status = "resolved"
    elif data.action == "ban_user":
        await _ban(db, r.target_user_id)
        r.status = "resolved"
    elif data.action == "dismiss":
        r.status = "dismissed"
    else:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="非法处理动作")

    r.handled_by = user.id
    r.handled_at = utc_now()
    await admin_service.audit(
        db, user, f"report_{data.action}", "report", r.id,
        detail=f"target_user={r.target_user_id}",
    )
    await db.commit()
    return {"ok": True, "status": r.status}


async def _ban(db: AsyncSession, user_id: int) -> None:
    """封号: status→banned, 旧 token 由 get_current_user 拒绝."""
    u = (
        await db.execute(select(HkUser).where(HkUser.id == user_id))
    ).scalar_one_or_none()
    if u is not None:
        u.status = "banned"
