"""资金明细服务: 每次余额变动留痕 (Phase 6.2, 文档第八节可追溯).

与业务变动在同一事务内调用: 先完成原子增减, 再记录变动后余额.
只增不改, 旧记录永不覆盖.
"""
from __future__ import annotations

from decimal import Decimal

from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkAccount, HkBalanceLog

_BALANCE_COL = {"principal": HkAccount.principal_balance, "income": HkAccount.income_balance}
_PENDING_COL = {"principal": HkAccount.principal_pending, "income": HkAccount.income_pending}


async def log(
    db: AsyncSession,
    user_id: int,
    account: str,
    change_type: str,
    amount: Decimal,
    *,
    ref_type: str = "",
    ref_id: int | None = None,
) -> HkBalanceLog:
    """记录一笔变动 (amount 正=入账 负=出账), balance_after 取当前事务内最新余额."""
    balance = (
        await db.execute(
            select(_BALANCE_COL[account]).where(HkAccount.user_id == user_id)
        )
    ).scalar_one()
    entry = HkBalanceLog(
        user_id=user_id,
        account=account,
        change_type=change_type,
        amount=amount,
        balance_after=balance,
        ref_type=ref_type,
        ref_id=ref_id,
    )
    db.add(entry)
    await db.flush()
    return entry


async def list_logs(
    db: AsyncSession, user_id: int, account: str | None = None, limit: int = 200
) -> list[HkBalanceLog]:
    """我的资金明细, 最新在前."""
    q = select(HkBalanceLog).where(HkBalanceLog.user_id == user_id)
    if account:
        q = q.where(HkBalanceLog.account == account)
    result = await db.execute(q.order_by(desc(HkBalanceLog.id)).limit(limit))
    return list(result.scalars().all())
