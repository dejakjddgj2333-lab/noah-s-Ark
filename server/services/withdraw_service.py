"""提现服务 (Phase 6.3-6.6, 需求文档第六节/第九节).

规则 (文档已确认部分):
- 收益账户: 单笔 ≥50 USDT, 收 3% 平台服务费 + 网络费;
- 本金账户: 无门槛、无服务费, 只收网络费;
- 费用从申请金额内扣除: 实际到账 = 申请金额 - 服务费 - 网络费,
  账户占用 = 申请金额 (不额外重复锁定手续费); 实际到账必须为正数;
- 费用在提交时一次算定, 确认后不得追加扣费 (入账只按申请时算出的费用);
- 申请即占用: 申请金额从可用余额转处理中;
- 拒绝/失败: 全额退回申请金额; 审核通过: 处理中金额转出, 平台线下打款;
- 地址按网络格式校验 (TRC20 = base58check; EVM = 0x+40hex).

⚠️ Phase 0.6 未拍板: 网络费数值暂按配置表固定值, 费用报价来源/有效期待拍板后调整.
"""
from __future__ import annotations

from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import func, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from models.account import HkAccount, HkWithdrawal
from services.account_service import get_or_create_account
from services.balance_log_service import log as log_balance
from services.team_service import truncate_2dp

# 各网络提现参数. network_fee 数值为占位默认值, 待 Phase 0.6 拍板
WITHDRAW_NETWORKS: dict[str, dict[str, object]] = {
    "trc20": {"label": "TRC20 (波场)", "network_fee": Decimal("1")},
    "erc20": {"label": "ERC20 (以太坊)", "network_fee": Decimal("5")},
    "bep20": {"label": "BEP20 (BNB Chain)", "network_fee": Decimal("0.3")},
    "arbitrum": {"label": "Arbitrum", "network_fee": Decimal("0.5")},
}

_EVM_NETWORKS = ("erc20", "bep20", "arbitrum")

# 收益账户提现规则 (文档第六节)
INCOME_MIN_AMOUNT = Decimal("50")
INCOME_SERVICE_RATE = Decimal("0.03")


def list_networks() -> list[dict]:
    """支持提现的网络清单 (App 提现页渲染用)."""
    return [
        {
            "network": net,
            "label": str(cfg["label"]),
            "network_fee": cfg["network_fee"],
            "income_min_amount": INCOME_MIN_AMOUNT,
            "income_service_rate": INCOME_SERVICE_RATE,
        }
        for net, cfg in WITHDRAW_NETWORKS.items()
    ]


def _validate_address(network: str, address: str) -> str:
    """按网络格式校验并规范化地址 (TRC20: base58check; EVM: 0x+40hex)."""
    address = address.strip()
    if network == "trc20":
        try:
            from tronpy.keys import to_base58check_address

            return to_base58check_address(address)
        except Exception:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, "TRC20 地址格式无效"
            )
    if network in _EVM_NETWORKS:
        import re

        if re.fullmatch(r"0[xX][0-9a-fA-F]{40}", address):
            return address.lower()
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "EVM 地址格式无效 (0x 开头 42 位)"
        )
    raise HTTPException(status.HTTP_400_BAD_REQUEST, f"暂不支持网络 {network}")


def quote(account: str, amount: Decimal, network: str) -> dict:
    """费用报价 (提交前展示; 提交时服务端重算, 以服务端为准)."""
    if account not in ("principal", "income"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "账户类型无效")
    if network not in WITHDRAW_NETWORKS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"暂不支持网络 {network}")
    amount = Decimal(amount)
    if not amount.is_finite() or amount <= 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "提现金额必须为正数")
    if amount != amount.quantize(Decimal("0.01")):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "提现金额最多两位小数")
    if config.withdraw_max_per_request > 0 and amount > config.withdraw_max_per_request:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"单笔提现不能超过 {config.withdraw_max_per_request} USDT",
        )
    if account == "income" and amount < INCOME_MIN_AMOUNT:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, "收益账户提现单笔至少 50 USDT"
        )
    service_fee = (
        truncate_2dp(amount * INCOME_SERVICE_RATE) if account == "income" else Decimal(0)
    )
    network_fee = Decimal(str(WITHDRAW_NETWORKS[network]["network_fee"]))
    # 费用从申请金额内扣除 (文档第六节): 到账 = 金额 - 服务费 - 网络费, 必须为正数
    arrive_amount = amount - service_fee - network_fee
    if arrive_amount <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "申请金额不足以覆盖费用, 实际到账须为正数",
        )
    return {
        "account": account,
        "network": network,
        "amount": amount,
        "service_fee": service_fee,
        "network_fee": network_fee,
        "total_deduction": amount,  # 账户占用 = 申请金额, 不重复锁定手续费
        "arrive_amount": arrive_amount,
    }


