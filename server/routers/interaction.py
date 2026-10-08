"""互动路由: 评论 / 点赞 / 收藏. 当前 target_type 仅 news, 形状保留通用性."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.security import OAuth2PasswordBearer
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkComment, HkFavorite, HkLike, HkReport, HkUser
from services import auth_service

router = APIRouter(prefix="/interaction", tags=["互动"])

# 读接口允许未登录: 有 token 则带出 liked_by_me 等私有态, 无则匿名
_optional_oauth2 = OAuth2PasswordBearer(tokenUrl="/api/auth/login", auto_error=False)

TARGET_TYPES = ("news",)


async def get_optional_user(
    token: str | None = Depends(_optional_oauth2),
    db: AsyncSession = Depends(get_db),
) -> HkUser | None:
    """可选认证: 无 token 或 token 无效返回 None, 不抛 401."""
    if not token:
        return None
    payload = auth_service.decode_token(token)
    if not payload or not payload.get("sub"):
        return None
    result = await db.execute(
        select(HkUser).where(HkUser.id == int(payload["sub"]))
    )
    return result.scalar_one_or_none()


# ---------- Schemas ----------


class CommentCreateIn(BaseModel):
    target_type: str = Field(pattern="^(news)$")
    target_id: int
    content: str = Field(min_length=1, max_length=500)
    reply_to_id: int | None = None


class TargetIn(BaseModel):
    target_type: str = Field(pattern="^(news)$")
    target_id: int


class CommentReportIn(BaseModel):
    reason: str = "other"
    detail: str = Field(default="", max_length=500)


REPORT_REASONS = ("spam", "abuse", "fraud", "porn", "other")


# ---------- Helpers ----------


async def _comment_out(
    db: AsyncSession, c: HkComment, current_user: HkUser | None
) -> dict:
    user = await db.get(HkUser, c.user_id)
    reply_count = await db.scalar(
        select(func.count())
        .select_from(HkComment)
        .where(HkComment.reply_to_id == c.id, HkComment.status == "visible")
    )
    like_count = await db.scalar(
        select(func.count())
        .select_from(HkLike)
        .where(HkLike.target_type == "comment", HkLike.target_id == c.id)
    )
    liked_by_me = False
    if current_user is not None:
        liked_by_me = (
            await db.scalar(
                select(func.count())
                .select_from(HkLike)
                .where(
                    HkLike.target_type == "comment",
                    HkLike.target_id == c.id,
                    HkLike.user_id == current_user.id,
                )
            )
            or 0
        ) > 0
    return {
        "id": c.id,
        "user": {"id": user.id, "username": user.username} if user else None,
        "content": c.content,
        "reply_count": reply_count or 0,
        "like_count": like_count or 0,
        "liked_by_me": liked_by_me,
        "created_at": c.created_at,
    }


# ---------- 评论 ----------


@router.get("/comments")
async def list_comments(
    target_type: str = Query("news", pattern="^(news)$"),
    target_id: int = Query(gt=0),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: HkUser | None = Depends(get_optional_user),
):
    """一级评论: 最新在前, 只出可见."""
    stmt = select(HkComment).where(
        HkComment.target_type == target_type,
        HkComment.target_id == target_id,
        HkComment.reply_to_id.is_(None),
        HkComment.status == "visible",
    )
    total = await db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = (
        await db.scalars(
            stmt.order_by(HkComment.created_at.desc(), HkComment.id.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
    ).all()
    return {
        "items": [await _comment_out(db, c, current_user) for c in rows],
        "total": total or 0,
        "page": page,
        "page_size": page_size,
    }


@router.get("/comments/{comment_id}/replies")
async def list_replies(
    comment_id: int,
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
    current_user: HkUser | None = Depends(get_optional_user),
):
    """某条评论的回复."""
    stmt = select(HkComment).where(
        HkComment.reply_to_id == comment_id,
        HkComment.status == "visible",
    )
    total = await db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = (
        await db.scalars(
            stmt.order_by(HkComment.created_at.asc(), HkComment.id.asc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
    ).all()
    return {
        "items": [await _comment_out(db, c, current_user) for c in rows],
        "total": total or 0,
        "page": page,
        "page_size": page_size,
    }


@router.post("/comments", status_code=201)
async def create_comment(
    data: CommentCreateIn,
    db: AsyncSession = Depends(get_db),
    current_user: HkUser = Depends(auth_service.get_current_user),
):
    if data.reply_to_id is not None:
        parent = await db.get(HkComment, data.reply_to_id)
        if (
            parent is None
            or parent.status != "visible"
            or parent.target_type != data.target_type
            or parent.target_id != data.target_id
        ):
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND, detail="被回复的评论不存在"
            )
    comment = HkComment(
        user_id=current_user.id,
        target_type=data.target_type,
        target_id=data.target_id,
        content=data.content,
        reply_to_id=data.reply_to_id,
        status="visible",
    )
    db.add(comment)
    await db.commit()
    await db.refresh(comment)
    return await _comment_out(db, comment, current_user)


@router.delete("/comments/{comment_id}", status_code=204)
async def delete_comment(
    comment_id: int,
    db: AsyncSession = Depends(get_db),
    current_user: HkUser = Depends(auth_service.get_current_user),
):
    comment = await db.get(HkComment, comment_id)
    if comment is None or comment.status == "deleted":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="评论不存在"
        )
    if comment.user_id != current_user.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="只能删除自己的评论"
        )
    comment.status = "deleted"
    await db.commit()


@router.post("/comments/{comment_id}/report", status_code=201)
async def report_comment(
    comment_id: int,
    data: CommentReportIn,
    db: AsyncSession = Depends(get_db),
    current_user: HkUser = Depends(auth_service.get_current_user),
):
    """举报评论 (App Store 1.2 UGC): 复用 hk_reports, comment_id 标记评论."""
    comment = await db.get(HkComment, comment_id)
    if comment is None or comment.status == "deleted":
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="评论不存在"
        )
    if comment.user_id == current_user.id:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="不能举报自己的评论"
        )
    if data.reason not in REPORT_REASONS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="非法举报类型"
        )
    dup = await db.scalar(
        select(func.count()).select_from(
            select(HkReport)
            .where(
                HkReport.reporter_id == current_user.id,
                HkReport.comment_id == comment_id,
                HkReport.status == "pending",
            )
            .subquery()
        )
    )
    if dup:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail="已举报过, 等待处理"
        )
    db.add(
        HkReport(
            reporter_id=current_user.id,
            target_user_id=comment.user_id,
            comment_id=comment_id,
            reason=data.reason,
            detail=data.detail,
        )
    )
    await db.commit()
    return {"ok": True}


# ---------- 点赞 / 收藏 ----------


@router.post("/like")
async def toggle_like(
    data: TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: HkUser = Depends(auth_service.get_current_user),
):
    existing = (
        await db.scalars(
            select(HkLike).where(
                HkLike.user_id == current_user.id,
                HkLike.target_type == data.target_type,
                HkLike.target_id == data.target_id,
            )
        )
    ).first()
    if existing is None:
        db.add(
            HkLike(
                user_id=current_user.id,
                target_type=data.target_type,
                target_id=data.target_id,
            )
        )
        liked = True
    else:
        await db.delete(existing)
        liked = False
    await db.commit()
    like_count = await db.scalar(
        select(func.count())
        .select_from(HkLike)
        .where(
            HkLike.target_type == data.target_type,
            HkLike.target_id == data.target_id,
        )
    )
    return {"liked": liked, "like_count": like_count or 0}


@router.post("/favorite")
async def toggle_favorite(
    data: TargetIn,
    db: AsyncSession = Depends(get_db),
    current_user: HkUser = Depends(auth_service.get_current_user),
):
    existing = (
        await db.scalars(
            select(HkFavorite).where(
                HkFavorite.user_id == current_user.id,
                HkFavorite.target_type == data.target_type,
                HkFavorite.target_id == data.target_id,
            )
        )
    ).first()
    if existing is None:
        db.add(
            HkFavorite(
                user_id=current_user.id,
                target_type=data.target_type,
                target_id=data.target_id,
            )
        )
        favorited = True
    else:
        await db.delete(existing)
        favorited = False
    await db.commit()
    return {"favorited": favorited}


# ---------- 详情页初始态 ----------


@router.get("/state")
async def interaction_state(
    target_type: str = Query("news", pattern="^(news)$"),
    target_id: int = Query(gt=0),
    db: AsyncSession = Depends(get_db),
    current_user: HkUser | None = Depends(get_optional_user),
):
    """详情页首屏: 计数 + 当前用户态."""
    like_count = await db.scalar(
        select(func.count())
        .select_from(HkLike)
        .where(
            HkLike.target_type == target_type, HkLike.target_id == target_id
        )
    )
    comment_count = await db.scalar(
        select(func.count())
        .select_from(HkComment)
        .where(
            HkComment.target_type == target_type,
            HkComment.target_id == target_id,
            HkComment.status == "visible",
        )
    )
    liked_by_me = favorited_by_me = False
    if current_user is not None:
        liked_by_me = (
            await db.scalar(
                select(func.count())
                .select_from(HkLike)
                .where(
                    HkLike.target_type == target_type,
                    HkLike.target_id == target_id,
                    HkLike.user_id == current_user.id,
                )
            )
            or 0
        ) > 0
        favorited_by_me = (
            await db.scalar(
                select(func.count())
                .select_from(HkFavorite)
                .where(
                    HkFavorite.target_type == target_type,
                    HkFavorite.target_id == target_id,
                    HkFavorite.user_id == current_user.id,
                )
            )
            or 0
        ) > 0
    return {
        "like_count": like_count or 0,
        "comment_count": comment_count or 0,
        "liked_by_me": liked_by_me,
        "favorited_by_me": favorited_by_me,
    }
