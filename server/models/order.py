"""购买订单. Phase 1 仅承载"成功购买记录"供补绑全层级检查; 结算字段 Phase 2 起扩展."""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, DateTime, ForeignKey, Index, Integer, Numeric, String

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

    # ---- 下单瞬间的产品/资格快照 (Phase 2.5: 订单留存, 之后改产品不影响存量订单) ----
    product_name = Column(String(64), nullable=False, default="")
    base_daily_rate = Column(Numeric(10, 6), nullable=False, default=0)
    duration_days = Column(Integer, nullable=False, default=0)
    return_method = Column(String(16), nullable=False, default="expiry")
    # 购买时适用 VIP 与锁定加成 (Phase 3 等级体系落地后由等级服务填充)
    vip_level = Column(Integer, nullable=True)
    lock_bonus_rate = Column(Numeric(10, 6), nullable=True)
    # 购买时适用团队等级 (文档第八节: 资格校验依据随订单留存)
    team_level = Column(Integer, nullable=True)
    # 资格校验依据的规则版本号
    rule_version = Column(String(16), nullable=False, default="v0.7")
    # 到期时间 = 生效时间 + 周期天数 (计时以订单生效时间为准, 每满24小时为一日)
    expires_at = Column(DateTime, nullable=True)
    # 结算进度 (Phase 5 结算引擎): 已结算期数 / 下期应结算时点
    settled_periods = Column(Integer, nullable=False, default=0)
    next_settle_at = Column(DateTime, nullable=True, index=True)
    # 幂等键 (2026-10-06): 双击/超时重试/脚本重放只扣一次款 (唯一索引见 __table_args__)
    idempotency_key = Column(String(64), nullable=True)

    __table_args__ = (
        # 幂等键按用户隔离: 同用户同键只生成一单, 跨用户互不影响
        Index("uq_hk_orders_user_idem", "user_id", "idempotency_key", unique=True),
    )

    @property
    def actual_daily_rate(self) -> Decimal | None:
        """实际每日收益率 = 基础每日收益率 × (1 + 锁定VIP加成). 结算引擎(Phase 5)按此计算."""
        if self.lock_bonus_rate is None:
            return None
        return Decimal(self.base_daily_rate) * (
            1 + Decimal(self.lock_bonus_rate)
        )
