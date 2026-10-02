"""宏观日历事件名中文化: DeepSeek 批量翻译 + hk_macro_name_zh 永久缓存.

事件名高度重复 (FOMC Member X Speaks / CPI y/y 等), 全部 distinct 仅百来个,
翻一次缓存复用. 接口每次只补翻新增的名, 失败回退英文原名.
"""
from __future__ import annotations

import json
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import HkMacroNameZh
from services.translate_service import _chat

logger = logging.getLogger(__name__)

_PROMPT = """把下面 JSON 数组里的宏观经济指标/事件英文名 (ForexFactory 日历风格) 翻译成简体中文。
要求: 金融术语通用译法 (CPI=消费者价格指数或保留CPI, FOMC=美联储, PMI=采购经理人指数, m/m=环比, y/y=同比, q/q=环比(季度), Speaks=讲话);
人名音译 (Jefferson=杰斐逊, Bowman=鲍曼); 简洁, 不超过 20 字。
直接输出 JSON {"map": {"原名": "译名", ...}}, 每个输入都要有键, 不要任何额外内容。"""

_BATCH = 40  # 每次请求翻 40 个


async def zh_name_map(db: AsyncSession, names: list[str]) -> dict[str, str]:
    """返回 {英文名: 中文名}. 未命中缓存的批量翻译入库, 失败回退原名."""
    unique = [n for n in dict.fromkeys(names) if n]
    if not unique:
        return {}
    cached = (
        await db.scalars(
            select(HkMacroNameZh).where(HkMacroNameZh.name.in_(unique))
        )
    ).all()
    out = {c.name: c.name_zh for c in cached}
    missing = [n for n in unique if n not in out]
    if not missing:
        return out

    for i in range(0, len(missing), _BATCH):
        chunk = missing[i : i + _BATCH]
        try:
            r = await _chat(
                _PROMPT, json.dumps({"names": chunk}, ensure_ascii=False),
                max_tokens=4000,
            )
            m = (r or {}).get("map") or {}
        except Exception as exc:
            logger.warning("macro_name_translate_failed: %s", str(exc)[:200])
            m = {}
        for name in chunk:
            zh = str(m.get(name) or "").strip()
            if not zh:
                continue
            db.add(HkMacroNameZh(name=name[:300], name_zh=zh[:300]))
            out[name] = zh
        try:
            await db.commit()
        except Exception:
            await db.rollback()  # 唯一键竞争等, 下轮再补
    return out
