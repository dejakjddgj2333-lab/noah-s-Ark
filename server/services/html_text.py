"""APITube body_html 转带段落换行的纯文本 (移植自 okx services/html_text).

APITube 的 body 字段是摊平纯文本 (无换行), body_html 保留 <p>/<li> 结构.
转成 \n\n 分段纯文本, 供翻译按段落分块、前端按段落渲染.
"""
from __future__ import annotations

import re
from html import unescape

_BLOCK_CLOSE = re.compile(
    r"</(?:p|div|li|h[1-6]|blockquote|section|article|tr)\s*>", re.I
)
_BR = re.compile(r"<br\s*/?>", re.I)
_LI_OPEN = re.compile(r"<li[^>]*>", re.I)
_SCRIPT_STYLE = re.compile(r"<(script|style)[^>]*>.*?</\1>", re.I | re.S)
_TAG = re.compile(r"<[^>]+>")
_WS_LINES = re.compile(r"[ \t]*\n[ \t]*")
_MULTI_NL = re.compile(r"\n{3,}")


def body_html_to_text(html: str | None) -> str | None:
    """body_html → 分段纯文本; 空/无内容返回 None."""
    if not html or not html.strip():
        return None
    text = _SCRIPT_STYLE.sub("", html)
    text = _LI_OPEN.sub("\n• ", text)
    text = _BLOCK_CLOSE.sub("\n\n", text)
    text = _BR.sub("\n", text)
    text = _TAG.sub("", text)
    text = unescape(text)
    text = _WS_LINES.sub("\n", text)
    text = _MULTI_NL.sub("\n\n", text).strip()
    return text or None
