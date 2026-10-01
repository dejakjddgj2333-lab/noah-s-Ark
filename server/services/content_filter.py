"""资讯内容过滤: 赌博及违法垃圾内容入库前拦截 (移植自 okx services/content_filter).

APITube 用 crypto 关键词会命中大量网赌 SEO 垃圾稿 (casino/slots 站群),
按标题+摘要+正文匹配关键词, 命中即丢弃, 不入库.
"""
from __future__ import annotations

import re

# 英文: 词边界匹配, 避免误伤
_EN_TERMS = [
    "casino", "casinos", "gambling", "gambler", "gamblers",
    "slot", "slots", "poker", "roulette", "blackjack", "baccarat",
    "sportsbook", "betting", "bet", "bets", "wager", "wagering",
    "lottery", "lotteries", "bingo", "jackpot", "jackpots",
    "free spins", "no deposit bonus", "real money casino",
    "online casino", "live dealer", "slot machine",
]
# 中文: 子串匹配
_ZH_TERMS = [
    "赌博", "赌场", "博彩", "赌钱", "赌球", "投注站", "老虎机",
    "轮盘", "百家乐", "彩票", "赌局", "赌资", "网上赌场", "在线赌场",
]

_EN_RE = re.compile(
    r"\b(?:" + "|".join(re.escape(t) for t in _EN_TERMS) + r")\b", re.I
)


def is_blocked(*texts: str | None) -> bool:
    """任一文本命中赌博/违法关键词即拦截."""
    for text in texts:
        if not text:
            continue
        if _EN_RE.search(text):
            return True
        for term in _ZH_TERMS:
            if term in text:
                return True
    return False
