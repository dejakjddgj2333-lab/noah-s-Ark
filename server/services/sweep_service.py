"""资金归集: 池地址 USDT → 平台主钱包 (管理员手动触发).

- 主钱包/阈值存 hk_platform_settings (sweep_target_<network> / sweep_threshold_<network>)
- 地址缺 gas (TRX/ETH/BNB) 不强行转: 记 gas_needed, 管理员手动补 gas 后再跑
- 每次归集写 hk_sweep_records 留痕
"""
from __future__ import annotations

import asyncio
import logging
from decimal import Decimal

import httpx
from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import (
    HkDepositAddress,
    HkPlatformSetting,
    HkSweepRecord,
)
from models.hk import HkUser
from services import evmscan, trongrid
from services.deposit_service import NETWORKS, get_network

logger = logging.getLogger(__name__)

# 归集所需原生币下限: tron 30 TRX (USDT 转账 ~13-27), evm 按 gasPrice*gas 估算
TRON_MIN_SUN = 30_000_000
EVM_GAS_LIMIT = 100_000  # ERC20 transfer 典型 ~65k, 留余量

DEFAULT_THRESHOLD = Decimal("500")


async def get_setting(db: AsyncSession, key: str, default: str = "") -> str:
    row = (
        await db.execute(
            select(HkPlatformSetting).where(HkPlatformSetting.key == key)
        )
    ).scalar_one_or_none()
    return row.value if row else default


async def set_setting(db: AsyncSession, key: str, value: str) -> None:
    row = (
        await db.execute(
            select(HkPlatformSetting).where(HkPlatformSetting.key == key)
        )
    ).scalar_one_or_none()
    if row is None:
        db.add(HkPlatformSetting(key=key, value=value))
    else:
        row.value = value
    await db.flush()


async def get_targets(db: AsyncSession) -> dict:
    """各网络主钱包 + 阈值."""
    out = {}
    for network in NETWORKS:
        out[network] = {
            "target": await get_setting(db, f"sweep_target_{network}"),
            "threshold": await get_setting(
                db, f"sweep_threshold_{network}", str(DEFAULT_THRESHOLD)
            ),
        }
    return out


# ---------- 链上余额 ----------


async def _tron_balances(
    client: httpx.AsyncClient, address: str, usdt_contract: str
) -> tuple[Decimal, Decimal]:
    """返回 (USDT 余额, TRX 余额)."""
    resp = await client.get(
        f"{trongrid.TRONGRID_BASE}/v1/accounts/{address}",
        timeout=trongrid.HTTP_TIMEOUT,
    )
    data = resp.json().get("data") or []
    if not data:
        return Decimal(0), Decimal(0)
    acc = data[0]
    trx = Decimal(acc.get("balance", 0)) / Decimal(10**6)
    usdt = Decimal(0)
    for t in acc.get("trc20", []) or []:
        for k, v in t.items():
            if k.lower() == usdt_contract.lower():
                usdt = Decimal(v) / Decimal(10**6)
    return usdt, trx


async def address_balances(
    db: AsyncSession, network: str
) -> list[dict]:
    """已分配地址的 USDT + 原生币余额 (归集决策依据)."""
    cfg = get_network(network)
    rows = (
        await db.execute(
            select(HkDepositAddress).where(
                HkDepositAddress.network == network,
                HkDepositAddress.user_id.isnot(None),
            )
        )
    ).scalars().all()
    out = []
    async with trongrid.make_client() as client:
        for addr in rows:
            try:
                if cfg["chain"] == "tron":
                    usdt, native = await _tron_balances(
                        client, addr.address, cfg["usdt_contract"]
                    )
                    native_symbol = "TRX"
                else:
                    usdt = await evmscan.token_balance(
                        client, cfg["chain_id"], addr.address,
                        cfg["usdt_contract"], cfg["decimals"],
                    )
                    native = await evmscan.native_balance(
                        client, cfg["chain_id"], addr.address
                    )
                    native_symbol = {1: "ETH", 56: "BNB", 42161: "ETH"}[
                        cfg["chain_id"]
                    ]
            except Exception as e:  # noqa: BLE001
                logger.warning("sweep balance %s failed: %s", addr.address, e)
                continue
            if usdt <= 0 and native <= 0:
                continue  # 空地址不展示
            out.append(
                {
                    "address": addr.address,
                    "user_id": addr.user_id,
                    "usdt": str(usdt),
                    "native": str(native),
                    "native_symbol": native_symbol,
                }
            )
    return out


# ---------- 归集执行 ----------


