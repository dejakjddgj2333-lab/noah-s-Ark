"""资讯正文/摘要 HTML → 纯文本 (对齐 web-terminal src/utils/htmlText.js).

背景: 共享库 news_articles 由 okx 侧采集, apitube 的 content/summary 是整段 HTML
(含 <p>/<a>/<img>/自定义 bi-shortcode 与实体), 前端按纯文本渲染会把标签露出.
hk 侧只读不改库, 在出参时降级为可读纯文本: 丢图片/链接, 只留文字 (封面走 cover_url).
"""
from __future__ import annotations

import html as _html
import re

# bi-shortcode / script / style 整块丢弃 (含占位文本 "摘要列表位置" 等)
_DROP_BLOCK_RE = re.compile(r"<(bi-shortcode|script|style)\b[\s\S]*?</\1>", re.I)
# 块级标签边界 → 换行
_BLOCK_RE = re.compile(
    r"</?(?:p|div|li|ul|ol|h[1-6]|blockquote|section|article|header|footer"
    r"|table|thead|tbody|tr|td|th|figure|figcaption|hr|br)\b[^>]*>",
    re.I,
)
# 其余所有标签 (含截断的残缺尾标签)
_TAG_RE = re.compile(r"</?[a-zA-Z][^>]*>?")
_WS_RE = re.compile(r"\s+")


def _drop_mojibake(s: str) -> str:
    """抹掉采集/翻译管道的编码损坏残留: 替换符 U+FFFD 与孤立代理项."""
    return "".join(
        c for c in s if c != "\ufffd" and not (0xD800 <= ord(c) <= 0xDFFF)
    )


def html_to_text(raw: object) -> str:
    """HTML → 纯文本, 段落间保留一个空行. 非字符串/无标签输入原样返回 (trim)."""
    s = raw if isinstance(raw, str) else ("" if raw is None else str(raw))
    if not s or ("<" not in s and "&" not in s and "\ufffd" not in s):
        return _drop_mojibake(s.strip())
    s = _DROP_BLOCK_RE.sub("", s)
    s = _BLOCK_RE.sub("\n", s)
    s = _TAG_RE.sub("", s)
    # html.unescape 覆盖全部命名/数字实体 (&nbsp; &#187; &#x1F600; ...);
    # 对孤立的 "&187;" 之类非法实体原样保留, 不会炸
    s = _html.unescape(s)
    s = _drop_mojibake(s)
    lines = [_WS_RE.sub(" ", line).strip() for line in s.split("\n")]
    return "\n\n".join(line for line in lines if line)
