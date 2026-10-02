"""资讯路由: 列表 / 详情. 共享库只读, 采集归 okx 侧."""
from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkComment, HkLike
from models.shared import MacroEvent, NewsArticle

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
    keyword: str | None = Query(None),
    lang: str = Query("zh"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=50),
    db: AsyncSession = Depends(get_db),
):
    """资讯列表: 发布时间倒序, 只出已发布. lang=zh 中文, 其他出原文(有备份时).
    keyword: 标题/摘要模糊匹配 (用于 行业政策 等主题筛选)."""
    if category and category not in NEWS_CATEGORIES:
        raise HTTPException(status_code=400, detail=f"分类必须是: {', '.join(NEWS_CATEGORIES)}")

    stmt = select(NewsArticle).where(NewsArticle.status == "published")
    if category:
        stmt = stmt.where(NewsArticle.category == category)
    if source:
        stmt = stmt.where(NewsArticle.source == source)
    if keyword:
        # 逗号分隔多关键词, OR 匹配 (如 行业政策: 监管,政策,SEC,法案)
        terms = [t.strip() for t in keyword.split(",") if t.strip()]
        if terms:
            conds = [
                NewsArticle.title.ilike(f"%{t}%")
                | NewsArticle.summary.ilike(f"%{t}%")
                for t in terms
            ]
            stmt = stmt.where(or_(*conds))

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


@router.get("/macro-calendar")
async def get_macro_calendar(
    date: str | None = Query(None, description="北京时间日期 YYYY-MM-DD, 默认今天"),
    db: AsyncSession = Depends(get_db),
):
    """宏观日历: 按北京时间日过滤 (event_at 存 UTC, 换算 ±8h)."""
    from datetime import datetime, timedelta

    try:
        day = (
            datetime.strptime(date, "%Y-%m-%d")
            if date
            else datetime.utcnow() + timedelta(hours=8)
        )
    except ValueError:
        raise HTTPException(status_code=400, detail="date 格式: YYYY-MM-DD")
    bj_start = day.replace(hour=0, minute=0, second=0, microsecond=0)
    # 北京时间 [start, +24h) 对应 UTC 区间
    utc_start = bj_start - timedelta(hours=8)
    utc_end = utc_start + timedelta(days=1)

    try:
        rows = (
            await db.scalars(
                select(MacroEvent)
                .where(
                    MacroEvent.event_at >= utc_start, MacroEvent.event_at < utc_end
                )
                .order_by(MacroEvent.event_at)
            )
        ).all()
    except Exception:
        # macro_events 表未迁移 (okx 侧未部署) 时返回空, 前端显示 暂无数据
        await db.rollback()
        rows = []

    # 事件名中文化 (DeepSeek 批量翻译 + hk_macro_name_zh 缓存, 失败回退英文)
    from services.macro_translate import zh_name_map

    try:
        zh_map = await zh_name_map(db, [e.name for e in rows if e.name])
    except Exception:
        await db.rollback()
        zh_map = {}

    return {
        "date": bj_start.strftime("%Y-%m-%d"),
        "items": [
            {
                "id": e.id,
                # 转北京时间输出
                "event_at": (e.event_at + timedelta(hours=8)).strftime("%H:%M"),
                "country": e.country,
                "currency": e.currency,
                "name": zh_map.get(e.name) or e.name,
                "name_en": e.name,
                "importance": e.importance,
                "previous": e.previous,
                "forecast": e.forecast,
                "actual": e.actual,
                "unit": e.unit,
            }
            for e in rows
        ],
    }


@router.get("/macro-calendar/{event_id}/detail")
async def get_macro_event_detail(
    event_id: int,
    db: AsyncSession = Depends(get_db),
):
    """宏观事件详情: 中文名/解读/历史走势 (同名同币种近 12 期)."""
    from datetime import timedelta

    from services.macro_translate import zh_desc_map, zh_name_map

    e = await db.get(MacroEvent, event_id)
    if e is None:
        raise HTTPException(status_code=404, detail="事件不存在")

    try:
        zh_name = (await zh_name_map(db, [e.name])).get(e.name) if e.name else None
        desc = (await zh_desc_map(db, [e.name])).get(e.name) if e.name else None
    except Exception:
        await db.rollback()
        zh_name = desc = None

    # 历史: 同名同币种, 早于本期, 近 12 期 (走势用)
    try:
        history = (
            await db.scalars(
                select(MacroEvent)
                .where(
                    MacroEvent.name == e.name,
                    MacroEvent.currency == e.currency,
                    MacroEvent.event_at < e.event_at,
                )
                .order_by(MacroEvent.event_at.desc())
                .limit(12)
            )
        ).all()
    except Exception:
        await db.rollback()
        history = []

    return {
        "id": e.id,
        "event_at": (e.event_at + timedelta(hours=8)).strftime("%Y-%m-%d %H:%M"),
        "country": e.country,
        "currency": e.currency,
        "name": zh_name or e.name,
        "name_en": e.name,
        "desc_zh": desc,
        "importance": e.importance,
        "previous": e.previous,
        "forecast": e.forecast,
        "actual": e.actual,
        "unit": e.unit,
        # 时间倒序 -> 前端反转为正序画图
        "history": [
            {
                "date": (h.event_at + timedelta(hours=8)).strftime("%Y-%m-%d"),
                "previous": h.previous,
                "forecast": h.forecast,
                "actual": h.actual,
            }
            for h in history
        ],
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
    data = _news_out(article, lang)
    # 详情页用 hk 互动表的实时计数覆盖静态列 (列表页仍走静态列省查询)
    data["like_count"] = await db.scalar(
        select(func.count())
        .select_from(HkLike)
        .where(HkLike.target_type == "news", HkLike.target_id == news_id)
    ) or 0
    data["comment_count"] = await db.scalar(
        select(func.count())
        .select_from(HkComment)
        .where(
            HkComment.target_type == "news",
            HkComment.target_id == news_id,
            HkComment.status == "visible",
        )
    ) or 0
    return data