def _tron_sweep(priv_hex: str, source: str, target: str, units: int,
                usdt_contract: str) -> str:
    """tronpy 签名广播 TRC20 transfer, 返回 txid. 同步阻塞, 调用方 to_thread."""
    from tronpy import Tron
    from tronpy.keys import PrivateKey

    client = Tron(network="mainnet")
    priv = PrivateKey(bytes.fromhex(priv_hex.removeprefix("0x")))
    contract = client.get_contract(usdt_contract)
    txn = (
        contract.functions.transfer(target, units)
        .with_owner(source)
        .fee_limit(15_000_000)
        .build()
        .sign(priv)
        .broadcast()
    )
    # broadcast 返回 {'result': True, 'txid': ...} 或 TransactionRet
    if hasattr(txn, "txid"):
        return txn.txid
    if isinstance(txn, dict) and txn.get("result") and txn.get("txid"):
        return txn["txid"]
    raise RuntimeError(str(txn)[:200])


async def _evm_sweep(client: httpx.AsyncClient, cfg: dict, priv_hex: str,
                     source: str, target: str, units: int) -> str:
    """eth_account 签名 + Etherscan proxy 广播, 返回 0x txid."""
    from eth_account import Account

    chain_id = cfg["chain_id"]
    nonce = await evmscan.tx_nonce(client, chain_id, source)
    price = await evmscan.gas_price(client, chain_id)
    data = (
        "0xa9059cbb"
        + target.lower().removeprefix("0x").rjust(64, "0")
        + hex(units)[2:].rjust(64, "0")
    )
    tx = {
        "chainId": chain_id,
        "nonce": nonce,
        "to": cfg["usdt_contract"],
        "value": 0,
        "gas": EVM_GAS_LIMIT,
        "gasPrice": price,
        "data": data,
    }
    signed = Account.sign_transaction(tx, priv_hex)
    return await evmscan.send_raw_tx(client, chain_id, signed.raw_transaction.hex())


async def run_sweep(
    db: AsyncSession, network: str, operator: HkUser,
    only_address: str | None = None,
) -> dict:
    """归集一网络: USDT >= 阈值且 gas 够的地址全部转到主钱包.

    返回 {swept, gas_needed, failed, skipped}.
    """
    cfg = get_network(network)
    target = await get_setting(db, f"sweep_target_{network}")
    if not target:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"未设置 {network} 主钱包地址 (先保存归集设置)",
        )
    threshold = Decimal(
        await get_setting(db, f"sweep_threshold_{network}", str(DEFAULT_THRESHOLD))
    )

    rows = (
        await db.execute(
            select(HkDepositAddress).where(
                HkDepositAddress.network == network,
                HkDepositAddress.user_id.isnot(None),
                HkDepositAddress.private_key.isnot(None),
            )
        )
    ).scalars().all()
    if only_address:
        rows = [r for r in rows if r.address == only_address]
        if not rows:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "该地址不在充值池")

    result = {"swept": 0, "gas_needed": 0, "failed": 0, "skipped": 0}
    async with trongrid.make_client() as client:
        for addr in rows:
            try:
                if cfg["chain"] == "tron":
                    usdt, native = await _tron_balances(
                        client, addr.address, cfg["usdt_contract"]
                    )
                    gas_ok = native * Decimal(10**6) >= TRON_MIN_SUN
                else:
                    usdt = await evmscan.token_balance(
                        client, cfg["chain_id"], addr.address,
                        cfg["usdt_contract"], cfg["decimals"],
                    )
                    native = await evmscan.native_balance(
                        client, cfg["chain_id"], addr.address
                    )
                    price = await evmscan.gas_price(client, cfg["chain_id"])
                    gas_ok = native >= Decimal(price * EVM_GAS_LIMIT) / Decimal(
                        10**18
                    )
            except Exception as e:  # noqa: BLE001
                logger.warning("sweep probe %s failed: %s", addr.address, e)
                result["failed"] += 1
                continue

            if usdt < threshold:
                result["skipped"] += 1
                continue

            def record(status_: str, txid=None, error=None) -> HkSweepRecord:
                return HkSweepRecord(
                    network=network,
                    from_address=addr.address,
                    to_address=target,
                    amount=usdt,
                    txid=txid,
                    status=status_,
                    error=error,
                    operator_id=operator.id,
                    operator_username=operator.username,
                )

            if not gas_ok:
                db.add(record("gas_needed"))
                await db.flush()
                result["gas_needed"] += 1
                continue

            units = int(usdt * Decimal(10 ** cfg["decimals"]))
            try:
                if cfg["chain"] == "tron":
                    txid = await asyncio.to_thread(
                        _tron_sweep, addr.private_key, addr.address, target,
                        units, cfg["usdt_contract"],
                    )
                else:
                    txid = await _evm_sweep(
                        client, cfg, addr.private_key, addr.address, target, units
                    )
                db.add(record("success", txid=txid))
                result["swept"] += 1
                logger.info(
                    "sweep ok %s %s -> %s: %s USDT txid=%s",
                    network, addr.address, target, usdt, txid,
                )
            except Exception as e:  # noqa: BLE001
                logger.warning("sweep %s %s failed: %s",
                               network, addr.address, e)
                db.add(record("failed", error=str(e)[:250]))
                result["failed"] += 1
            await db.flush()
    await db.commit()
    return result
