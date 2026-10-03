"""资金账户服务: 开户与入账 (幂等, 第八节技术要求)."""
from __future__ import annotations

from decimal import Decimal

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkAccount, HkDepositRecord  # noqa: F401 注册元数据
from models.hk import utc_now
from services import balance_log_service


async def get_or_create_account(db: AsyncSession, user_id: int) -> HkAccount:
    result = await db.execute(
        select(HkAccount).where(HkAccount.user_id == user_id)
    )
    account = result.scalar_one_or_none()
    if account is not None:
        return account
    account = HkAccount(user_id=user_id)
    db.add(account)
    await db.flush()
    return account


async def credit_principal(
    db: AsyncSession, record: HkDepositRecord
) -> bool:
    """按充值流水给本金账户入账. 仅 confirming -> credited 一次有效, 重复调用幂等.

    必须与流水状态变更在同一事务内调用, 由调用方 commit.
    """
    if record.status != "confirming":
        return False
    account = await get_or_create_account(db, record.user_id)
    account.principal_balance = Decimal(account.principal_balance) + Decimal(
        record.amount
    )
    record.status = "credited"
    record.credited_at = utc_now()
    await db.flush()
    # 资金明细: 充值入账 → 本金
    await balance_log_service.log(
        db, record.user_id, "principal", "deposit_credited", Decimal(record.amount),
        ref_type="deposit", ref_id=record.id,
    )
    return True
