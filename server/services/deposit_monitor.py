"""扫链监听服务: TronGrid 轮询充值地址, 确认后自动入账 (类微信/支付宝自动到账).

- 只监听"已分配给用户"的地址
- (network, txid) 唯一约束保证不重复入账
- confirmations >= required 时入账本金账户, 状态 confirming -> credited
- 低于最小充值金额的记 unmatched, 走客服人工处理
- TronGrid 429 指数退避; 空闲地址池低于下限自动补足
"""
from __future__ import annotations

import asyncio
import logging
from decimal import Decimal

from sqlalchemy import func, select

from config import config
from database import SessionLocal
from models.account import HkDepositAddress, HkDepositRecord
from services import account_service, evmscan, trongrid
from services.deposit_service import NETWORKS

logger = logging.getLogger(__name__)

POLL_INTERVAL_SEC = 30

# 429 退避状态: 连续限流次数 -> sleep 秒数 (30s..5min 封顶)
_throttle_hits = 0


def _throttle_sleep() -> float:
    return min(30 * (2 ** _throttle_hits), 300)


async def _ensure_pool(db, network: str) -> None:
    """空闲地址低于下限自动补足 (与 admin generate 同逻辑, 明文私钥为既有设计)."""
    free = await db.scalar(
        select(func.count())
        .select_from(HkDepositAddress)
        .where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id.is_(None),
        )
    )
    if (free or 0) >= config.deposit_pool_min:
        return
    count = config.deposit_pool_target - (free or 0)
    logger.warning(
        "deposit pool low (%s free), generating %s", free, count
    )
    from scripts.keygen import generate_addresses

    created = await generate_addresses(network, count)
    logger.info("deposit pool replenished: +%s %s addresses", created, network)


async def _poll_network(db, client, network: str) -> None:
    global _throttle_hits
    cfg = NETWORKS[network]
    is_evm = cfg["chain"] == "evm"
    if is_evm and not evmscan.available():
        return  # 未配 Etherscan key: 跳过 EVM 网络 (TRC20 不受影响)

    result = await db.execute(
        select(HkDepositAddress).where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id.isnot(None),
        )
    )
    addresses = list(result.scalars().all())
    if not addresses:
        return

    if is_evm:
        latest = await evmscan.latest_block(client, cfg["chain_id"])
    else:
        latest = await trongrid.latest_block(client)
    if latest is None:
        return

    required = cfg["confirmations_required"]
    min_deposit = Decimal(cfg["min_deposit"])

    for addr in addresses:
        try:
            if is_evm:
                txs = await evmscan.fetch_incoming(
                    client, cfg["chain_id"], addr.address,
                    cfg["usdt_contract"], cfg["decimals"],
                )
            else:
                txs = await trongrid.fetch_incoming(
                    client, addr.address, cfg["usdt_contract"]
                )
        except (trongrid.RateLimited, evmscan.RateLimited):
            _throttle_hits += 1
            logger.warning(
                "deposit_monitor throttled (hits=%s), skip round",
                _throttle_hits,
            )
            return  # 本轮剩余地址跳过, 外层 sleep 退避
        except Exception as e:  # noqa: BLE001
            logger.warning("deposit_monitor poll %s failed: %s", addr.address, e)
            continue

        for tx in txs:
            tx["txid"] = tx["txid"].lower().removeprefix("0x")  # 与补单归一化同口径
            confirmations = max(latest - tx["block_number"] + 1, 0)
            existing = await db.execute(
                select(HkDepositRecord).where(
                    HkDepositRecord.network == network,
                    HkDepositRecord.txid == tx["txid"],
                )
            )
            record = existing.scalar_one_or_none()
            if record is None:
                record = HkDepositRecord(
                    user_id=addr.user_id,
                    network=network,
                    address=addr.address,
                    txid=tx["txid"],
                    from_address=tx["from"],
                    amount=tx["amount"],
                    confirmations=confirmations,
                    required_confirmations=required,
                    status="confirming",
                    block_number=tx["block_number"],
                    block_time=tx["block_time"],
                )
                # 低于最小充值金额: 不入账, 记 unmatched 人工处理
                if tx["amount"] < min_deposit:
                    record.status = "unmatched"
                db.add(record)
                await db.flush()
            elif record.status == "confirming":
                record.confirmations = confirmations

            if (
                record.status == "confirming"
                and record.confirmations >= required
            ):
                await account_service.credit_principal(db, record)

        await db.commit()


async def run_forever() -> None:
    """后台轮询循环. 由 app lifespan 启动, 异常自恢复不退出."""
    global _throttle_hits
    logger.info("deposit_monitor started, interval=%ss", POLL_INTERVAL_SEC)
    async with trongrid.make_client() as client:
        while True:
            try:
                async with SessionLocal() as db:
                    for network in NETWORKS:
                        await _ensure_pool(db, network)
                        await _poll_network(db, client, network)
            except Exception as e:  # noqa: BLE001
                logger.exception("deposit_monitor cycle error: %s", e)
            sleep_s = (
                _throttle_sleep() if _throttle_hits > 0 else POLL_INTERVAL_SEC
            )
            if _throttle_hits > 0:
                _throttle_hits = max(_throttle_hits - 1, 0)  # 每轮衰减恢复
            await asyncio.sleep(sleep_s)
