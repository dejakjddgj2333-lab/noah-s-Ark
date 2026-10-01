"""DeepSeek 翻译 (异步版, 移植自 okx services/translate_service).

资讯入库时把英文标题/摘要/正文翻成简体中文.
DeepSeek 是 OpenAI 兼容接口 (POST /chat/completions, model=deepseek-chat).
正文按段落分块全文翻译, 保留换行结构. 失败返回 None, 调用方回退原文.
"""
from __future__ import annotations

import asyncio
import json
import logging

import httpx

from config import config

logger = logging.getLogger(__name__)

_API_URL = "https://api.deepseek.com/chat/completions"
_MODEL = "deepseek-chat"
_CHUNK_CHARS = 1500

_HEAD_PROMPT = """把下面 JSON 里的英文资讯标题和摘要翻译成简体中文（加密货币领域，术语保留通用译法如 Bitcoin=比特币、ETF 不译）。
直接输出 JSON，字段与输入一致，不要任何额外内容。某字段为空字符串则原样返回空字符串。"""

_BODY_PROMPT = """把下面的英文资讯正文片段翻译成简体中文（加密货币领域，术语保留通用译法如 Bitcoin=比特币、ETF 不译）。
要求：完整翻译每一个字，不得省略或总结；严格保留原有的段落换行结构。
直接输出 JSON {"content": "译文"}，不要任何额外内容。"""


async def _chat_once(system: str, payload: str, max_tokens: int) -> dict | None:
    if not config.deepseek_api_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=60) as client:
            resp = await client.post(
                _API_URL,
                headers={"Authorization": f"Bearer {config.deepseek_api_key}"},
                json={
                    "model": _MODEL,
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": payload},
                    ],
                    "response_format": {"type": "json_object"},
                    "temperature": 0.1,
                    "max_tokens": max_tokens,
                },
            )
        resp.raise_for_status()
        content = resp.json()["choices"][0]["message"]["content"]
        # strict=False: DeepSeek 偶尔在 JSON 字符串里返回原始控制字符
        return json.loads(content, strict=False)
    except Exception as exc:
        logger.warning("deepseek_translate_failed: %s", str(exc)[:200])
        return None


async def _chat(system: str, payload: str, max_tokens: int = 8000) -> dict | None:
    """带重试的单次调用: DeepSeek 偶发截断 JSON, 重试可恢复."""
    for attempt in range(3):
        result = await _chat_once(system, payload, max_tokens)
        if result is not None:
            return result
        if attempt < 2:
            await asyncio.sleep(5)
    return None


def _chunk_text(text: str) -> list[str]:
    """按段落 (空行) 切分正文, 每块 ≤ _CHUNK_CHARS, 段落不拆散."""
    paragraphs = text.split("\n\n")
    chunks: list[str] = []
    buf = ""
    for p in paragraphs:
        if buf and len(buf) + len(p) + 2 > _CHUNK_CHARS:
            chunks.append(buf)
            buf = p
        else:
            buf = f"{buf}\n\n{p}" if buf else p
    if buf:
        chunks.append(buf)
    return chunks


async def _translate_chunk(text: str, depth: int = 0) -> str | None:
    """翻译一块正文; 失败按段落对半拆开重试."""
    r = await _chat(
        _BODY_PROMPT,
        json.dumps({"content": text}, ensure_ascii=False),
        max_tokens=8000,
    )
    if r and r.get("content"):
        return str(r["content"])
    if depth >= 2 or len(text) < 300:
        return None
    paras = text.split("\n\n")
    mid = max(1, len(paras) // 2)
    first = await _translate_chunk("\n\n".join(paras[:mid]), depth + 1)
    second = await _translate_chunk("\n\n".join(paras[mid:]), depth + 1)
    if first is None or second is None:
        return None
    return first + "\n\n" + second


async def translate_article(
    title: str, summary: str | None, content: str | None
) -> dict[str, str] | None:
    """全文翻译一篇, 返回 {'title','summary','content'} 中文; 失败 None.

    标题+摘要一次调用; 正文按块翻完拼接. 任一块失败整体 None (不出半成品).
    """
    if not title.strip():
        return None
    head = await _chat(
        _HEAD_PROMPT,
        json.dumps({"title": title, "summary": summary or ""}, ensure_ascii=False),
    )
    if not head or not head.get("title"):
        return None
    out = {
        "title": str(head["title"]),
        "summary": str(head.get("summary") or ""),
        "content": "",
    }
    if content and content.strip():
        parts: list[str] = []
        for chunk in _chunk_text(content):
            part = await _translate_chunk(chunk)
            if part is None:
                return None
            parts.append(part)
        out["content"] = "\n\n".join(parts)
    return out
