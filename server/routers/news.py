"""资讯路由: 列表 / 详情. 共享库只读, 采集归 okx 侧."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.shared import NewsArticle

router = APIRouter(prefix="/news", tags=["资讯"])

NEWS_CATEGORIES = ("flash", "notice", "research", "news")


def _news_out(a: NewsArticle, lang: str = "zh", with_content: bool = True) -> dict:
    # 非中文: 有原文备份则出原文, 老数据无备份回退中文
    use_original = lang != "zh" and a.title_en
    data = {
        "id": a.id,
        "title": a.title_en if use_original else a.title,
        "summary": a.summary_en if use_original else a.summary,
        "cover_url": a.cover_url,
        "source": a.source,
        "source_url": a.source_url,
        "category": a.category,
        "sentiment": a.sentiment,
        "publish_at": a.publish_at,
        "like_count": a.like_count,
        "comment_count": a.comment_count,
        "favorite_count": a.favorite_count,
        "share_count": a.share_count,
    }
    if with_content:
        data["content"] = a.content_en if use_original else a.content
    return data


@router.get("")
async def list_news(
    category: str | None = Query(None),
    source: str | None = Query(None),
    lang: str = Query("zh"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """资讯列表: 发布时间倒序, 只出已发布. lang=zh 中文, 其他出原文(有备份时)."""
    if category and category not in NEWS_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"分类必须是: {', '.join(NEWS_CATEGORIES)}")

    stmt = select(NewsArticle).where(NewsArticle.status == "published")
    if category:
        stmt = stmt.where(NewsArticle.category == category)
    if source:
        stmt = stmt.where(NewsArticle.source == source)

    total = await db.scalar(select(func.count()).select_from(stmt.subquery()))
    rows = (
        await db.scalars(
            stmt.order_by(NewsArticle.publish_at.desc())
            .offset((page - 1) * page_size)
            .limit(page_size)
        )
    ).all()

    # 列表页不带正文, 减小流量
    return {
        "items": [_news_out(a, lang, with_content=False) for a in rows],
        "total": total or 0,
        "page": page,
        "page_size": page_size,
    }


@router.get("/{news_id}")
async def get_news(
    news_id: int,
    lang: str = Query("zh"),
    db: AsyncSession = Depends(get_db),
):
    """资讯详情."""
    article = await db.get(NewsArticle, news_id)
    if article is None or article.status != "published":
        raise HTTPException(status_code=404, detail="资讯不存在或已下架")
    return _news_out(article, lang)
