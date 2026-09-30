"""共享库中的 okx 表 — hk 只读映射. 建表/写入归 okx 后端, 勿动."""
from __future__ import annotations

from sqlalchemy import Column, DateTime, Integer, String, Text
from sqlalchemy.orm import declarative_base

SharedBase = declarative_base()


class NewsArticle(SharedBase):
    """资讯 (okx 采集, hk 只读). 字段对齐 okx backend models/business.py:613."""
    __tablename__ = "news_articles"

    id = Column(Integer, primary_key=True)
    title = Column(String(300), nullable=False)
    summary = Column(String(512))
    content = Column(Text)
    cover_url = Column(String(512))
    source = Column(String(32), nullable=False, default="manual")
    source_url = Column(String(512))
    external_id = Column(String(128))
    category = Column(String(32), nullable=False, default="news")
    publish_at = Column(DateTime, nullable=False)
    status = Column(String(16), nullable=False, default="published")
    sentiment = Column(String(16))
    title_en = Column(String(300))
    summary_en = Column(String(512))
    content_en = Column(Text)
    like_count = Column(Integer, default=0)
    comment_count = Column(Integer, default=0)
    favorite_count = Column(Integer, default=0)
    share_count = Column(Integer, default=0)


class MacroEvent(SharedBase):
    """宏观日历事件 (okx 采集, hk 只读). 字段对齐 okx backend models/business.py MacroEvent."""

    __tablename__ = "macro_events"

    id = Column(Integer, primary_key=True)
    external_id = Column(String(128))
    event_at = Column(DateTime, nullable=False)  # UTC naive
    country = Column(String(32))
    currency = Column(String(16))
    name = Column(String(300))
    importance = Column(Integer, default=1)  # 1-3
    previous = Column(String(64))
    forecast = Column(String(64))
    actual = Column(String(64))
    unit = Column(String(32))
    source = Column(String(32))