async def create_request(
    db: AsyncSession, user_id: int, account: str, network: str,
    address: str, amount: Decimal, idempotency_key: str | None = None,
) -> HkWithdrawal:
    """创建提现申请: 服务端重算报价 + 限额校验 + 原子占用余额.

    idempotency_key: 可选幂等键 (客户端生成, 同键重复提交返回首次申请,
    网络重试/双击不产生重复扣款).
    """
    if idempotency_key:
        existing = (
            await db.execute(
                select(HkWithdrawal).where(
                    HkWithdrawal.idempotency_key == idempotency_key
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            return existing
    q = quote(account, amount, network)
    if config.withdraw_daily_limit > 0:
        from datetime import datetime, timezone

        day_start = datetime.now(timezone.utc).replace(
            hour=0, minute=0, second=0, microsecond=0
        )
        used = (
            await db.execute(
                select(func.coalesce(func.sum(HkWithdrawal.amount), 0)).where(
                    HkWithdrawal.user_id == user_id,
                    HkWithdrawal.status.in_(("pending", "approved")),
                    HkWithdrawal.created_at >= day_start,
                )
            )
        ).scalar_one()
        if Decimal(used) + q["amount"] > config.withdraw_daily_limit:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST,
                f"超出单日提现上限 {config.withdraw_daily_limit} USDT",
            )
    address = _validate_address(network, address)
    try:
        await get_or_create_account(db, user_id)
    except IntegrityError:
        await db.rollback()
        await get_or_create_account(db, user_id)

    balance_col = (
        HkAccount.principal_balance if account == "principal" else HkAccount.income_balance
    )
    pending_col = (
        HkAccount.principal_pending if account == "principal" else HkAccount.income_pending
    )
    res = await db.execute(
        update(HkAccount)
        .where(HkAccount.user_id == user_id, balance_col >= q["total_deduction"])
        .values(
            **{
                balance_col.name: balance_col - q["total_deduction"],
                pending_col.name: pending_col + q["amount"],
            }
        )
    )
    await db.flush()
    if res.rowcount != 1:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "账户可用余额不足")
    w = HkWithdrawal(
        user_id=user_id,
        account=account,
        network=network,
        address=address,
        amount=q["amount"],
        service_fee=q["service_fee"],
        network_fee=q["network_fee"],
        arrive_amount=q["arrive_amount"],
        idempotency_key=idempotency_key,
    )
    db.add(w)
    try:
        await db.flush()
    except IntegrityError:
        # 幂等键并发撞键: 撤销本次占用, 返回已存在的申请 (仅入账一次)
        await db.rollback()
        existing = (
            await db.execute(
                select(HkWithdrawal).where(
                    HkWithdrawal.idempotency_key == idempotency_key
                )
            )
        ).scalar_one()
        return existing
    # 资金明细: 申请占用 (金额+费用出账)
    await log_balance(
        db, user_id, account, "withdraw_request", -q["total_deduction"],
        ref_type="withdrawal", ref_id=w.id,
    )
    return w


async def approve(db: AsyncSession, w: HkWithdrawal, txid: str | None) -> None:
    """审核通过: 处理中金额转出 (余额已在申请时扣除), 平台线下打款后登记 txid."""
    if w.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "该提现申请已处理")
    pending_col = (
        HkAccount.principal_pending if w.account == "principal" else HkAccount.income_pending
    )
    await db.execute(
        update(HkAccount)
        .where(HkAccount.user_id == w.user_id)
        .values(**{pending_col.name: pending_col - Decimal(w.amount)})
    )
    w.status = "approved"
    w.txid = txid
    from models.hk import utc_now

    w.processed_at = utc_now()
    await db.flush()
    await log_balance(
        db, w.user_id, w.account, "withdraw_approve", -Decimal(w.amount),
        ref_type="withdrawal", ref_id=w.id,
    )


async def reject(db: AsyncSession, w: HkWithdrawal, remark: str | None) -> None:
    """拒绝: 退回申请金额 (费用从金额内扣, 未额外占用), 释放处理中."""
    if w.status != "pending":
        raise HTTPException(status.HTTP_409_CONFLICT, "该提现申请已处理")
    balance_col = (
        HkAccount.principal_balance if w.account == "principal" else HkAccount.income_balance
    )
    pending_col = (
        HkAccount.principal_pending if w.account == "principal" else HkAccount.income_pending
    )
    refund = Decimal(w.amount)
    await db.execute(
        update(HkAccount)
        .where(HkAccount.user_id == w.user_id)
        .values(
            **{
                balance_col.name: balance_col + refund,
                pending_col.name: pending_col - Decimal(w.amount),
            }
        )
    )
    w.status = "rejected"
    w.remark = remark
    from models.hk import utc_now

    w.processed_at = utc_now()
    await db.flush()
    await log_balance(
        db, w.user_id, w.account, "withdraw_reject", refund,
        ref_type="withdrawal", ref_id=w.id,
    )


async def get(db: AsyncSession, withdrawal_id: int) -> HkWithdrawal:
    w = (
        await db.execute(
            select(HkWithdrawal).where(HkWithdrawal.id == withdrawal_id)
        )
    ).scalar_one_or_none()
    if w is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "提现申请不存在")
    return w


async def list_mine(db: AsyncSession, user_id: int) -> list[HkWithdrawal]:
    from sqlalchemy import desc

    result = await db.execute(
        select(HkWithdrawal)
        .where(HkWithdrawal.user_id == user_id)
        .order_by(desc(HkWithdrawal.id))
        .limit(200)
    )
    return list(result.scalars().all())
