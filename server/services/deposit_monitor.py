"""扫链监听服务: 轮询充值地址, 确认后自动入账 (类微信/支付宝自动到账).

- 只监听"已分配给用户"的地址
- (network, txid) 唯一约束保证不重复入账
- confirmations >= required 时入账本金账户, 状态 confirming -> credited
- 低于最小充值金额的记 unmatched, 走客服人工处理
- 链: tron=TronGrid, evm=Etherscan V2, bsc=公共 RPC eth_getLogs (游标持久化)
- 429 指数退避; 空闲地址池低于下限自动补足; 异常/停链/持续限流发邮件告警
"""
from __future__ import annotations

import asyncio
import logging
from decimal import Decimal

import httpx
from sqlalchemy import func, select

from config import config
from database import SessionLocal
from models.account import HkDepositAddress, HkDepositRecord, HkPlatformSetting
from services import (
    account_service,
    alert_service,
    auth_service,
    bscrpc,
    deposit_service,
    evmscan,
    trongrid,
)
from services.chat_ws import chat_ws
from services.deposit_service import NETWORKS

logger = logging.getLogger(__name__)

# 分级轮询: 活跃用户 (WS 在线或 30min 内有 API 活动) 每轮都扫, 不活跃每 10min 全量扫.
# 省链上 API 配额, 且活跃档可承受更快轮询间隔 (30s -> 15s).
POLL_INTERVAL_SEC = 15
ACTIVE_WINDOW_SEC = 1800
FULL_SCAN_EVERY = 40  # 15s x 40 = 10min 一次全量

# 429 退避状态: 连续限流次数 -> sleep 秒数 (30s..5min 封顶)
_throttle_hits = 0

# Etherscan 套餐不覆盖的 EVM 网络, 命中后停用本进程内扫描
_evm_disabled: set[str] = set()

# BSC 扫块: 首轮从最近 N 块开始; 每轮窗口上限 (BSC 3s/块, 2000 块 ≈ 100 分钟)
BSC_SEED_BLOCKS = 2000
BSC_MAX_WINDOW = 2000


def _throttle_sleep() -> float:
    return min(30 * (2 ** _throttle_hits), 300)


async def _on_throttle(network: str) -> None:
    global _throttle_hits
    _throttle_hits += 1
    logger.warning(
        "deposit_monitor throttled (%s, hits=%s), skip round",
        network,
        _throttle_hits,
    )
    if _throttle_hits == 5:
        await alert_service.alert(
            "deposit_throttle",
            "扫链持续限流",
            f"{network} 网络连续限流 {_throttle_hits} 轮, "
            "充值到账会延迟, 请检查 API 配额/节点。",
        )


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


async def _get_scan_cursor(db, network: str) -> int | None:
    row = (
        await db.execute(
            select(HkPlatformSetting).where(
                HkPlatformSetting.key == f"deposit_scan_block_{network}"
            )
        )
    ).scalar_one_or_none()
    return int(row.value) if row and row.value.isdigit() else None


async def _set_scan_cursor(db, network: str, block: int) -> None:
    key = f"deposit_scan_block_{network}"
    row = (
        await db.execute(
            select(HkPlatformSetting).where(HkPlatformSetting.key == key)
        )
    ).scalar_one_or_none()
    if row is None:
        db.add(HkPlatformSetting(key=key, value=str(block)))
    else:
        row.value = str(block)


