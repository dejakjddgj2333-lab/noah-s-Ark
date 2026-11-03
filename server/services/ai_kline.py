"""K线技术分析:拉 OKX K线 → 后端算指标 → 生成紧凑数据块供 AI 解读。

原则:数字全部由后端算好注入,AI 只解读不计算,防编造。
结果按 K线周期缓存,同一周期内只生成一次,省 token。
"""

from __future__ import annotations

import time

# bar → 缓存秒数(≈一根 K线周期,新 K线出来后重新生成)
_BAR_TTL = {
    "1m": 60, "3m": 180, "5m": 300, "15m": 900, "30m": 1800,
    "1H": 3600, "2H": 7200, "4H": 14400,
    "6H": 21600, "12H": 43200, "1D": 86400, "1W": 604800,
}

# key → (过期时间戳, 报告 dict)
_cache: dict[str, tuple[float, dict]] = {}


def cache_get(inst_id: str, bar: str) -> dict | None:
    ent = _cache.get(f"{inst_id}:{bar}")
    if ent and ent[0] > time.time():
        return ent[1]
    return None


def cache_put(inst_id: str, bar: str, report: dict) -> None:
    ttl = _BAR_TTL.get(bar, 1800)
    _cache[f"{inst_id}:{bar}"] = (time.time() + ttl, report)
    # 防内存膨胀:顺手清过期项
    if len(_cache) > 200:
        now = time.time()
        for k in [k for k, v in _cache.items() if v[0] <= now]:
            del _cache[k]


# ---------- 指标计算(纯 Python,无三方依赖) ----------

def _sma(vals: list[float], n: int) -> float | None:
    if len(vals) < n:
        return None
    return sum(vals[-n:]) / n


def _ema_series(vals: list[float], n: int) -> list[float]:
    if not vals:
        return []
    k = 2 / (n + 1)
    out = [vals[0]]
    for v in vals[1:]:
        out.append(v * k + out[-1] * (1 - k))
    return out


def _rsi(closes: list[float], n: int = 14) -> float | None:
    if len(closes) < n + 1:
        return None
    gains, losses = 0.0, 0.0
    for i in range(-n, 0):
        d = closes[i] - closes[i - 1]
        if d >= 0:
            gains += d
        else:
            losses -= d
    if losses == 0:
        return 100.0
    rs = gains / losses
    return 100 - 100 / (1 + rs)


def _macd(closes: list[float]) -> tuple[float, float, float] | None:
    """返回 (DIF, DEA, 柱)。柱>0 多头动能。"""
    if len(closes) < 35:
        return None
    e12 = _ema_series(closes, 12)
    e26 = _ema_series(closes, 26)
    dif = [a - b for a, b in zip(e12, e26)]
    dea = _ema_series(dif, 9)
    return dif[-1], dea[-1], (dif[-1] - dea[-1]) * 2


def _kdj(highs: list[float], lows: list[float], closes: list[float],
         n: int = 9) -> tuple[float, float, float] | None:
    if len(closes) < n:
        return None
    k, d = 50.0, 50.0
    for i in range(n - 1, len(closes)):
        h = max(highs[i - n + 1:i + 1])
        lo = min(lows[i - n + 1:i + 1])
        rsv = 50.0 if h == lo else (closes[i] - lo) / (h - lo) * 100
        k = k * 2 / 3 + rsv / 3
        d = d * 2 / 3 + k / 3
    j = 3 * k - 2 * d
    return k, d, j


def _boll(closes: list[float], n: int = 20, mult: float = 2.0
          ) -> tuple[float, float, float] | None:
    """返回 (上轨, 中轨, 下轨)。"""
    if len(closes) < n:
        return None
    seg = closes[-n:]
    mid = sum(seg) / n
    var = sum((c - mid) ** 2 for c in seg) / n
    sd = var ** 0.5
    return mid + mult * sd, mid, mid - mult * sd


def _fmt(v: float | None, digits: int = 4) -> str:
    if v is None:
        return "暂无"
    if abs(v) >= 1000:
        return f"{v:,.2f}"
    if abs(v) >= 1:
        return f"{v:.4f}".rstrip("0").rstrip(".")
    return f"{v:.{digits}g}"


