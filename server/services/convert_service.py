"""收益→本金转化服务 (2026-10-06 拍板).

规则 (与提现同口径防绕过):
- 单笔 ≥ 配置下限 (默认 50 USDT, 与收益提现门槛一致);
- 收服务费 = 转化金额 × 费率 (默认 3%, 从转化金额内扣除, 截断 2 位小数);
- 内部转化不走链, 不收网络费;
- 到账本金 = 转化金额 − 服务费, 必须为正数;
- 出账用条件原子 UPDATE 防并发超扣; 入账同事务, 要么全成要么全滚;
- 幂等键防网络重试/重复点击: 同用户同键只扣一次, 重试返回首次结果;
- 单向: 只有收益→本金, 不存在本金→收益.

这样收益想转本金买产品, 3% 服务费照样留下, 不会绕过收益提现收费.
"""
from __future__ import annotations

from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkAccount, HkConvertRecord
from services import param_service
from services.account_service import get_or_create_account
from services.balance_log_service import log as log_balance
from services.team_service import truncate_2dp


def quote(amount: Decimal) -> dict:
    """转化报价: 校验金额, 算出服务费与实际到账.

    费率/下限走 param_service (后台参数配置可改, 即时生效), env 仅为默认值.
    """
    convert_min = Decimal(str(param_service.get("income_convert_min")))
    convert_rate = Decimal(str(param_service.get("income_convert_rate")))
    amount = Decimal(amount)
    if not amount.is_finite() or amount <= 0:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "转化金额必须为正数")
    if amount != amount.quantize(Decimal("0.01")):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "转化金额最多两位小数")
    if amount < convert_min:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            f"收益转化单笔至少 {convert_min} USDT",
        )
    service_fee = truncate_2dp(amount * convert_rate)
    arrive_amount = amount - service_fee
    if arrive_amount <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            "转化金额不足以覆盖服务费, 实际到账须为正数",
        )
    return {
        "amount": amount,
        "service_fee": service_fee,
        "rate": convert_rate,
        "min_amount": convert_min,
        "arrive_amount": arrive_amount,
    }


async def convert(
    db: AsyncSession, user_id: int, amount: Decimal,
    idempotency_key: str | None = None,
) -> dict:
    """执行转化: 收益账户扣全额 → 本金账户入 (金额−服务费). 调用方 commit.

    idempotency_key: 可选幂等键 (客户端生成), 网络超时重试/重复点击
    不产生第二次扣款, 直接返回首次转化结果.
    """
    if idempotency_key:
        existing = (
            await db.execute(
                select(HkConvertRecord).where(
                    HkConvertRecord.user_id == user_id,
                    HkConvertRecord.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one_or_none()
        if existing is not None:
            return _out(existing)
    q = quote(amount)
    try:
        await get_or_create_account(db, user_id)
    except IntegrityError:
        await db.rollback()
        await get_or_create_account(db, user_id)

    # 原子扣收益: 余额不足则影响行数为 0, 防并发超扣
    res = await db.execute(
        update(HkAccount)
        .where(
            HkAccount.user_id == user_id,
            HkAccount.income_balance >= q["amount"],
        )
        .values(
            income_balance=HkAccount.income_balance - q["amount"],
            principal_balance=HkAccount.principal_balance + q["arrive_amount"],
        )
    )
    await db.flush()
    if res.rowcount != 1:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "收益账户可用余额不足")

    record = HkConvertRecord(
        user_id=user_id,
        amount=q["amount"],
        service_fee=q["service_fee"],
        arrive_amount=q["arrive_amount"],
        idempotency_key=idempotency_key,
    )
    db.add(record)
    try:
        await db.flush()
    except IntegrityError:
        # 并发同键: 撤销本次扣款, 返回首次转化 (只扣一次)
        await db.rollback()
        existing = (
            await db.execute(
                select(HkConvertRecord).where(
                    HkConvertRecord.user_id == user_id,
                    HkConvertRecord.idempotency_key == idempotency_key,
                )
            )
        ).scalar_one()
        return _out(existing)

    # 资金明细: 收益出 / 本金入 (费用不另列, 与提现口径一致: 到账=金额−费用)
    await log_balance(
        db, user_id, "income", "convert_out", -q["amount"], ref_type="convert",
    )
    await log_balance(
        db, user_id, "principal", "convert_in", q["arrive_amount"],
        ref_type="convert",
    )
    return _out(record)


def _out(record: HkConvertRecord) -> dict:
    return {
        "id": record.id,
        "amount": record.amount,
        "service_fee": record.service_fee,
        "arrive_amount": record.arrive_amount,
        "created_at": record.created_at,
    }
