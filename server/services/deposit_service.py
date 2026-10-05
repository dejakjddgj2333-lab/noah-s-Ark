"""充值服务: 地址分配 + 记录查询 + txid 补单 (需求文档第六节).

充值网络配置见 NETWORKS; 首批仅 TRC20. 到账判定/确认数见 docs/充值模块设计方案.md.
"""
from __future__ import annotations

import re
from decimal import Decimal

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from models.account import HkDepositAddress, HkDepositRecord
from models.hk import utc_now
from services import account_service, evmscan, trongrid

# 网络配置: chain=tron 走 TronGrid; chain=evm 走 Etherscan V2 (chain_id 区分).
# usdt_contract 为各网 USDT 官方合约; decimals 影响金额解析.
NETWORKS: dict[str, dict] = {
    "trc20": {
        "name": "TRC20 (Tron)",
        "usdt_contract": "TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t",
        "confirmations_required": 12,
        "min_deposit": "10",  # USDT, 设计文档第三节
        "decimals": 6,
        "chain": "tron",
    },
    "erc20": {
        "name": "ERC20 (Ethereum)",
        "usdt_contract": "0xdAC17F958D2ee523a1638c3018b8Eb7c0b51D39E4",
        "confirmations_required": 12,
        "min_deposit": "10",
        "decimals": 6,
        "chain": "evm",
        "chain_id": 1,
    },
    "bep20": {
        "name": "BEP20 (BSC)",
        "usdt_contract": "0x55d398326f99059fF775485246999027B3197955",
        "confirmations_required": 15,
        "min_deposit": "10",
        "decimals": 18,
        "chain": "evm",
        "chain_id": 56,
    },
    "arbitrum": {
        "name": "Arbitrum One",
        "usdt_contract": "0xFd086bC7CD5C481DCC9C85C478Fbe1e0C31CaaF69",
        "confirmations_required": 12,
        "min_deposit": "10",
        "decimals": 6,
        "chain": "evm",
        "chain_id": 42161,
    },
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


_TXID_RE = re.compile(r"^[0-9a-fA-F]{64}$")


async def prepare_transfer(
    db: AsyncSession, user_id: int, network: str, owner_address: str, amount: Decimal
) -> dict:
    """构造未签名 USDT transfer (钱包连接支付用).

    tron: TronGrid triggersmartcontract 生成, 钱包签名后走 broadcast.
    evm: 本地构造 eth_sendTransaction 参数, 钱包自行估 gas 签名并广播.
    """
    network = network.lower()
    cfg = get_network(network)
    min_deposit = Decimal(cfg["min_deposit"])
    if amount < min_deposit:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"低于最小充值金额 {min_deposit} USDT",
        )
    if amount > Decimal("1000000"):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="金额超出限制")

    addr = await get_or_assign_address(db, user_id, network)
    units = int(amount * Decimal(10 ** cfg["decimals"]))

    if cfg["chain"] == "evm":
        owner = owner_address.strip()
        if not re.fullmatch(r"0x[0-9a-fA-F]{40}", owner):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail="付款地址不是有效 EVM 地址"
            )
        data = (
            "0xa9059cbb"
            + addr.address.lower().removeprefix("0x").rjust(64, "0")
            + hex(units)[2:].rjust(64, "0")
        )
        return {
            "transaction": {
                "from": owner,
                "to": cfg["usdt_contract"],
                "value": "0x0",
                "data": data,
            },
            "chain_id": cfg["chain_id"],
            "to": addr.address,
            "amount": str(amount),
        }

    # tron
    try:
        from tronpy.keys import to_base58check_address, to_hex_address

        owner = to_base58check_address(owner_address)  # 校验+归一化
        owner_hex = to_hex_address(owner)
        contract_hex = to_hex_address(cfg["usdt_contract"])
    except Exception:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="付款地址不是有效 TRC20 地址"
        ) from None

    to_hex = to_hex_address(addr.address)
    # transfer(address,uint256): 地址去 0x41 前缀补 32 字节 + 金额 32 字节
    parameter = to_hex[2:].rjust(64, "0") + hex(units)[2:].rjust(64, "0")
    payload = {
        "owner_address": owner,
        "contract_address": cfg["usdt_contract"],
        "function_selector": "transfer(address,uint256)",
        "parameter": parameter,
        "fee_limit": 15_000_000,  # 15 TRX 上限
        "call_value": 0,
        "visible": True,
    }
    async with trongrid.make_client() as client:
        try:
            resp = await client.post(
                f"{trongrid.TRONGRID_BASE}/wallet/triggersmartcontract",
                json=payload,
                timeout=trongrid.HTTP_TIMEOUT,
            )
            data = resp.json()
        except Exception:
            raise HTTPException(
                status.HTTP_502_BAD_GATEWAY, detail="链上交易构造失败, 请稍后重试"
            ) from None
    tx = data.get("transaction")
    if not tx:
        msg = (data.get("Error") or data.get("error") or "构造失败").__str__()
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=msg)
    return {
        "transaction": tx,
        "to": addr.address,
        "amount": str(amount),
        "owner_hex": owner_hex,
        "contract_hex": contract_hex,
    }


