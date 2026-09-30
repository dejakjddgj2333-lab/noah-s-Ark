"""购买订单. Phase 1 仅承载"成功购买记录"供补绑全层级检查; 结算字段 Phase 2 起扩展."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, DateTime, ForeignKey, Integer, Numeric, String

from models.hk import HkBase, utc_now


class HkOrder(HkBase):
    """订单. status='effective' 即需求文档所称"成功购买"."""

    __tablename__ = "hk_orders"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    product_id = Column(String(32), nullable=False, default="")
    amount = Column(Numeric(18, 2), nullable=False, default=0)
    status = Column(String(16), nullable=False, default="effective", index=True)
    effective_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)
