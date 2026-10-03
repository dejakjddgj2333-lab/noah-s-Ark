"""平台充值地址生成 (tronpy). 私钥仅开发环境入库, 生产必须改为 KMS/硬件钱包."""
from __future__ import annotations

import asyncio

from fastapi import HTTPException, status
from tronpy.keys import PrivateKey

from database import SessionLocal
from models.account import HkDepositAddress


async def generate_addresses(network: str, count: int) -> int:
    """生成 count 个指定网络的充值地址并存入地址池. 返回生成数量."""
    if network != "trc20":
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"暂不支持生成 {network} 地址 (当前仅 trc20)",
        )

    def _gen() -> list[tuple[str, str]]:
        out = []
        for _ in range(count):
            priv = PrivateKey.random()
            out.append((priv.public_key.to_base58check_address(), priv.hex()))
        return out

    items = await asyncio.to_thread(_gen)
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
