"""hk 资讯采集器 (异步版, 移植自 okx jobs/news_collector).

APITube 源 30 分钟一轮: 拉增量 → 去重入库 → 英文稿并发翻译成中文.
写入共享表 news_articles (镜像模型见 services/news_models.py),
(source, external_id) 唯一约束去重, 与 okx 侧采集器并存安全.

分类: 有长正文 (≥300字) 进 news, 短讯/无正文进 flash
(okx 旧规则 "有正文即 news" 导致 09-05 后 flash 断更, 这里按长度分).
"""
from __future__ import annotations

import asyncio
import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

import httpx
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import SessionLocal
from models.shared import NewsArticle, NewsSyncState
from services.content_filter import is_blocked
from services.html_text import body_html_to_text
from services.translate_service import translate_article

logger = logging.getLogger(__name__)

_BJ_OFFSET = timedelta(hours=8)  # 北京时间

_CJK_RE = re.compile(r"[一-鿿]")
# 正文达到该长度算长文进资讯频道, 否则进快讯
_NEWS_BODY_MIN = 300


def _bj_now() -> datetime:
    """北京时间 naive (publish_at 入库口径, 与 okx 一致)."""
    return datetime.utcnow() + _BJ_OFFSET


def _parse_dt(raw) -> datetime | None:
    if not raw:
        return None
    try:
        s = str(raw).replace("Z", "+00:00")
        dt = datetime.fromisoformat(s)
        if dt.tzinfo is not None:
            # 带时区 → 转北京时间 naive 入库 (与 okx 口径一致)
            return datetime.utcfromtimestamp(dt.timestamp()) + _BJ_OFFSET
        return dt
    except (ValueError, TypeError):
        return None


@dataclass
class CollectedArticle:
    external_id: str
    title: str
    summary: str | None = None
    content: str | None = None
    source_url: str | None = None
    cover_url: str | None = None
    category: str = "flash"
    publish_at: datetime = field(default_factory=_bj_now)
    sentiment: str | None = None


class ApitubeCollector:
    """APITube 资讯源 (https://docs.apitube.io). 中英双语, 游标=上次最新发布时间."""

    source = "apitube"
    API_URL = "https://api.apitube.io/v1/news/everything"
    QUERY = "bitcoin OR ethereum OR crypto OR blockchain OR solana OR OKX OR binance"
    LANGUAGES = "en,zh"

    async def fetch(
        self, last_cursor: str | None
    ) -> tuple[list[CollectedArticle], str | None]:
        if not config.apitube_api_key:
            raise RuntimeError("APITUBE_API_KEY 未配置")
        results: list[dict] = []
        async with httpx.AsyncClient(timeout=15) as client:
            for page in range(1, 6):
                resp = await client.get(
                    self.API_URL,
                    params={
                        "query": self.QUERY,
                        "language.code": self.LANGUAGES,
                        "sort.by": "published_at",
                        "sort.order": "asc",
                        "per_page": 50,
                        "page": page,
                        "published_at.start": last_cursor or "NOW-7DAYS",
                        "published_at.end": "NOW",
                    },
                    headers={"X-API-Key": config.apitube_api_key},
                )
                resp.raise_for_status()
                payload = resp.json()
                results.extend(payload.get("results") or [])
                if not payload.get("has_next_pages"):
                    break

        articles: list[CollectedArticle] = []
        newest: str | None = None
        for a in results:
            published = _parse_dt(a.get("published_at"))
            image = a.get("image")
            if isinstance(image, dict):
                image = image.get("url") or image.get("href")
            body = body_html_to_text(a.get("body_html")) or a.get("body") or None
            summary = a.get("description") or " ".join(a.get("summary") or []) or None
            title = (a.get("title") or "").strip()
            if not title:
                continue
            if is_blocked(title, summary, body):
                continue
            sentiment = ((a.get("sentiment") or {}).get("overall") or {}).get("polarity")
            articles.append(CollectedArticle(
                external_id=str(a.get("id")),
                title=title,
                summary=summary,
                content=body,
                source_url=a.get("href"),
                cover_url=image if isinstance(image, str) else None,
                # 长文进资讯, 短讯/无正文进快讯
                category="news" if body and len(body) >= _NEWS_BODY_MIN else "flash",
                publish_at=published or _bj_now(),
                sentiment=sentiment if sentiment in ("positive", "negative", "neutral") else None,
            ))
            if a.get("published_at"):
                newest = a["published_at"]  # asc 序, 最后一条即最新
        return articles, newest


