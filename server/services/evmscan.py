"""Etherscan V2 公共封装: EVM 三网 (ERC20/BEP20/Arbitrum) 充值扫链.

V2 单 key 多链: https://api.etherscan.io/v2/api?chainid=X
免费 5 QPS / 10 万次一天. 无 key 不可用 (V2 强制 key), 空 key 时调用方跳过.
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal

import httpx

from config import config

logger = logging.getLogger(__name__)

V2_BASE = "https://api.etherscan.io/v2/api"
HTTP_TIMEOUT = 10.0


def available() -> bool:
    return bool(config.etherscan_api_key)


class RateLimited(Exception):
    """Etherscan 限流/额度耗尽."""


async def _get(client: httpx.AsyncClient, params: dict) -> dict:
    params = {**params, "apikey": config.etherscan_api_key}
    resp = await client.get(V2_BASE, params=params, timeout=HTTP_TIMEOUT)
    if resp.status_code == 429:
        raise RateLimited("etherscan 429")
    resp.raise_for_status()
    data = resp.json()
    # V2 业务错误: status "0" + message "NOTOK" (限流/额度也走这里)
    if isinstance(data, dict) and data.get("message") == "NOTOK":
        result = str(data.get("result", ""))
        if "rate limit" in result.lower() or "limit" in result.lower():
            raise RateLimited(result)
        raise RuntimeError(f"etherscan error: {result[:120]}")
    return data


async def latest_block(client: httpx.AsyncClient, chain_id: int) -> int | None:
    try:
        data = await _get(
            client,
            {"chainid": chain_id, "module": "proxy", "action": "eth_blockNumber"},
        )
        return int(data["result"], 16)
    except RateLimited:
        raise
    except Exception as e:  # noqa: BLE001
        logger.warning("etherscan latest_block chain=%s failed: %s", chain_id, e)
        return None


async def fetch_incoming(
    client: httpx.AsyncClient,
    chain_id: int,
    address: str,
    usdt_contract: str,
    decimals: int,
    limit: int = 50,
) -> list[dict]:
    """拉某地址的 USDT 转入 tokentx (归一化为 tron 同构字段). 429 抛 RateLimited."""
    data = await _get(
        client,
        {
            "chainid": chain_id,
            "module": "account",
            "action": "tokentx",
            "address": address,
            "contractaddress": usdt_contract,
            "page": 1,
            "offset": limit,
            "sort": "desc",
        },
    )
    out = []
    for tx in data.get("result", []) or []:
        try:
            if tx.get("to", "").lower() != address.lower():
                continue  # 只统计转入
            out.append(
                {
                    # 统一无 0x 小写存储, 与 tron 侧一致, (network,txid) 幂等不错位
                    "txid": tx["hash"].lower().removeprefix("0x"),
                    "from": tx.get("from", ""),
                    "to": tx.get("to", ""),
                    "block_number": int(tx["blockNumber"]),
                    "amount": Decimal(tx.get("value", "0")) / Decimal(10**decimals),
                    "block_time": datetime.fromtimestamp(int(tx["timeStamp"])),
                }
            )
        except (KeyError, ValueError, TypeError):
            continue
    return out
