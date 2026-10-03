"""扫链监听服务: TronGrid 轮询充值地址, 确认后自动入账 (类微信/支付宝自动到账).

- 只监听"已分配给用户"的地址
- (network, txid) 唯一约束保证不重复入账
- confirmations >= required 时入账本金账户, 状态 confirming -> credited
- 低于最小充值金额的记 unmatched, 走客服人工处理
"""
from __future__ import annotations

import asyncio
import logging
from datetime import datetime
from decimal import Decimal

import httpx
from sqlalchemy import select

from database import SessionLocal
from models.account import HkDepositAddress, HkDepositRecord
from models.hk import utc_now
from services import account_service
from services.deposit_service import NETWORKS

logger = logging.getLogger(__name__)

TRONGRID_BASE = "https://api.trongrid.io"
POLL_INTERVAL_SEC = 30
HTTP_TIMEOUT = 10.0


def _extract_txs(data: dict) -> list[dict]:
    """TronGrid trc20 交易列表 -> 归一化字段."""
    out = []
    for tx in data.get("data", []) or []:
        try:
            value = tx.get("value", "0")
            out.append(
                {
                    "txid": tx["transaction_id"],
                    "from": tx.get("from", ""),
                    "block_number": int(tx["block_number"]),
                    "amount": Decimal(value) / Decimal(10**6),  # USDT 6 位小数
                    "block_time": datetime.fromtimestamp(
                        tx["block_timestamp"] / 1000
                    ),
                }
            )
        except (KeyError, ValueError, TypeError):
            continue
    return out


async def _latest_block(client: httpx.AsyncClient) -> int | None:
    try:
        resp = await client.get(
            f"{TRONGRID_BASE}/walletsolidity/getnowblock",
            timeout=HTTP_TIMEOUT,
        )
        resp.raise_for_status()
        return int(resp.json()["block_header"]["raw_data"]["number"])
    except Exception as e:  # noqa: BLE001 轮询服务不中断
        logger.warning("deposit_monitor latest_block failed: %s", e)
        return None


async def _poll_network(db, client: httpx.AsyncClient, network: str) -> None:
    cfg = NETWORKS[network]
    result = await db.execute(
        select(HkDepositAddress).where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id.isnot(None),
        )
    )
    addresses = list(result.scalars().all())
    if not addresses:
        return

    latest = await _latest_block(client)
    if latest is None:
        return

    required = cfg["confirmations_required"]
    min_deposit = Decimal(cfg["min_deposit"])

    for addr in addresses:
        try:
            resp = await client.get(
                f"{TRONGRID_BASE}/v1/accounts/{addr.address}/transactions/trc20",
                params={
                    "contract_address": cfg["usdt_contract"],
                    "only_confirmed": "true",
                    "limit": 50,
                },
                timeout=HTTP_TIMEOUT,
            )
            resp.raise_for_status()
        except Exception as e:  # noqa: BLE001
            logger.warning("deposit_monitor poll %s failed: %s", addr.address, e)
            continue

        for tx in _extract_txs(resp.json()):
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
    logger.info("deposit_monitor started, interval=%ss", POLL_INTERVAL_SEC)
    async with httpx.AsyncClient() as client:
        while True:
            try:
                async with SessionLocal() as db:
                    for network in NETWORKS:
                        await _poll_network(db, client, network)
            except Exception as e:  # noqa: BLE001
                logger.exception("deposit_monitor cycle error: %s", e)
            await asyncio.sleep(POLL_INTERVAL_SEC)
