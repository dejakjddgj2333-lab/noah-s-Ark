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


# ---------- IM (聊天) ----------


class HkFriendRequest(HkBase):
    """好友申请: pending/accepted/rejected."""

    __tablename__ = "hk_friend_requests"
    __table_args__ = (
        Index("ix_hk_friend_requests_to_status", "to_user_id", "status"),
    )

    id = Column(Integer, primary_key=True, index=True)
    from_user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    to_user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    status = Column(String(16), nullable=False, default="pending")
    created_at = Column(DateTime, default=utc_now)


class HkFriendship(HkBase):
    """好友关系: 通过后双向各存一行."""

    __tablename__ = "hk_friendships"
    __table_args__ = (
        UniqueConstraint("user_id", "friend_id", name="uq_hk_friendship_pair"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    friend_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    created_at = Column(DateTime, default=utc_now)


class HkConversation(HkBase):
    """会话: direct 单聊 / group 群聊 (name 仅群聊有)."""

    __tablename__ = "hk_conversations"

    id = Column(Integer, primary_key=True, index=True)
    type = Column(String(16), nullable=False)  # direct/group
    name = Column(String(32), nullable=True)
    created_by = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    created_at = Column(DateTime, default=utc_now)


class HkConversationMember(HkBase):
    """会话成员: last_read_message_id 用于未读数."""

    __tablename__ = "hk_conversation_members"
    __table_args__ = (
        UniqueConstraint(
            "conversation_id", "user_id", name="uq_hk_conv_member"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("hk_conversations.id"), nullable=False, index=True
    )
    user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    last_read_message_id = Column(Integer, nullable=False, default=0)
    created_at = Column(DateTime, default=utc_now)


class HkChatMessage(HkBase):
    """聊天消息: reply_to_id 自引用, status visible/deleted."""

    __tablename__ = "hk_chat_messages"

    id = Column(Integer, primary_key=True, index=True)
    conversation_id = Column(
        Integer, ForeignKey("hk_conversations.id"), nullable=False, index=True
    )
    sender_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    content = Column(Text, nullable=False)
    reply_to_id = Column(
        Integer, ForeignKey("hk_chat_messages.id"), nullable=True
    )
    status = Column(String(16), nullable=False, default="visible")
    created_at = Column(DateTime, default=utc_now, index=True)


class HkMessageReaction(HkBase):
    """消息表情回应: (message, user, emoji) 唯一, 重复即取消."""

    __tablename__ = "hk_message_reactions"
    __table_args__ = (
        UniqueConstraint(
            "message_id", "user_id", "emoji", name="uq_hk_reaction_m_u_e"
        ),
    )

    id = Column(Integer, primary_key=True, index=True)
    message_id = Column(
        Integer, ForeignKey("hk_chat_messages.id"), nullable=False, index=True
    )
    user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    emoji = Column(String(16), nullable=False)
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
