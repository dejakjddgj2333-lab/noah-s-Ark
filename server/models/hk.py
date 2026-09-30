"""hk 自有表 (hk_ 前缀), 与 okx 表隔离, 便于日后迁服拆分."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import declarative_base

HkBase = declarative_base()


def utc_now() -> datetime:
    return datetime.now(timezone.utc).replace(tzinfo=None)


class HkUser(HkBase):
    """用户: 用户名密码登录, 注册时邮箱验证码校验后自动绑定."""

    __tablename__ = "hk_users"

    id = Column(Integer, primary_key=True, index=True)
    username = Column(String(32), unique=True, nullable=False, index=True)
    password_hash = Column(String(128), nullable=False)
    email = Column(String(128), unique=True, nullable=False, index=True)
    email_verified = Column(Boolean, nullable=False, default=True)  # 注册即验证
    avatar_url = Column(String(512), nullable=True)
    status = Column(String(16), nullable=False, default="active")  # active/banned
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkEmailCode(HkBase):
    """邮箱验证码: 注册/换绑用. 6 位数字, 10 分钟有效."""

    __tablename__ = "hk_email_codes"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(128), nullable=False, index=True)
    code = Column(String(8), nullable=False)
    purpose = Column(String(16), nullable=False, default="register")
    used = Column(Boolean, nullable=False, default=False)
    expires_at = Column(DateTime, nullable=False)
    created_at = Column(DateTime, default=utc_now)


class HkComment(HkBase):
    """通用评论: target_type 区分目标(当前仅 news), reply_to_id 支持楼中楼."""

    __tablename__ = "hk_comments"
    __table_args__ = (
        Index("ix_hk_comments_target", "target_type", "target_id"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    target_type = Column(String(16), nullable=False)  # 当前仅 news
    target_id = Column(Integer, nullable=False)
    content = Column(Text, nullable=False)
    reply_to_id = Column(Integer, nullable=True)  # 一级评论为 NULL, 指向本表 id
    status = Column(String(16), nullable=False, default="visible")  # visible/deleted
    created_at = Column(DateTime, default=utc_now, index=True)


class HkLike(HkBase):
    """通用点赞 (幂等, 唯一约束防重)."""

    __tablename__ = "hk_likes"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "target_type", "target_id", name="uq_hk_like_user_target"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    target_type = Column(String(16), nullable=False)  # 当前仅 news
    target_id = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=utc_now)


class HkFavorite(HkBase):
    """通用收藏 (幂等, 唯一约束防重)."""

    __tablename__ = "hk_favorites"
    __table_args__ = (
        UniqueConstraint(
            "user_id", "target_type", "target_id", name="uq_hk_favorite_user_target"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    target_type = Column(String(16), nullable=False)  # 当前仅 news
    target_id = Column(Integer, nullable=False)
    created_at = Column(DateTime, default=utc_now)
