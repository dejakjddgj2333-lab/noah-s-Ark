"""hk 自有表 (hk_ 前缀), 与 okx 表隔离, 便于日后迁服拆分."""
from __future__ import annotations

from datetime import datetime, timezone

from sqlalchemy import (
    Boolean,
    Column,
    DateTime,
    Float,
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
    nickname = Column(String(32), nullable=True)  # 展示昵称, 空=显示 username
    password_hash = Column(String(128), nullable=False)
    email = Column(String(128), unique=True, nullable=False, index=True)
    email_verified = Column(Boolean, nullable=False, default=True)  # 注册即验证
    avatar_url = Column(String(512), nullable=True)
    status = Column(String(16), nullable=False, default="active")  # active/banned
    role_id = Column(Integer, ForeignKey("hk_roles.id"), nullable=True)  # 后台角色, NULL=普通用户
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkRole(HkBase):
    """后台角色 (RBAC): perms 为权限码 JSON 数组, ['*']=全部; builtin 角色不可删."""

    __tablename__ = "hk_roles"

    id = Column(Integer, primary_key=True, index=True)
    code = Column(String(32), unique=True, nullable=False, index=True)
    name = Column(String(32), nullable=False)
    perms = Column(Text, nullable=False, default="[]")  # JSON array of perm codes
    builtin = Column(Boolean, nullable=False, default=False)
    created_at = Column(DateTime, default=utc_now)


class HkEmailCode(HkBase):
    """邮箱验证码: 注册/换绑用. 6 位数字, 10 分钟有效."""

    __tablename__ = "hk_email_codes"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String(128), nullable=False, index=True)
    code = Column(String(8), nullable=False)
    purpose = Column(String(16), nullable=False, default="register")
    used = Column(Boolean, nullable=False, default=False)
    attempts = Column(Integer, nullable=False, default=0)  # 校验失败累计, 超限作废
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
    # 富媒体: text/image/audio/video; 非文本时 file_url 必填, duration 秒(音视频)
    msg_type = Column(String(16), nullable=False, default="text")
    file_url = Column(String(512), nullable=True)
    duration = Column(Integer, nullable=True)
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


class HkMacroNameZh(HkBase):
    """宏观日历事件名中文缓存 (DeepSeek 批量翻译, 翻一次永久复用)."""

    __tablename__ = "hk_macro_name_zh"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(300), unique=True, nullable=False, index=True)  # 英文原名
    name_zh = Column(String(300), nullable=False)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkMacroDescZh(HkBase):
    """宏观指标解读缓存 (DeepSeek 生成, 一次永久复用)."""

    __tablename__ = "hk_macro_desc_zh"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(300), unique=True, nullable=False, index=True)  # 英文原名
    desc_zh = Column(Text, nullable=False)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkLiqEvent(HkBase):
    """爆仓事件 (免费模式自建聚合): Binance/Bybit 强平 WS 写入, 保留 48h.

    side = 被强平的仓位方向: long=多头爆仓 / short=空头爆仓.
    """

    __tablename__ = "hk_liq_events"
    __table_args__ = (Index("ix_hk_liq_events_ts_ex", "ts", "exchange"),)

    id = Column(Integer, primary_key=True, index=True)
    ts = Column(DateTime, nullable=False, index=True)  # UTC naive
    exchange = Column(String(16), nullable=False)  # Binance/Bybit
    symbol = Column(String(32), nullable=False)
    side = Column(String(8), nullable=False)  # long/short
    price = Column(Float, nullable=False, default=0)
    qty = Column(Float, nullable=False, default=0)
    notional_usd = Column(Float, nullable=False, default=0)
