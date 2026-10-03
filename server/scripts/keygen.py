"""平台充值地址生成. 私钥仅开发环境入库, 生产必须改为 KMS/硬件钱包.

tron 用 tronpy; evm (erc20/bep20/arbitrum) 用 eth_account.
"""
from __future__ import annotations

import asyncio

from fastapi import HTTPException, status

from database import SessionLocal
from models.account import HkDepositAddress
from services.deposit_service import NETWORKS


def _gen_one(network: str) -> tuple[str, str]:
    chain = NETWORKS[network]["chain"]
    if chain == "tron":
        from tronpy.keys import PrivateKey

        priv = PrivateKey.random()
        return priv.public_key.to_base58check_address(), priv.hex()
    # evm: 同一地址三网通用, 但池按网络分行隔离管理
    from eth_account import Account

    acct = Account.create()
    return acct.address, acct.key.hex()


async def generate_addresses(network: str, count: int) -> int:
    """生成 count 个指定网络的充值地址并存入地址池. 返回生成数量."""
    if network not in NETWORKS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"不支持生成 {network} 地址 (当前支持: {', '.join(NETWORKS)})",
        )

    items = await asyncio.to_thread(lambda: [_gen_one(network) for _ in range(count)])
    async with SessionLocal() as db:
        for address, private_key in items:
            db.add(
                HkDepositAddress(
                    network=network,
                    address=address,
                    private_key=private_key,  # dev-only, 见 models/account.py 警示
                )
            )
        await db.commit()
    return len(items)
