"""协议管理后台路由 (管理员): 读取/编辑 隐私政策/用户协议."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkLegalDoc, HkUser
from services import admin_service

router = APIRouter(prefix="/admin/legal", tags=["后台-协议"])

_VALID_KEYS = ("privacy", "terms")


class LegalDocIn(BaseModel):
    title: str
    content: str


def _doc_to_dict(doc: HkLegalDoc) -> dict:
    return {"doc_key": doc.doc_key, "title": doc.title, "content": doc.content,
            "updated_at": doc.updated_at}


@router.get("")
async def get_legal_docs(
    user: HkUser = Depends(admin_service.require_perm("page:legal")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """返回两份协议 {privacy:{...}, terms:{...}} (管理员, 读)."""
    result = await db.execute(select(HkLegalDoc))
    docs = {d.doc_key: _doc_to_dict(d) for d in result.scalars().all()}
    return {k: docs.get(k) for k in _VALID_KEYS}


@router.put("/{doc_key}")
async def update_legal_doc(
    doc_key: str,
    data: LegalDocIn,
    user: HkUser = Depends(admin_service.require_perm("btn:legal:edit")),
    db: AsyncSession = Depends(get_db),
) -> dict:
    """更新协议 (管理员, 写). doc_key 仅 privacy/terms."""
    if doc_key not in _VALID_KEYS:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="协议不存在")
    doc = (
        await db.execute(select(HkLegalDoc).where(HkLegalDoc.doc_key == doc_key))
    ).scalar_one_or_none()
    if doc is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="协议不存在")
    doc.title = data.title
    doc.content = data.content
    await admin_service.audit(
        db, user, "legal_update", "legal_doc", doc.id, detail=f"key={doc_key}"
    )
    await db.commit()
    return _doc_to_dict(doc)
