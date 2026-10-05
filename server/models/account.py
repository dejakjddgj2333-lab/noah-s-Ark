"""资金账户 + 充值体系 (需求文档第六节).

- HkAccount: 本金账户/收益账户双账户余额 (持仓本金不属可提现余额, 后续持仓模块接入)
- HkDepositAddress: 平台地址池, 每个用户每网络分配一个固定充值地址
- HkDepositRecord: 充值流水, (network, txid) 唯一防重复入账
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from sqlalchemy import (
    Column,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    Numeric,
    String,
    UniqueConstraint,
)

from models.hk import HkBase, utc_now

# 充值记录状态: confirming=确认中; credited=已入账; unmatched=异常(错链/错币, 人工处理)
DEPOSIT_STATUSES = ("confirming", "credited", "unmatched")

# 资金账户: principal=本金账户; income=收益账户
ACCOUNT_TYPES = ("principal", "income")

# 资金明细变动类型 (余额方向由 amount 正负表达)
BALANCE_CHANGE_TYPES = (
    "deposit_credited",   # 充值入账 → 本金
    "purchase",           # 购买产品扣款 ← 本金
    "income_settled",     # 产品收益结算 → 收益
    "commission",         # 邀请佣金 → 收益
    "principal_returned", # 到期返本 → 本金
    "withdraw_request",   # 提现申请占用 ← 对应账户 (金额+费用)
    "withdraw_reject",    # 提现拒绝退回 → 对应账户
    "withdraw_approve",   # 提现审核通过打款 (占用转实付)
)

# 提现状态: pending=待审核(占用中); approved=已打款; rejected=已拒绝(已退回)
WITHDRAW_STATUSES = ("pending", "approved", "rejected")


class HkAccount(HkBase):
    """双资金账户. 本金账户: 充值+到期本金; 收益账户: 产品收益+邀请佣金."""

    __tablename__ = "hk_accounts"

    user_id = Column(Integer, ForeignKey("hk_users.id"), primary_key=True)
    # 可用余额
    principal_balance = Column(Numeric(18, 2), nullable=False, default=0)
    income_balance = Column(Numeric(18, 2), nullable=False, default=0)
    # 提现处理中金额 (第六节: 申请后从可用余额转出, 分别列示)
    principal_pending = Column(Numeric(18, 2), nullable=False, default=0)
    income_pending = Column(Numeric(18, 2), nullable=False, default=0)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkDepositAddress(HkBase):
    """平台充值地址池.

    ⚠️ private_key 仅开发环境明文存放, 生产必须改为 KMS/硬件钱包托管.
    """

    __tablename__ = "hk_deposit_addresses"
    __table_args__ = (
        UniqueConstraint("network", "address", name="uq_dep_addr"),
    )

    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(16), nullable=False, index=True)  # 如 trc20
    address = Column(String(64), nullable=False)
    private_key = Column(String(128), nullable=True)  # dev-only, 见模块 docstring
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=True, index=True
    )
    assigned_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)


class HkDepositRecord(HkBase):
    """充值流水. txid 维度唯一, 重试/重复回调不得重复入账 (第八节技术要求)."""

    __tablename__ = "hk_deposit_records"
    __table_args__ = (
        UniqueConstraint("network", "txid", name="uq_dep_record"),
    )

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    network = Column(String(16), nullable=False)
    address = Column(String(64), nullable=False)  # 充值到账地址
    txid = Column(String(80), nullable=False)
    from_address = Column(String(64), nullable=True)
    # USDT 原值入账, 6 位小数 (文档: 充值不设截断, 提现精度另行定义)
    amount = Column(Numeric(18, 6), nullable=False)
    confirmations = Column(Integer, nullable=False, default=0)
    required_confirmations = Column(Integer, nullable=False, default=12)
    status = Column(String(16), nullable=False, default="confirming", index=True)
    block_number = Column(Integer, nullable=True)
    block_time = Column(DateTime, nullable=True)
    credited_at = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=utc_now)


class HkBalanceLog(HkBase):
    """资金明细流水: 每一次余额变动留痕 (来源分类 + 关联单据 + 变动后余额), 只增不改."""

    __tablename__ = "hk_balance_logs"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    account = Column(String(16), nullable=False, index=True)  # principal / income
    change_type = Column(String(24), nullable=False, index=True)
    amount = Column(Numeric(18, 2), nullable=False)  # 正=入账 负=出账
    balance_after = Column(Numeric(18, 2), nullable=False)  # 变动后该账户余额
    ref_type = Column(String(24), nullable=False, default="")  # order/settlement/commission/deposit/withdrawal
    ref_id = Column(Integer, nullable=True)  # 关联单据 id
    created_at = Column(DateTime, default=utc_now, index=True)


class HkWithdrawal(HkBase):
    """提现申请. 费用从申请金额内扣除: 申请即占用申请金额转处理中; 拒绝全额退回; 通过后线下打款."""

    __tablename__ = "hk_withdrawals"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(
        Integer, ForeignKey("hk_users.id"), nullable=False, index=True
    )
    account = Column(String(16), nullable=False)  # principal / income
    network = Column(String(16), nullable=False)  # 如 trc20
    address = Column(String(64), nullable=False)
    amount = Column(Numeric(18, 2), nullable=False)  # 申请金额 (占用/扣款口径, 费用从其中扣除)
    service_fee = Column(Numeric(18, 2), nullable=False, default=0)  # 3% 服务费(仅收益账户)
    network_fee = Column(Numeric(18, 2), nullable=False, default=0)  # 网络费(两账户都收)
    arrive_amount = Column(Numeric(18, 2), nullable=False)  # 实际到账 = amount − 服务费 − 网络费
    status = Column(String(16), nullable=False, default="pending", index=True)
    txid = Column(String(80), nullable=True)  # 打款链上交易号
    remark = Column(String(256), nullable=True)
    processed_by = Column(String(32), nullable=True)  # 审核操作人 (后台账号)
    idempotency_key = Column(String(64), nullable=True)  # 幂等键 (唯一索引见 __table_args__)
    created_at = Column(DateTime, default=utc_now)
    processed_at = Column(DateTime, nullable=True)

    __table_args__ = (
        Index("uq_hk_withdrawals_idem", "idempotency_key", unique=True),
    )


class HkAdminActionLog(HkBase):
    """后台关键操作审计日志: 谁在何时对什么做了什么 (只增不改)."""

    __tablename__ = "hk_admin_action_logs"

    id = Column(Integer, primary_key=True, index=True)
    admin_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    admin_username = Column(String(32), nullable=False)
    action = Column(String(32), nullable=False)  # withdraw_approve / withdraw_reject / product_create / product_update / product_publish / product_offline
    target_type = Column(String(32), nullable=False)  # withdrawal / product
    target_id = Column(Integer, nullable=False)
    detail = Column(String(512), nullable=True)  # 关键前后值摘要 (如拒绝原因/txid)
    created_at = Column(DateTime, default=utc_now, index=True)


class HkPlatformSetting(HkBase):
    """平台参数 KV 表 (后台可改): 归集主钱包 sweep_target_<network> /
    归集阈值 sweep_threshold_<network> 等."""

    __tablename__ = "hk_platform_settings"

    id = Column(Integer, primary_key=True, index=True)
    key = Column(String(64), unique=True, nullable=False, index=True)
    value = Column(String(256), nullable=False, default="")
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)


class HkSweepRecord(HkBase):
    """资金归集记录: 池地址 → 主钱包. gas_needed=地址缺原生币待手动补."""

    __tablename__ = "hk_sweep_records"

    id = Column(Integer, primary_key=True, index=True)
    network = Column(String(16), nullable=False, index=True)
    from_address = Column(String(64), nullable=False)
    to_address = Column(String(64), nullable=False)
    amount = Column(Numeric(18, 6), nullable=False)  # USDT
    txid = Column(String(80), nullable=True)
    status = Column(String(16), nullable=False, default="success", index=True)  # success/gas_needed/failed
    error = Column(String(256), nullable=True)
    operator_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False)
    operator_username = Column(String(32), nullable=False)
    created_at = Column(DateTime, default=utc_now, index=True)