async def broadcast_tx(signed_tx: dict) -> str:
    """广播钱包签名的交易, 返回 txid."""
    async with trongrid.make_client() as client:
        try:
            resp = await client.post(
                f"{trongrid.TRONGRID_BASE}/wallet/broadcasttransaction",
                json=signed_tx,
                timeout=trongrid.HTTP_TIMEOUT,
            )
            data = resp.json()
        except Exception:
            raise HTTPException(
                status.HTTP_502_BAD_GATEWAY, detail="广播失败, 请稍后重试"
            ) from None
    if data.get("result") and data.get("txid"):
        return data["txid"]
    msg = data.get("message") or data.get("code") or "广播被拒绝"
    if isinstance(msg, str):
        try:
            msg = bytes.fromhex(msg).decode()
        except ValueError:
            pass
    raise HTTPException(status.HTTP_400_BAD_REQUEST, detail=f"广播失败: {msg}")


async def claim_by_txid(
    db: AsyncSession, user_id: int, network: str, txid: str
) -> HkDepositRecord:
    """txid 补单: 链上已转但 monitor 未抓到/未到账时用户自助核销.

    幂等: txid 已有记录直接返回. 只认领"转入本人充值地址"的 USDT.
    """
    network = network.lower()
    cfg = get_network(network)
    txid = txid.strip()
    if txid.lower().startswith("0x"):
        txid = txid[2:]  # EVM 交易哈希 0x 前缀归一化
    txid = txid.lower()  # 哈希大小写不敏感, 归一化防大小写变体重复入账
    if not _TXID_RE.match(txid):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, detail="txid 格式不正确")

    existing = await db.execute(
        select(HkDepositRecord).where(
            HkDepositRecord.network == network,
            HkDepositRecord.txid == txid,
        )
    )
    record = existing.scalar_one_or_none()
    if record is not None:
        if record.user_id != user_id:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail="该 txid 与本账户无关"
            )
        return record  # 幂等: 重复提交返回现状

    # 必须已分配地址 (没地址说明没充值入口记录)
    result = await db.execute(
        select(HkDepositAddress).where(
            HkDepositAddress.network == network,
            HkDepositAddress.user_id == user_id,
        )
    )
    addr = result.scalar_one_or_none()
    if addr is None:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="请先获取充值地址"
        )

    is_evm = cfg["chain"] == "evm"
    if is_evm and not evmscan.available():
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="该网络暂未开放, 请用 TRC20 或联系客服",
        )
    async with trongrid.make_client() as client:
        try:
            if is_evm:
                txs = await evmscan.fetch_incoming(
                    client, cfg["chain_id"], addr.address,
                    cfg["usdt_contract"], cfg["decimals"], limit=200,
                )
                latest = await evmscan.latest_block(client, cfg["chain_id"])
            else:
                txs = await trongrid.fetch_incoming(
                    client, addr.address, cfg["usdt_contract"], limit=200
                )
                latest = await trongrid.latest_block(client)
        except (trongrid.RateLimited, evmscan.RateLimited):
            raise HTTPException(
                status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="链上查询限流, 请稍后重试",
            ) from None
        except Exception:
            raise HTTPException(
                status.HTTP_502_BAD_GATEWAY,
                detail="链上查询失败, 请稍后重试",
            ) from None

    tx = next(
        (t for t in txs if t["txid"].lower().removeprefix("0x") == txid.lower()),
        None,
    )
    if tx is None:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND,
            detail="未查到该笔转入您充值地址的 USDT 记录, 请核对 txid 或联系客服",
        )

    confirmations = max((latest or tx["block_number"]) - tx["block_number"] + 1, 0)
    required = cfg["confirmations_required"]
    min_deposit = Decimal(cfg["min_deposit"])
    record = HkDepositRecord(
        user_id=user_id,
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
    if tx["amount"] < min_deposit:
        record.status = "unmatched"  # 低额不入账, 走客服
    db.add(record)
    try:
        await db.flush()
    except IntegrityError:
        # 与扫链 monitor 并发撞 txid 唯一键: 放弃本单, 返回已有记录 (入账一次)
        await db.rollback()
        existing = await db.execute(
            select(HkDepositRecord).where(
                HkDepositRecord.network == network,
                HkDepositRecord.txid == txid,
            )
        )
        record = existing.scalar_one()
        if record.user_id != user_id:
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail="该 txid 与本账户无关"
            )
        return record
    if record.status == "confirming" and record.confirmations >= required:
        await account_service.credit_principal(db, record)
    await db.commit()
    await db.refresh(record)
    return record
