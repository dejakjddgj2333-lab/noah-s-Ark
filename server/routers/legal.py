"""协议公开访问路由 (无需登录): 隐私政策/用户协议, 返回完整 HTML."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkLegalDoc

router = APIRouter(prefix="/legal", tags=["协议"])


async def _get_doc(db: AsyncSession, doc_key: str) -> HkLegalDoc:
    doc = (
        await db.execute(select(HkLegalDoc).where(HkLegalDoc.doc_key == doc_key))
    ).scalar_one_or_none()
    if doc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="协议不存在")
    return doc


@router.get("/privacy", response_class=HTMLResponse)
async def privacy(db: AsyncSession = Depends(get_db)) -> str:
    """隐私政策完整 HTML (公开)."""
    doc = await _get_doc(db, "privacy")
    return doc.content


@router.get("/terms", response_class=HTMLResponse)
async def terms(db: AsyncSession = Depends(get_db)) -> str:
    """用户协议完整 HTML (公开)."""
    doc = await _get_doc(db, "terms")
    return doc.content
