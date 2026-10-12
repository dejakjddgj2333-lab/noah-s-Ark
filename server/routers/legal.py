"""协议公开访问路由 (无需登录): 隐私政策/用户协议, 返回完整 HTML."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.responses import HTMLResponse
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkLegalDoc

router = APIRouter(prefix="/legal", tags=["协议"])

# 富文本片段的页面外壳: 后台富文本编辑器只存正文片段, 此处包成完整 HTML 输出.
# 存量完整 HTML 文档 (含 <html) 原样直出, 不重复包裹.
_SHELL = """<!DOCTYPE html>
<html lang="zh-CN">
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{{TITLE}}</title>
<style>
body { max-width: 760px; margin: 0 auto; padding: 20px 16px 48px;
  font-family: -apple-system, "PingFang SC", "Microsoft YaHei", sans-serif;
  font-size: 15px; line-height: 1.8; color: #1f2430; background: #ffffff; }
h1 { font-size: 22px; text-align: center; }
h2 { font-size: 17px; margin-top: 28px; }
h3 { font-size: 15px; }
img { max-width: 100%; }
table { border-collapse: collapse; width: 100%; }
td, th { border: 1px solid #d8dce6; padding: 6px 10px; }
a { color: #4c6fff; }
blockquote { margin: 0; padding: 4px 14px; border-left: 3px solid #d8dce6; color: #5a607f; }
@media (prefers-color-scheme: dark) {
  body { background: #12141a; color: #e2e5ee; }
  td, th { border-color: #333a4a; }
  blockquote { border-left-color: #333a4a; color: #9aa3b5; }
}
</style></head>
<body>{{CONTENT}}</body></html>"""


def _render(doc: HkLegalDoc) -> str:
    content = doc.content or ""
    if "<html" in content[:256].lower():
        return content  # 存量完整文档直出
    return _SHELL.replace("{{TITLE}}", doc.title or "").replace("{{CONTENT}}", content)


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
    return _render(await _get_doc(db, "privacy"))


@router.get("/terms", response_class=HTMLResponse)
async def terms(db: AsyncSession = Depends(get_db)) -> str:
    """用户协议完整 HTML (公开)."""
    return _render(await _get_doc(db, "terms"))
