"""充值服务: 地址分配 + 记录查询 (需求文档第六节).

充值网络配置见 NETWORKS; 首批仅 TRC20. 到账判定/确认数见 docs/充值模块设计方案.md.
"""
from __future__ import annotations

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkDepositAddress, HkDepositRecord
from models.hk import utc_now

# 网络配置: usdt_contract 为 TRC20-USDT 官方合约
NETWORKS: dict[str, dict] = {
    "trc20": {
        "name": "TRC20 (Tron)",
        "usdt_contract": "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
        "confirmations_required": 12,
        "min_deposit": "10",  # USDT, 设计文档第三节
    }
}

MIN_DEPOSIT_VIOLATION = "低于最小充值金额, 记录为 unmatched 待人工处理"


def get_network(network: str) -> dict:
    cfg = NETWORKS.get(network.lower())
    if cfg is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"不支持的网络: {network} (当前支持: {', '.join(NETWORKS)})",
        )
    return cfg


async def get_or_assign_address(
    db: AsyncSession, user_id: int, network: str
) -> HkDepositAddress:
    """查/分配用户在该网络的专属充值地址 (每人每网络固定一个)."""
    network = network.lower()
    get_network(network)

    result = await db.execute(
        select(HkDepositAddress).where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id == user_id,
        )
    )
    assigned = result.scalar_one_or_none()
    if assigned is not None:
        return assigned

    # 从空闲池取一个地址并标记分配 (sqlite 串行写; postgres 走行锁)
    result = await db.execute(
        select(HkDepositAddress)
        .where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id.is_(None),
        )
        .limit(1)
        .with_for_update()
    )
    free = result.scalar_one_or_none()
    if free is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="充值地址准备中, 请稍后重试或联系客服",
        )
    free.user_id = user_id
    free.assigned_at = utc_now()
    await db.commit()
    await db.refresh(free)
    return free


async def list_my_records(
    db: AsyncSession, user_id: int, limit: int = 50
) -> list[HkDepositRecord]:
    result = await db.execute(
        select(HkDepositRecord)
        .where(HkDepositRecord.user_id == user_id)
        .order_by(HkDepositRecord.id.desc())
        .limit(limit)
    )
    return list(result.scalars().all())
