"""邀请关系模型. 每名用户一条记录: 专属邀请码 + 上级(绑定后永久固定)."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String

from models.hk import HkBase, utc_now


class HkInvite(HkBase):
    """邀请绑定. inviter_id 一经写入不再变更; 不提供更换/解绑."""

    __tablename__ = "hk_invites"

    user_id = Column(Integer, ForeignKey("hk_users.id"), primary_key=True)
    invite_code = Column(String(16), unique=True, nullable=False, index=True)
    inviter_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=True, index=True
    )
    bound_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)
