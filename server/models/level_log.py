"""等级变动日志 (审计/可追溯).

个人 VIP 与团队等级是动态计算的, 等级本身不落库; 本表在**等级可能变化的事件点**
(购买成功 / 订单到期结算) 记录当时的等级与统计依据, 供事后核查:
- 结算引擎异常时可对照日志还原"某时点用户等级是多少";
- 日志只增不改, 旧记录不被新状态覆盖.

注意: 同一事务内先完成业务变更再记录, 保证日志反映事件后的最新等级.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import Column, DateTime, ForeignKey, Integer, Numeric, String

from models.hk import HkBase, utc_now

# 等级类型: vip=个人VIP; team=团队等级
LEVEL_KINDS = ("vip", "team")

# 变动来源: purchase=购买成功; settle=订单到期结算
LEVEL_SOURCES = ("purchase", "settle")


class HkLevelLog(HkBase):
    """一条 = 某用户某类等级的一次变动 (与上一条记录等级不同才写入)."""

    __tablename__ = "hk_level_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    kind = Column(String(8), nullable=False, index=True)  # vip / team
    level = Column(Integer, nullable=False)  # 变动后的等级
    # 依据快照: VIP=有效持仓; team=团队有效持仓总额
    holding = Column(Numeric(18, 2), nullable=True)
    member_count = Column(Integer, nullable=True)  # 仅 team: 三代有效人数
    source = Column(String(16), nullable=False, default="")  # purchase / settle
    created_at = Column(DateTime, default=utc_now, index=True)
