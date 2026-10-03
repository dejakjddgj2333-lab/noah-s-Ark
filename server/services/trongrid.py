"""TronGrid 公共封装: 扫链 monitor 与 txid 补单共用.

免费 key 10 万次/天、15 QPS; 无 key 公共 3 QPS. 429 由调用方退避.
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal

import httpx

from config import config

logger = logging.getLogger(__name__)

TRONGRID_BASE = "https://api.trongrid.io"
HTTP_TIMEOUT = 10.0


def _headers() -> dict[str, str]:
    if config.trongrid_api_key:
        return {"TRON-PRO-API-KEY": config.trongrid_api_key}
    return {}


def make_client() -> httpx.AsyncClient:
    return httpx.AsyncClient(headers=_headers())


class RateLimited(Exception):
    """TronGrid 429."""


def extract_txs(data: dict, usdt_contract: str) -> list[dict]:
    """TronGrid trc20 交易列表 -> 归一化字段 (仅指定合约的转入)."""
    out = []
    for tx in data.get("data", []) or []:
        try:
            if tx.get("token_info", {}).get("address") not in (
                None,
                usdt_contract,
            ):
                continue  # 其他代币不入账 (只统计 USDT)
            value = tx.get("value", "0")
            out.append(
                {
                    "txid": tx["transaction_id"],
                    "from": tx.get("from", ""),
                    "to": tx.get("to", ""),
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


async def latest_block(client: httpx.AsyncClient) -> int | None:
    try:
        resp = await client.get(
            f"{TRONGRID_BASE}/walletsolidity/getnowblock",
            timeout=HTTP_TIMEOUT,
        )
        if resp.status_code == 429:
            raise RateLimited("getnowblock 429")
        resp.raise_for_status()
        return int(resp.json()["block_header"]["raw_data"]["number"])
    except RateLimited:
        raise
    except Exception as e:  # noqa: BLE001 轮询服务不中断
        logger.warning("trongrid latest_block failed: %s", e)
        return None


async def fetch_incoming(
    client: httpx.AsyncClient, address: str, usdt_contract: str, limit: int = 50
) -> list[dict]:
    """拉某地址的 USDT-TRC20 转入列表 (归一化). 429 抛 RateLimited."""
    resp = await client.get(
        f"{TRONGRID_BASE}/v1/accounts/{address}/transactions/trc20",
        params={
            "contract_address": usdt_contract,
            "only_confirmed": "true",
            "only_to": "true",
            "limit": limit,
        },
        timeout=HTTP_TIMEOUT,
    )
    if resp.status_code == 429:
        raise RateLimited(f"{address} 429")
    resp.raise_for_status()
    return extract_txs(resp.json(), usdt_contract)