def build_snapshot(candles: list[dict], inst_id: str, bar: str) -> tuple[str, float | None]:
    """把 K线+指标压成注入 AI 的紧凑文本块。

    返回 (注入文本, 最新收盘价)。数据不足时返回 ("", None)。
    最新收盘价用于调用方对 AI 产出的止盈/止损做方向一致性校验。
    """
    rows = [c for c in candles if c.get("close") is not None]
    if len(rows) < 30:
        return "", None
    closes = [float(c["close"]) for c in rows]
    highs = [float(c["high"]) for c in rows]
    lows = [float(c["low"]) for c in rows]
    opens = [float(c["open"]) for c in rows]
    vols = [float(c["vol"]) for c in rows if c.get("vol") is not None]

    last = closes[-1]
    lines: list[str] = [
        f"【{inst_id} {bar} K线技术数据】(共{len(rows)}根,最新收盘 {_fmt(last, 2)};"
        f"注意:最后一根为当前未收盘K线,数据仍在变动)"
    ]

    # 均线
    ma5, ma10, ma20 = _sma(closes, 5), _sma(closes, 10), _sma(closes, 20)
    ma7, ma25, ma99 = _sma(closes, 7), _sma(closes, 25), _sma(closes, 99)
    lines.append(
        f"均线: MA5 {_fmt(ma5, 2)} / MA10 {_fmt(ma10, 2)} / MA20 {_fmt(ma20, 2)}"
        f" / MA99 {_fmt(ma99, 2)};"
        f"现价相对 MA5 {_rel(last, ma5)}、MA20 {_rel(last, ma20)}、MA99 {_rel(last, ma99)}"
    )
    # 排列状态(短期组 + 长期参照)
    if ma5 and ma10 and ma20:
        if ma5 > ma10 > ma20:
            lines.append("短期均线多头排列(MA5>MA10>MA20)")
        elif ma5 < ma10 < ma20:
            lines.append("短期均线空头排列(MA5<MA10<MA20)")
        else:
            lines.append("短期均线缠绕")
    if ma7 and ma25 and ma99:
        if ma7 > ma25 > ma99:
            lines.append("中长期均线多头排列(MA7>MA25>MA99)")
        elif ma7 < ma25 < ma99:
            lines.append("中长期均线空头排列(MA7<MA25<MA99)")

    m = _macd(closes)
    if m:
        dif, dea, hist = m
        cross = "金叉" if dif > dea else "死叉"
        lines.append(
            f"MACD: DIF {_fmt(dif)} / DEA {_fmt(dea)} / 柱 {_fmt(hist)};{cross}状态"
        )
    rsi = _rsi(closes)
    if rsi is not None:
        zone = "超买区(>70)" if rsi > 70 else "超卖区(<30)" if rsi < 30 else "中性区"
        lines.append(f"RSI14: {rsi:.1f},{zone}")
    kdj = _kdj(highs, lows, closes)
    if kdj:
        lines.append(f"KDJ: K {kdj[0]:.1f} / D {kdj[1]:.1f} / J {kdj[2]:.1f}")
    boll = _boll(closes)
    if boll:
        up, mid, lo = boll
        width = (up - lo) / mid * 100 if mid else 0
        pos = (last - lo) / (up - lo) * 100 if up > lo else 50
        lines.append(
            f"布林带(20,2): 上 {_fmt(up, 2)} / 中 {_fmt(mid, 2)} / 下 {_fmt(lo, 2)};"
            f"带宽 {width:.1f}%,现价处于带内 {pos:.0f}% 位置"
        )

    # 量能
    if len(vols) >= 21:
        v_ratio = vols[-1] / (sum(vols[-21:-1]) / 20)
        lines.append(f"量能: 最新量 {vols[-1]:.4g},20周期均量的 {v_ratio:.2f} 倍")

    # 区间结构:近 30/全部 高低点 + 现价位置
    n30 = min(30, len(rows))
    hi30, lo30 = max(highs[-n30:]), min(lows[-n30:])
    hi_all, lo_all = max(highs), min(lows)
    pos30 = (last - lo30) / (hi30 - lo30) * 100 if hi30 > lo30 else 50
    lines.append(
        f"近{n30}根区间: {_fmt(lo30, 2)} ~ {_fmt(hi30, 2)},现价处于 {pos30:.0f}% 位置;"
        f"全区间极值 {_fmt(lo_all, 2)} ~ {_fmt(hi_all, 2)}"
    )

    # 近10根K线明细(开高低收+量),供 AI 识别形态
    detail = []
    for i in range(-10, 0):
        detail.append(
            f"  [{i}] O{_fmt(opens[i], 2)} H{_fmt(highs[i], 2)} "
            f"L{_fmt(lows[i], 2)} C{_fmt(closes[i], 2)}"
            + (f" V{vols[i]:.4g}" if i >= -len(vols) else "")
        )
    lines.append("近10根K线明细(旧→新):\n" + "\n".join(detail))

    # 近5根形态摘要(实体/振幅/上下影),辅助判断吞没/锤子/十字星
    desc = []
    for i in range(-5, 0):
        o, c, h, lo = opens[i], closes[i], highs[i], lows[i]
        body = (c - o) / o * 100 if o else 0
        rng = (h - lo) / o * 100 if o else 0
        upper = (h - max(o, c)) / o * 100 if o else 0
        lower = (min(o, c) - lo) / o * 100 if o else 0
        d = "阳" if body >= 0 else "阴"
        desc.append(
            f"{d}线 实体{body:+.2f}% 振幅{rng:.2f}% "
            f"上影{upper:.2f}% 下影{lower:.2f}%"
        )
    lines.append("近5根形态:\n" + "\n".join("  " + s for s in desc))

    return "\n".join(lines), last


def _rel(price: float, ma: float | None) -> str:
    if not ma:
        return "暂无"
    return f"{'+' if price >= ma else ''}{(price - ma) / ma * 100:.2f}%"
