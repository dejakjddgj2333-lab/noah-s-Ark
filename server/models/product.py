"""产品模型. 参数由后台配置, 上架前须通过 services/product_service.validate_product 校验."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, DateTime, Integer, Numeric, String, Text

from models.hk import HkBase, utc_now

# 收益返还方式 (需求文档第二节):
# daily=每满24小时; period_7d=每隔7天; period_30d=每隔30天; expiry=到期一次性
RETURN_METHODS = ("daily", "period_7d", "period_30d", "expiry")

# 产品状态: draft=草稿/待上架; published=已上架可购买; offline=已下架
PRODUCT_STATUSES = ("draft", "published", "offline")


class HkProduct(HkBase):
    """产品配置表. 正式参数由后台运营配置, 不在代码里固定."""

    __tablename__ = "hk_products"

    id = Column(Integer, primary_key=True, index=True)
    name = Column(String(64), nullable=False)
    description = Column(Text, nullable=True)
    # 基础每日收益率, 如 0.02 = 2%/日
    base_daily_rate = Column(Numeric(10, 6), nullable=False)
    # 产品周期(天). 计时以订单生效时间为准, 每满24小时为一日
    duration_days = Column(Integer, nullable=False)
    # 收益返还方式, 见 RETURN_METHODS
    return_method = Column(String(16), nullable=False, default="expiry")
    # 购买金额范围 (USDT)
    min_amount = Column(Numeric(18, 2), nullable=False)
    max_amount = Column(Numeric(18, 2), nullable=False)
    # 购买等级门槛: NULL=不限; 购买时按"生效前"等级校验, 两项同时设置须同时满足
    vip_level_req = Column(Integer, nullable=True)
    team_level_req = Column(Integer, nullable=True)
    status = Column(String(16), nullable=False, default="draft", index=True)
    created_at = Column(DateTime, default=utc_now)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)
