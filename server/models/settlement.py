"""结算与佣金流水 (需求文档第八节: 唯一流水、可追溯).

- HkSettlementRecord: 订单每期收益结算流水, (order_id, period_no) 唯一 → 幂等, 重试不重复入账
- HkCommissionRecord: 每期佣金流水, (settlement_id, receiver_id) 唯一;
  留存应结算时点的接收人团队等级、代数与比例 (文档: 结算依据不得无记录)
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
)

from models.hk import HkBase, utc_now


class HkSettlementRecord(HkBase):
    """订单某期收益结算流水."""

    __tablename__ = "hk_settlement_records"
    __table_args__ = (
        UniqueConstraint("order_id", "period_no", name="uq_stl_order_period"),
    )

    id = Column(Integer, primary_key=True, index=True)
    order_id = Column(Integer, ForeignKey("hk_orders.id"), nullable=False, index=True)
    user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    period_no = Column(Integer, nullable=False)  # 第几期, 从 1 开始
    period_days = Column(Numeric(10, 6), nullable=False)  # 本期天数 (小时节奏可为分数, 如 1/24)
    # 本期收益 (已按文档第五节截断至 2 位小数)
    income_amount = Column(Numeric(18, 2), nullable=False)
    # 最后一期同时记录返还本金金额 (0 表示未返)
    principal_amount = Column(Numeric(18, 2), nullable=False, default=0)
    # 应结算时点 = 生效时间 + 周期×期数 (文档第八节: 结算依据须留痕)
    due_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)  # 实际入账时间


class HkCommissionRecord(HkBase):
    """每期佣金流水 (平台额外支付, 不扣减购买用户收益)."""

    __tablename__ = "hk_commission_records"
    __table_args__ = (
        UniqueConstraint("settlement_id", "receiver_id", name="uq_comm_stl_receiver"),
    )

    id = Column(Integer, primary_key=True, index=True)
    settlement_id = Column(
        Integer, ForeignKey("hk_settlement_records.id"), nullable=False, index=True
    )
    order_id = Column(Integer, ForeignKey("hk_orders.id"), nullable=False, index=True)
    buyer_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    receiver_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    gen = Column(Integer, nullable=False)  # 代数: 1/2/3
    receiver_team_level = Column(Integer, nullable=False)  # 应结算时点接收人团队等级
    rate = Column(Numeric(10, 6), nullable=False)  # 适用比例
    base_amount = Column(Numeric(18, 2), nullable=False, default=0)  # 佣金基数 = 该期收益
    amount = Column(Numeric(18, 2), nullable=False)  # 已截断 2 位小数
    due_at = Column(DateTime, nullable=True)  # 应结算时点 (同关联结算流水)
    status = Column(String(16), nullable=False, default="settled")  # settled=已入账(终态)
    created_at = Column(DateTime, default=utc_now)  # 实际入账时间