async def _poll_network(
    db,
    tron_client,
    plain_client,
    network: str,
    active_ids: set[int],
    full_scan: bool,
) -> None:
    cfg = NETWORKS[network]
    chain = cfg["chain"]  # tron | evm | bsc
    if chain == "evm":
        if not evmscan.available():
            return  # 未配 Etherscan key: 跳过 EVM 网络 (TRC20 不受影响)
        if network in _evm_disabled:
            return  # 套餐不覆盖该链, 已停用

    result = await db.execute(
        select(HkDepositAddress).where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id.isnot(None),
        )
    )
    addresses = list(result.scalars().all())
    if not full_scan:
        # 分级轮询: 非全量轮只扫活跃用户地址 (离线用户的充值最多晚 10min 发现)
        addresses = [a for a in addresses if a.user_id in active_ids]
    if not addresses:
        return

    # ---- 最新块高 (BSC 顺带确定本轮扫描窗口) ----
    bsc_from = bsc_to = None
    try:
        if chain == "evm":
            latest = await evmscan.latest_block(plain_client, cfg["chain_id"])
        elif chain == "bsc":
            latest = await bscrpc.latest_block(plain_client)
            cursor = await _get_scan_cursor(db, network)
            bsc_from = (
                cursor + 1 if cursor else max(latest - BSC_SEED_BLOCKS, 0)
            )
            bsc_to = min(latest, bsc_from + BSC_MAX_WINDOW)
        else:
            latest = await trongrid.latest_block(tron_client)
    except evmscan.ChainUnsupported:
        _evm_disabled.add(network)
        logger.error(
            "evmscan chain unsupported (free plan), disabling %s monitor",
            network,
        )
        await alert_service.alert(
            f"deposit_chain_disabled_{network}",
            f"{network} 扫链已停用",
            "Etherscan 套餐不覆盖该链, 本进程内已停止扫描, "
            "该网络充值不会自动到账。",
        )
        return
    except (trongrid.RateLimited, evmscan.RateLimited, bscrpc.RateLimited):
        await _on_throttle(network)
        return
    except Exception as e:  # noqa: BLE001 节点故障不中断周期
        logger.warning("deposit_monitor latest_block %s failed: %s", network, e)
        return
    if latest is None:
        return

    required = cfg["confirmations_required"]
    min_deposit = Decimal(cfg["min_deposit"])

    for addr in addresses:
        try:
            if chain == "evm":
                txs = await evmscan.fetch_incoming(
                    plain_client, cfg["chain_id"], addr.address,
                    cfg["usdt_contract"], cfg["decimals"],
                )
            elif chain == "bsc":
                txs = await bscrpc.fetch_incoming(
                    plain_client, cfg["usdt_contract"], addr.address,
                    bsc_from, bsc_to, cfg["decimals"],
                )
            else:
                txs = await trongrid.fetch_incoming(
                    tron_client, addr.address, cfg["usdt_contract"]
                )
        except evmscan.ChainUnsupported:
            _evm_disabled.add(network)
            logger.error(
                "evmscan chain unsupported (free plan), disabling %s monitor",
                network,
            )
            await alert_service.alert(
                f"deposit_chain_disabled_{network}",
                f"{network} 扫链已停用",
                "Etherscan 套餐不覆盖该链, 本进程内已停止扫描, "
                "该网络充值不会自动到账。",
            )
            return
        except (trongrid.RateLimited, evmscan.RateLimited, bscrpc.RateLimited):
            await _on_throttle(network)
            return  # 本轮剩余地址跳过, 外层 sleep 退避
        except Exception as e:  # noqa: BLE001
            logger.warning("deposit_monitor poll %s failed: %s", addr.address, e)
            continue

        credited: list[HkDepositRecord] = []
        for tx in txs:
            tx["txid"] = tx["txid"].lower().removeprefix("0x")  # 与补单归一化同口径
            existing = await db.execute(
                select(HkDepositRecord).where(
                    HkDepositRecord.network == network,
                    HkDepositRecord.txid == tx["txid"],
                )
            )
            record = existing.scalar_one_or_none()
            if record is not None and record.status != "confirming":
                continue  # 已终态 (credited/unmatched), 不重复处理

            # 块高缺失: 先取已有记录, 否则单条补查 (仅新/确认中 tx)
            block_number = tx.get("block_number")
            if block_number is None:
                if record is not None and record.block_number:
                    block_number = record.block_number
                elif chain != "tron":
                    continue  # EVM/BSC 应带块高, 缺失跳过
                else:
                    try:
                        block_number = await trongrid.fetch_block_number(
                            tron_client, tx["txid"]
                        )
                    except trongrid.RateLimited:
                        await _on_throttle(network)
                        return
                    if block_number is None:
                        continue  # 链上未确认/查不到, 下轮再试

            confirmations = max(latest - block_number + 1, 0)
            if record is None:
                block_time = tx.get("block_time")
                if block_time is None and chain == "bsc":
                    try:  # BSC 日志不含时间戳, 建记录时单条补
                        block_time = await bscrpc.block_time(
                            plain_client, block_number
                        )
                    except Exception as e:  # noqa: BLE001
                        logger.warning("bsc block_time failed: %s", e)
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
                    block_number=block_number,
                    block_time=block_time,
                )
                # 低于最小充值金额: 不入账, 记 unmatched 人工处理
                if tx["amount"] < min_deposit:
                    record.status = "unmatched"
                db.add(record)
                await db.flush()
            else:
                record.confirmations = confirmations

            if (
                record.status == "confirming"
                and record.confirmations >= required
            ):
                if await account_service.credit_principal(db, record):
                    credited.append(record)

        await db.commit()
        # commit 之后通知, 防回滚假通知; 在线走 WS, 离线 APNs
        for rec in credited:
            await deposit_service.notify_credited(db, rec)

    # BSC: 全量轮全地址扫完才推进游标 (活跃轮只扫部分地址, 游标不动)
    if chain == "bsc" and bsc_to is not None and full_scan:
        await _set_scan_cursor(db, network, bsc_to)
        await db.commit()


async def run_forever() -> None:
    """后台轮询循环. 由 app lifespan 启动, 异常自恢复不退出."""
    global _throttle_hits
    logger.info(
        "deposit_monitor started, interval=%ss, full scan every %s rounds",
        POLL_INTERVAL_SEC,
        FULL_SCAN_EVERY,
    )
    cycle = 0
    async with trongrid.make_client() as tron_client, httpx.AsyncClient() as plain_client:
        while True:
            try:
                cycle += 1
                full_scan = cycle % FULL_SCAN_EVERY == 1
                active_ids = set(await chat_ws.online_user_ids())
                active_ids |= auth_service.recent_active_user_ids(ACTIVE_WINDOW_SEC)
                async with SessionLocal() as db:
                    for network in NETWORKS:
                        await _ensure_pool(db, network)
                        await _poll_network(
                            db, tron_client, plain_client, network,
                            active_ids, full_scan,
                        )
            except Exception as e:  # noqa: BLE001
                logger.exception("deposit_monitor cycle error: %s", e)
                await alert_service.alert(
                    "deposit_cycle_error",
                    "扫链周期异常",
                    f"deposit_monitor 周期异常: {e!r} (已自动恢复, 持续出现需排查)",
                )
            sleep_s = (
                _throttle_sleep() if _throttle_hits > 0 else POLL_INTERVAL_SEC
            )
            if _throttle_hits > 0:
                _throttle_hits = max(_throttle_hits - 1, 0)  # 每轮衰减恢复
            await asyncio.sleep(sleep_s)