async def _insert_batch(
    db: AsyncSession, source: str, articles: list[CollectedArticle]
) -> list[tuple[int, CollectedArticle]]:
    """逐条入库, (source, external_id) 冲突跳过. 返回 [(id, item)]."""
    inserted: list[tuple[int, CollectedArticle]] = []
    for item in articles:
        row = NewsArticle(
            title=item.title[:300],
            summary=(item.summary or "")[:512] or None,
            content=item.content,
            cover_url=item.cover_url,
            source=source,
            source_url=item.source_url,
            external_id=item.external_id[:128],
            category=item.category,
            publish_at=item.publish_at,
            sentiment=item.sentiment,
            status="published",
            # 原文备份: 翻译覆盖 title/summary/content 后这里留英文底稿
            title_en=item.title[:300],
            summary_en=(item.summary or "")[:512] or None,
            content_en=item.content,
        )
        db.add(row)
        try:
            await db.flush()
            inserted.append((row.id, item))
        except IntegrityError:
            await db.rollback()  # 已存在, 跳过
    return inserted


async def _translate_pending(
    inserted: list[tuple[int, CollectedArticle]]
) -> None:
    """并发翻译英文稿: 本轮新稿 + 存量未翻 (每轮限 40), 翻好一篇更新一篇."""
    todo: dict[int, tuple[str, str | None, str | None]] = {
        rid: (it.title, it.summary, it.content)
        for rid, it in inserted
        if it.title and not _CJK_RE.search(it.title)
    }
    async with SessionLocal() as db:
        backlog = (
            await db.scalars(
                select(NewsArticle)
                .where(~NewsArticle.title.op("~")(r"[一-鿿]"))
                .order_by(NewsArticle.publish_at.desc())
                .limit(40)
            )
        ).all()
        for row in backlog:
            if row.id not in todo:
                todo[row.id] = (row.title, row.summary, row.content)
    if not todo:
        return

    sem = asyncio.Semaphore(8)

    async def _one(rid: int, payload: tuple[str, str | None, str | None]) -> None:
        async with sem:
            try:
                tr = await translate_article(*payload)
            except Exception:
                tr = None
            if not tr:
                return
            async with SessionLocal() as s:
                try:
                    row = await s.get(NewsArticle, rid)
                    if row is None:
                        return
                    row.title = tr["title"][:300]
                    row.summary = (tr["summary"] or row.summary or "")[:512] or None
                    if tr["content"]:
                        row.content = tr["content"]
                    await s.commit()
                except Exception as exc:
                    await s.rollback()
                    logger.warning("news translate update failed id=%s: %s", rid, exc)

    await asyncio.gather(*[_one(rid, p) for rid, p in todo.items()])
    logger.info("news translated %d articles", len(todo))


async def run_collect() -> int:
    """执行一轮采集, 返回新入库条数. 异常不抛出 (调度器常驻)."""
    collector = ApitubeCollector()
    async with SessionLocal() as db:
        state = (
            await db.scalars(
                select(NewsSyncState).where(
                    NewsSyncState.source == collector.source
                )
            )
        ).first()
        if state is None:
            state = NewsSyncState(source=collector.source)
            db.add(state)
            await db.flush()
        try:
            # rollback 会 expire 对象, 游标先取到本地, 避免懒加载触发同步 IO
            cursor = state.last_cursor
            await db.rollback()  # fetch 纯拉取, 先释放事务避免远端 PG 杀空闲连接
            articles, new_cursor = await collector.fetch(cursor)
        except Exception as exc:
            state = (
                await db.scalars(
                    select(NewsSyncState).where(
                        NewsSyncState.source == collector.source
                    )
                )
            ).first()
            if state is not None:
                state.last_run_at = datetime.utcnow()
                state.last_status = "error"
                state.last_error = str(exc)[:512]
                await db.commit()
            logger.warning("news collector failed: %s", exc)
            return 0

        inserted = await _insert_batch(db, collector.source, articles)
        state = (
            await db.scalars(
                select(NewsSyncState).where(
                    NewsSyncState.source == collector.source
                )
            )
        ).first()
        if state is not None:
            state.last_cursor = new_cursor or state.last_cursor
            state.last_run_at = datetime.utcnow()
            state.last_status = "ok"
            state.last_error = None
        await db.commit()
    logger.info("news collector inserted %d articles", len(inserted))
    await _translate_pending(inserted)
    return len(inserted)
