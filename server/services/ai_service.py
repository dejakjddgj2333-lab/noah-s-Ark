"""AI 市场对话 + 每日综述: DeepSeek, 全异步。

核心原则 (与 okx 版一致): 所有数字由后端注入, AI 只做解读, 不预测价格、不给买卖点位。
hk 适配: coinglass_service → market_free/liq_aggregator/CoinGecko; 同步 DB → 异步。
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import time
from collections.abc import AsyncGenerator
from datetime import datetime, timedelta, timezone

import httpx
from sqlalchemy import select

from config import config

logger = logging.getLogger(__name__)

_API_URL = "https://api.deepseek.com/chat/completions"
_MODEL = "deepseek-chat"

# UI 语言 → 回答语言
_LANG_NAMES = {
    "zh": "简体中文",
    "en": "English",
    "ja": "日本語",
    "ko": "한국어",
    "fr": "Français",
    "es": "Español",
}


def _lang_of(lang: str) -> str:
    return _LANG_NAMES.get(lang, "简体中文")


# 流式失败兜底提示, 按 UI 语言
_ERR_BUSY = {
    "zh": "\n\n(AI 服务暂时繁忙, 请稍后再试)",
    "en": "\n\n(AI service is busy, please try again later)",
    "ja": "\n\n(AIサービスが混雑しています。しばらくしてから再試行してください)",
    "ko": "\n\n(AI 서비스가 혼잡합니다. 잠시 후 다시 시도해 주세요)",
    "fr": "\n\n(Service IA occupé, veuillez réessayer plus tard)",
    "es": "\n\n(Servicio de IA ocupado, inténtalo de nuevo más tarde)",
}

_SYSTEM = """你是资深的加密货币市场分析师「明策 AI」, 在一个行情终端里陪用户聊天。

边界 (只有这几条):
1. 所有数字必须来自下方注入的数据, 禁止编造数值、日期、事件; 数据里没有的就明说没有。
2. 问候、寒暄、日常闲聊可以放开聊, 像朋友一样自然回应, 别硬扯回行情; 聊到投资/市场类话题时才进入专业分析师状态。与加密货币完全无关的专业领域 (看病、法律咨询等) 礼貌说明不擅长。
3. 不说本平台的负面内容, 不贬低平台。
其余自由发挥, 大胆给出你的专业判断和观点。

说话方式 (反模板, 重点):
- 你在聊天, 不是在写报告。闲聊就闲聊: 一两句话、轻松、带点个性, 不要分点不要加粗不要端着。
- 用户问专业问题再专业: 数据、结构、逻辑讲透, 但组织方式跟着问题走, 禁止套用固定骨架。
- 用户问"怎么看/能不能买"这类开放问题时, 给明确倾向, 敢说"我偏空/这波我不追", 再讲为什么; 不要和稀泥列两边。
- 同一个会话里, 开头句式、组织方式不要和上几轮重复。用户连问几个币, 就从不同角度切入 (情绪、结构、资金面、事件轮着来)。
- 可以反问、可以追问用户持仓/周期, 把对话往前推进。
- 解读指标时说清楚"这个值在历史上处于什么位置、通常意味着什么", 而不是只复述数字。
- 专业名词 (资金费率、爆仓、市占率等) 一句话讲明白, 兼顾新手。
- 有【最新资讯】或【联网搜索】数据时, 像刚看到新闻一样自然带出来 ("刚才的消息是…"), 不要干巴巴罗列。

