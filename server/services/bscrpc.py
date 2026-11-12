"""BSC 公共 JSON-RPC 封装: BEP20 扫链/余额/广播 (替代 Etherscan, 免费套餐不覆盖 BSC).

默认 bsc-dataseed 官方公共节点, 可用 BSC_RPC_URL 覆盖.
限流 (HTTP 429 / RPC -32005) 抛 RateLimited, 由调用方退避.
"""
from __future__ import annotations

import logging
from datetime import datetime
from decimal import Decimal

import httpx

from config import config

logger = logging.getLogger(__name__)

HTTP_TIMEOUT = 15.0

TRANSFER_TOPIC = (
    "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
)


class RateLimited(Exception):
    """RPC 节点限流."""


def _rpc_urls() -> list[str]:
    """主节点 + 公共备用节点."""
    urls = [config.bsc_rpc_url]
    for u in (
        "https://bsc-rpc.publicnode.com",
        "https://bsc-dataseed.binance.org/",
        "https://bsc-dataseed1.defibit.io/",
        "https://bsc-dataseed1.ninicoin.io/",
        "https://binance.llamarpc.com",
    ):
        if u not in urls:
            urls.append(u)
    return urls


async def _rpc(client: httpx.AsyncClient, method: str, params: list):
    """单方法调用, 节点失败/限流自动尝试备用节点; 全节点限流才抛 RateLimited."""
    last_err: Exception | None = None
    rate_limited = False
    for url in _rpc_urls():
        try:
            resp = await client.post(
                url,
                json={"jsonrpc": "2.0", "id": 1, "method": method, "params": params},
                timeout=HTTP_TIMEOUT,
            )
            if resp.status_code == 429:
                raise RateLimited(f"{url} {method} 429")
            resp.raise_for_status()
            data = resp.json()
            if "error" in data:
                err = data["error"]
                if err.get("code") == -32005 or "limit" in str(
                    err.get("message", "")
                ).lower():
                    raise RateLimited(f"{url} {method}: {err}")
                raise RuntimeError(f"bsc rpc {method}: {err}")
            return data.get("result")
        except RateLimited as e:
            rate_limited = True
            last_err = e
            logger.warning("bsc rpc %s via %s limited, try next node", method, url)
        except Exception as e:  # noqa: BLE001 换备用节点重试
            last_err = e
            logger.warning("bsc rpc %s via %s failed: %s", method, url, e)
    if rate_limited:
        raise RateLimited(f"all nodes limited: {last_err}")
    raise RuntimeError(f"bsc rpc {method} all nodes failed: {last_err}")


async def latest_block(client: httpx.AsyncClient) -> int:
    return int(await _rpc(client, "eth_blockNumber", []), 16)


async def native_balance(client: httpx.AsyncClient, address: str) -> Decimal:
    """BNB 余额, 单位 BNB."""
    result = await _rpc(client, "eth_getBalance", [address, "latest"])
    return Decimal(int(result, 16)) / Decimal(10**18)


async def gas_price(client: httpx.AsyncClient) -> int:
    """wei."""
    return int(await _rpc(client, "eth_gasPrice", []), 16)


async def tx_nonce(client: httpx.AsyncClient, address: str) -> int:
    return int(
        await _rpc(client, "eth_getTransactionCount", [address, "latest"]), 16
    )


async def token_balance(
    client: httpx.AsyncClient, address: str, contract: str, decimals: int
) -> Decimal:
    """BEP20 余额 (eth_call balanceOf)."""
    data = "0x70a08231" + address.lower().removeprefix("0x").rjust(64, "0")
    result = await _rpc(
        client, "eth_call", [{"to": contract, "data": data}, "latest"]
    )
    return Decimal(int(result, 16)) / Decimal(10**decimals)


async def fetch_incoming(
    client: httpx.AsyncClient,
    usdt_contract: str,
    address: str,
    from_block: int,
    to_block: int,
    decimals: int,
) -> list[dict]:
    """eth_getLogs 拉 [from_block, to_block] 内该地址的 USDT 转入 (归一化)."""
    logs = await _rpc(
        client,
        "eth_getLogs",
        [
            {
                "address": usdt_contract,
                "fromBlock": hex(from_block),
                "toBlock": hex(to_block),
                "topics": [
                    TRANSFER_TOPIC,
                    None,
                    "0x" + address.lower().removeprefix("0x").rjust(64, "0"),
                ],
            }
        ],
    )
    out = []
    for log in logs or []:
        try:
            topics = log["topics"]
            out.append(
                {
                    "txid": log["transactionHash"].lower().removeprefix("0x"),
                    "from": "0x" + topics[1][-40:],
                    "to": "0x" + topics[2][-40:],
                    "block_number": int(log["blockNumber"], 16),
                    "amount": Decimal(int(log["data"], 16))
                    / Decimal(10**decimals),
                    "block_time": None,  # 日志不含时间戳, 建记录时再补
                }
            )
        except (KeyError, ValueError, TypeError, IndexError):
            continue
    return out


async def block_time(client: httpx.AsyncClient, block_number: int) -> datetime | None:
    """补单/建记录时按需补块时间戳 (UTC 裸值)."""
    result = await _rpc(
        client, "eth_getBlockByNumber", [hex(block_number), False]
    )
    if not result:
        return None
    return datetime.utcfromtimestamp(int(result["timestamp"], 16))


async def tx_receipt_transfers(
    client: httpx.AsyncClient, txid: str, usdt_contract: str, decimals: int
) -> list[dict]:
    """交易回执里的 USDT Transfer 事件 (补单按 txid 精确认领用)."""
    receipt = await _rpc(
        client, "eth_getTransactionReceipt", ["0x" + txid.removeprefix("0x")]
    )
    if not receipt:
        return []
    out = []
    for log in receipt.get("logs", []):
        try:
            if log["address"].lower() != usdt_contract.lower():
                continue
            topics = log["topics"]
            if not topics or topics[0].lower() != TRANSFER_TOPIC:
                continue
            out.append(
                {
                    "txid": receipt["transactionHash"]
                    .lower()
                    .removeprefix("0x"),
                    "from": "0x" + topics[1][-40:],
                    "to": "0x" + topics[2][-40:],
                    "block_number": int(receipt["blockNumber"], 16),
                    "amount": Decimal(int(log["data"], 16))
                    / Decimal(10**decimals),
                    "block_time": None,
                }
            )
        except (KeyError, ValueError, TypeError, IndexError):
            continue
    return out


async def send_raw_tx(client: httpx.AsyncClient, raw_hex: str) -> str:
    """广播签名交易, 返回 0x txid."""
    return await _rpc(client, "eth_sendRawTransaction", [raw_hex])