格式:
- markdown 可用, 但不要用一级/二级大标题 (# / ##); 复杂回答用小标题「**加粗**」。
- 篇幅跟着问题走: 简单问题一两句讲透, 复杂问题再展开。短回答优先。
- 语言专业但讲人话, 避免空话套话和模板腔。"""


# ---------- 实时数据上下文 (hk 数据源) ----------

# CoinGecko 全局数据小缓存 (btc 市占率用)
_gecko_cache: tuple[float, dict] | None = None


async def _btc_dominance() -> float | None:
    """BTC 市占率 (CoinGecko global, 10 分钟缓存)。失败 None。"""
    global _gecko_cache
    now = time.time()
    if _gecko_cache and _gecko_cache[0] > now:
        return _gecko_cache[1].get("btc_dominance")
    try:
        async with httpx.AsyncClient(timeout=12) as client:
            resp = await client.get("https://api.coingecko.com/api/v3/global")
            d = resp.json().get("data") or {}
        out = {
            "btc_dominance": (d.get("market_cap_percentage") or {}).get("btc"),
            "total_market_cap_usd": (d.get("total_market_cap") or {}).get("usd"),
            "market_cap_change_pct_24h": d.get("market_cap_change_percentage_24h_usd"),
        }
        _gecko_cache = (now + 600, out)
        return out["btc_dominance"]
    except Exception as exc:
        logger.warning("ai_gecko_failed: %s", str(exc)[:120])
        return None


async def _market_snapshot() -> str:
    """全市场快照: 情绪 + 市占率 + 山寨季 + 爆仓。任一源失败跳过, 不阻塞。"""
    from services import liq_aggregator, market_free

    fg, alt, liq, dom = await asyncio.gather(
        market_free.fear_greed(),
        market_free.altcoin_season(),
        liq_aggregator.exchange_list("24h"),
        _btc_dominance(),
        return_exceptions=True,
    )
    lines: list[str] = []
    if isinstance(fg, dict) and fg.get("fear_greed") is not None:
        lines.append(f"恐慌贪婪指数 {fg['fear_greed']}")
    if isinstance(dom, (int, float)):
        lines.append(f"BTC 市占率 {dom:.2f}%")
    if isinstance(alt, dict) and alt.get("value") is not None:
        lines.append(f"山寨季指数 {alt['value']:g}(>75 为山寨季)")
    if isinstance(liq, list) and liq:
        total = sum(r.get("liquidation_usd") or 0 for r in liq)
        long_ = sum(r.get("longLiquidation_usd") or 0 for r in liq)
        if total > 0:
            lines.append(
                f"24h 全网爆仓 ${total / 1e8:.2f}亿"
                f"(多 ${long_ / 1e8:.2f}亿 / 空 ${(total - long_) / 1e8:.2f}亿)"
            )
    return "【全市场快照】\n" + "\n".join(lines) if lines else ""


async def _news_digest(limit: int = 8) -> str:
    """最新资讯摘要: 读共享 news_articles 表。失败静默返回空。"""
    try:
        from database import SessionLocal
        from models.shared import NewsArticle

        async with SessionLocal() as db:
            rows = (
                await db.execute(
                    select(NewsArticle)
                    .where(NewsArticle.status == "published")
                    .order_by(NewsArticle.publish_at.desc())
                    .limit(limit)
                )
            ).scalars().all()
        if not rows:
            return ""
        lines = [f"[{r.publish_at:%m-%d %H:%M}] {r.title}" for r in rows]
        return "【最新资讯】\n" + "\n".join(lines)
    except Exception as exc:
        logger.warning("ai_news_digest_failed: %s", str(exc)[:120])
        return ""


# 需要实时检索的意图词: 命中才调联网搜索, 省 token 也避免乱引
_SEARCH_INTENT = (
    "最新", "最近", "刚刚", "今天", "新闻", "消息", "为什么涨", "为什么跌",
    "发生了", "事件", "突发", "利好", "利空",
    "news", "today", "why", "happened", "latest",
)


async def _web_search(query: str, limit: int = 3) -> str:
    """实时联网搜索。有 TAVILY_API_KEY 走 Tavily, 否则 DuckDuckGo (免 key)。失败静默。"""
    if os.getenv("TAVILY_API_KEY"):
        return await _tavily_search(query, limit)
    return await _ddg_search(query, limit)


async def _tavily_search(query: str, limit: int) -> str:
    try:
        async with httpx.AsyncClient(timeout=12) as client:
            resp = await client.post(
                "https://api.tavily.com/search",
                json={
                    "api_key": os.getenv("TAVILY_API_KEY", ""),
                    "query": query,
                    "max_results": limit,
                    "search_depth": "basic",
                    "topic": "news",
                },
            )
            resp.raise_for_status()
        results = resp.json().get("results") or []
        if not results:
            return ""
        lines = [
            f"- {r.get('title', '')}({r.get('url', '')})\n  {r.get('content', '')[:200]}"
            for r in results
        ]
        return "【联网搜索结果】\n" + "\n".join(lines)
    except Exception as exc:
        logger.warning("ai_tavily_failed: %s", str(exc)[:120])
        return ""


async def _ddg_search(query: str, limit: int) -> str:
    """DuckDuckGo html 端点抓取: 免 key。DDG 偶尔反爬限流 (202/403), 失败静默。"""
    import html as html_mod
    import re
    from urllib.parse import parse_qs, unquote, urlparse

    def _clean(s: str) -> str:
        return html_mod.unescape(re.sub(r"<[^>]+>", "", s)).strip()

    def _real_url(href: str) -> str:
        if "uddg=" in href:
            qs = parse_qs(urlparse(href).query)
            if qs.get("uddg"):
                return unquote(qs["uddg"][0])
        return href

    try:
        async with httpx.AsyncClient(timeout=12, follow_redirects=True) as client:
            resp = await client.post(
                "https://html.duckduckgo.com/html/",
                data={"q": query},
                headers={
                    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
                    "Accept-Language": "zh-CN,zh;q=0.9",
                },
            )
        if resp.status_code != 200:
            logger.warning("ai_ddg_failed status=%s", resp.status_code)
            return ""
        html = resp.text
        links = re.findall(
            r'class="result__a"[^>]+href="([^"]+)"[^>]*>(.*?)</a>', html
        )
        snippets = re.findall(r'class="result__snippet"[^>]*>(.*?)</a>', html)
        if not links:
            return ""
        lines: list[str] = []
        for i, (url, title) in enumerate(links[:limit]):
            snippet = _clean(snippets[i])[:200] if i < len(snippets) else ""
            lines.append(f"- {_clean(title)}({_real_url(url)})\n  {snippet}")
        return "【联网搜索结果】\n" + "\n".join(lines)
    except Exception as exc:
        logger.warning("ai_ddg_failed: %s", str(exc)[:120])
        return ""


async def _build_messages(
    message: str,
    history: list[dict] | None,
    lang: str = "zh",
) -> list[dict]:
    """组装 messages: 系统词 + 数据上下文 + 历史 + 当前问题。"""
    snapshot, news = await asyncio.gather(_market_snapshot(), _news_digest())
    ctx_parts = [snapshot, news]
    lowered = message.lower()
    if any(k in lowered for k in _SEARCH_INTENT):
        ctx_parts.append(await _web_search(message))
    context = "\n\n".join(p for p in ctx_parts if p)

    system = _SYSTEM
    # 模型本身不知道"现在", 注入当前北京时间
    now_cn = datetime.now(timezone(timedelta(hours=8)))
    system += f"\n\n当前时间: {now_cn:%Y-%m-%d %H:%M} (北京时间)"
    system += f"\n\n始终用{_lang_of(lang)}回答 (数据名、专有名词可保留原文)。"
    if context:
        system += f"\n\n以下是当前实时数据 (回答以此为准):\n{context}"

    msgs: list[dict] = [{"role": "system", "content": system}]
    # 历史最多 5 轮, 控制 token
    for h in (history or [])[-5:]:
        role = h.get("role")
        content = (h.get("content") or "").strip()
        if role in ("user", "assistant") and content:
            msgs.append({"role": role, "content": content})
    msgs.append({"role": "user", "content": message})
    return msgs


async def chat_stream(
    message: str,
    history: list[dict] | None = None,
    lang: str = "zh",
) -> AsyncGenerator[str, None]:
    """流式对话, 逐段 yield 文本增量。失败 yield 错误提示。"""
    if not config.deepseek_api_key:
        yield "AI 服务未配置, 请稍后再试。"
        return

    try:
        messages = await _build_messages(message, history, lang)
        async with httpx.AsyncClient(timeout=60) as client:
            async with client.stream(
                "POST",
                _API_URL,
                headers={"Authorization": f"Bearer {config.deepseek_api_key}"},
                json={
                    "model": _MODEL,
                    "messages": messages,
                    # 1.0 提多样性, 配合反模板 prompt 减少套路感
                    "temperature": 1.0,
                    "max_tokens": 1600,
                    "stream": True,
                },
            ) as resp:
                resp.raise_for_status()
                async for line in resp.aiter_lines():
                    if not line or not line.startswith("data: "):
                        continue
                    payload = line[6:].strip()
                    if payload == "[DONE]":
                        break
                    try:
                        delta = json.loads(payload)["choices"][0]["delta"]
                        piece = delta.get("content")
                        if piece:
                            yield piece
                    except (json.JSONDecodeError, KeyError, IndexError):
                        continue
    except Exception as exc:
        logger.warning("ai_chat_failed: %s", str(exc)[:200])
        yield _ERR_BUSY.get(lang, _ERR_BUSY["zh"])


# ---- K线技术分析 (AI 只解读后端算好的指标, 输出结构化 JSON) ----

_KLINE_SYSTEM = """你是资深的加密货币技术分析师「明策 AI」。只基于注入的 K线技术数据做技术面解读, 输出严格的 JSON 结构化分析报告。

铁律 (不可违反):
1. 所有数字必须来自注入的数据, 禁止编造数值、价格、日期、事件; 数据不足就降低置信度并说明。
2. 只讲技术面和市场结构; 不说本平台的负面内容。
3. 只输出 JSON, 不要输出任何 JSON 以外的文字、代码块标记或注释。

输出 JSON 结构 (字段必须齐全):
{
  "trend": {
    "direction": "bullish | bearish | neutral",
    "confidence": 0到100的整数,
    "ma_status": "均线系统状态一句话, 如: 短期多头排列/MA5金叉MA10/均线缠绕",
    "reason": "趋势判断依据, 1~2句"
  },
  "patterns": [
    {
      "name": "形态名, 如: 吞没形态/锤子线/双底/头肩底/连续阳线",
      "type": "反转 | 持续 | 中性",
      "validity": "高 | 中 | 低",
      "description": "一句话说明出现位置和含义"
    }
  ],
  "key_levels": {
    "supports": [数字数组, 强支撑位, 从近到远],
    "resistances": [数字数组, 强阻力位, 从近到远],
    "breakout": "关键突破点位及说明, 一句话",
    "description": "价位分析补充, 1~2句"
  },
  "volume": {
    "state": "放量 | 缩量 | 平量",
    "divergence": "顶背离 | 底背离 | 无",
    "description": "量价配合解读, 1~2句"
  },
  "signal": {
    "action": "buy | sell | hold",
    "stop_loss": "拟定止损位 (用注入数据中的关键位推导, 给具体数字)",
    "take_profit": "拟定目标止盈位 (具体数字)",
    "risks": ["风险提示列表, 2~4条"],
    "summary": "综合结论, 2~3句, 含置信度依据"
  }
}

分析要求:
- patterns 没有明显形态就给空数组, 不要硬凑。
- 支撑/阻力位从注入的区间高低点、布林带轨、整数关口推导, 给 1~3 个。
- action 判定规则 (不可违反):
  · 仅当 trend=bullish 且 confidence≥65 且出现明确多头信号 (短期均线多头排列 / MACD金叉 / 放量突破阻力位, 至少其一) 时, 才给 action=buy;
  · 仅当 trend=bearish 且 confidence≥65 且出现明确空头信号 (短期均线空头排列 / MACD死叉 / 放量跌破支撑位, 至少其一) 时, 才给 action=sell;
  · 其余情况一律 action=hold, 包括: 方向不明、置信度不足 65、趋势与信号相互矛盾、临近关键位但尚未有效突破/跌破;
  · trend 与 action 必须同向: trend=bearish 不得给 buy, trend=bullish 不得给 sell, trend=neutral 一律 hold。
- signal 方向一致性铁律 (以注入的"最新收盘"为基准价, 不可违反):
  · trend=bearish (看空): take_profit 必须低于最新收盘价, stop_loss 必须高于最新收盘价;
  · trend=bullish (看多): take_profit 必须高于最新收盘价, stop_loss 必须低于最新收盘价;
  · action=hold (观望) 时, stop_loss/take_profit 也要按 trend 方向给出, 作为"若按当前方向进场的参考位", 并在 summary 中说明是条件参考;
  · take_profit 与 stop_loss 的相对方向必须与 trend.direction 严格一致, 严禁反向。
- signal 是技术参考不是确定性预测, risks 必须包含止损失效或假突破等风险。
- 全部用简体中文。"""


def _to_float(value) -> float | None:
    """把 AI 返回的止盈/止损值 (可能是数字或带符号/单位的字符串) 转成 float。"""
    if value is None or isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        import re

        m = re.search(r"-?\d+(?:,\d{3})*(?:\.\d+)?", value)
        if m:
            try:
                return float(m.group(0).replace(",", ""))
            except ValueError:
                return None
    return None


def _enforce_signal_direction(report: dict, current_price: float | None) -> dict:
    """校验并修正 signal 的止盈/止损方向, 使其与 trend.direction 一致。

    LLM 可能"嘴上看空、手里给做多位"。以最新收盘价为基准做硬校验:
    - action 合法性: 非法值归一为 hold; trend=neutral 强制 hold;
      trend 与 action 反向 (bearish+buy / bullish+sell) 降级为 hold;
    - trend=bearish: take_profit 应低于现价、stop_loss 高于现价, 反则交换/置空;
    - trend=bullish: take_profit 应高于现价、stop_loss 低于现价, 反则交换/置空;
    - 两值同侧无法通过交换修正时, 剔除反向字段, 避免误导。
    """
    if current_price is None or current_price <= 0:
        return report
    signal = report.get("signal")
    if not isinstance(signal, dict):
        return report

    trend = report.get("trend") or {}
    direction = trend.get("direction")

    action = signal.get("action")
    if action not in ("buy", "sell", "hold"):
        if action is not None:
            logger.warning("ai_kline_action_normalized raw=%s", action)
        signal["action"] = "hold"
    elif direction == "neutral" and action != "hold":
        logger.warning("ai_kline_action_neutral_hold raw=%s", action)
        signal["action"] = "hold"
    elif direction == "bearish" and action == "buy":
        logger.warning("ai_kline_action_conflict %s/%s", direction, action)
        signal["action"] = "hold"
    elif direction == "bullish" and action == "sell":
        logger.warning("ai_kline_action_conflict %s/%s", direction, action)
        signal["action"] = "hold"

    if direction not in ("bullish", "bearish"):
        return report

    sl = _to_float(signal.get("stop_loss"))
    tp = _to_float(signal.get("take_profit"))
    if sl is None and tp is None:
        return report

    def _consistent(sl_v: float | None, tp_v: float | None) -> bool:
        if direction == "bullish":
            return (tp_v is None or tp_v > current_price) and (
                sl_v is None or sl_v < current_price
            )
        return (tp_v is None or tp_v < current_price) and (
            sl_v is None or sl_v > current_price
        )

    if _consistent(sl, tp):
        return report

    # 方向反了: 若两值都给出, 交换通常能修正 (LLM 常把多空两值写反)
    if sl is not None and tp is not None and _consistent(tp, sl):
        logger.warning("ai_kline_signal_swapped %s sl=%s tp=%s", direction, sl, tp)
        signal["stop_loss"], signal["take_profit"] = tp, sl
        return report

    # 单值反向或交换仍不一致: 剔除反向字段, 宁可不给也不给矛盾值
    fixed_sl = sl if (sl is None or _consistent(sl, None)) else None
    fixed_tp = tp if (tp is None or _consistent(None, tp)) else None
    if fixed_sl != sl or fixed_tp != tp:
        logger.warning("ai_kline_signal_pruned %s sl=%s tp=%s", direction, sl, tp)
    signal["stop_loss"] = fixed_sl
    signal["take_profit"] = fixed_tp
    return report


async def kline_analyze(
    data_block: str,
    symbol: str,
    bar: str,
    current_price: float | None = None,
) -> dict | None:
    """K线技术分析: 结构化 JSON 输出。失败返回 None。"""
    if not config.deepseek_api_key:
        return None
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            resp = await client.post(
                _API_URL,
                headers={"Authorization": f"Bearer {config.deepseek_api_key}"},
                json={
                    "model": _MODEL,
                    "messages": [
                        {"role": "system", "content": _KLINE_SYSTEM},
                        {"role": "user",
                         "content": f"请分析 {symbol} {bar} 周期:\n\n{data_block}"},
                    ],
                    "temperature": 0.5,
                    "max_tokens": 2000,
                    "response_format": {"type": "json_object"},
                },
            )
            resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        report = json.loads(text)
        return _enforce_signal_direction(report, current_price)
    except Exception as exc:
        logger.warning("ai_kline_failed: %s", str(exc)[:200])
        return None


# ---- 每日市场综述 (全用户共享, 按日期+语种缓存一次, 省 token) ----

_summary_cache: dict[tuple[str, str], str] = {}

_SUMMARY_SYSTEM = """你是资深的加密货币市场分析师「明策 AI」。只基于提供的实时数据写当日市场综述。

铁律 (不可违反):
1. 所有数字必须来自注入的数据, 禁止编造任何数值、日期、事件。
2. 不做价格预测, 不给买卖点位, 只解读数据含义、历史规律和结构关系。

写法:
- 像研报晨报: 一段总览定调, 再分 2~4 个要点展开 (情绪/资金/衍生品), 每个要点用数据支撑并讲清含义。
- 主动关联指标讲结构, 而不是逐条罗列数字。
- 用 markdown, 可用加粗和分点; 不要标题、日期、分割线, 直接写正文。
- 篇幅 250~400 字, 结尾一句风险提示。"""


async def daily_summary(lang: str = "zh") -> dict:
    """生成当日市场综述。同一语种一天只调一次 AI, 之后读缓存。
    返回 {date, text, cached}。失败时 text 为空串由前端隐藏卡片。"""
    from datetime import date

    today = date.today().isoformat()
    cache_key = (today, lang)
    if _summary_cache.get(cache_key):
        return {"date": today, "text": _summary_cache[cache_key], "cached": True}
    if not config.deepseek_api_key:
        return {"date": today, "text": "", "cached": False}

    context = await _market_snapshot()
    lang_name = _lang_of(lang)
    try:
        async with httpx.AsyncClient(timeout=90) as client:
            resp = await client.post(
                _API_URL,
                headers={"Authorization": f"Bearer {config.deepseek_api_key}"},
                json={
                    "model": _MODEL,
                    "messages": [
                        {"role": "system",
                         "content": _SUMMARY_SYSTEM + f"\n- 全文使用{lang_name}撰写。"},
                        {"role": "user",
                         "content": f"请根据以下实时数据写今日市场综述 (用{lang_name}):\n\n{context}"},
                    ],
                    "temperature": 0.6,
                    "max_tokens": 1200,
                },
            )
            resp.raise_for_status()
        text = resp.json()["choices"][0]["message"]["content"].strip()
        # 剥掉 AI 擅自加的标题/日期/分割线行, 避免和卡片头重复
        import re

        lines = [
            ln for ln in text.splitlines()
            if not re.match(r"^\s*(#{1,6}\s|[-*_]{3,}\s*$)", ln)
            and not re.match(r"^\s*每日?市场?综述", ln)
        ]
        text = "\n".join(lines).strip()
        if text:
            _summary_cache[cache_key] = text
            return {"date": today, "text": text, "cached": False}
    except Exception as exc:
        logger.warning("ai_daily_summary_failed: %s", str(exc)[:200])
    return {"date": today, "text": "", "cached": False}
