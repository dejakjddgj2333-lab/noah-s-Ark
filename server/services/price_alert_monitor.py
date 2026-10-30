"""行情预警监测: 定时扫未触发预警, 拿最新价判断触发并多渠道推送.

渠道: APNs (App 离线推送) + 邮件 (SMTP, 发到注册邮箱, 覆盖 PC/安卓等无 APNs 端).
价格源: Binance 公开 REST GET /api/v3/ticker/price (无需鉴权).
symbol 统一按 USDT 永续/现货对查询: 已含 USDT 则不重复拼.
"""
from __future__ import annotations

from collections import defaultdict

import httpx
import structlog
from sqlalchemy import select

from database import SessionLocal
from models.hk import HkPriceAlert, HkUser
from services import email_service, push_service

logger = structlog.get_logger("hk.price_alert")

_TICKER_URL = "https://api.binance.com/api/v3/ticker/price"


def _fmt(v: float) -> str:
    """价格格式化: 大数两位带千分位, 小数保留更多有效位 (最多 8 位)."""
    if v >= 1000:
        return f"{v:,.2f}"
    return f"{v:.8g}"


def _pair(symbol: str) -> str:
    """交易对查询名: 已含 USDT 直接用, 否则拼 USDT."""
    return symbol if symbol.endswith("USDT") else f"{symbol}USDT"


async def _fetch_price(symbol: str) -> float | None:
    """拿单币最新价; 网络/解析失败返回 None (调用方跳过该 symbol)."""
    try:
        async with httpx.AsyncClient(timeout=10) as client:
            r = await client.get(_TICKER_URL, params={"symbol": _pair(symbol)})
            r.raise_for_status()
            return float(r.json()["price"])
    except Exception as exc:
        logger.warning("price_fetch_failed", symbol=symbol, err=str(exc)[:200])
        return None


async def fetch_price(symbol: str) -> float | None:
    """拿单币最新价 (供创建百分比预警时取基准价); 失败返回 None."""
    return await _fetch_price(symbol)


def _check_hit(alert: HkPriceAlert, price: float) -> tuple[bool, str]:
    """命中判定 + 推送正文. 返回 (是否命中, body)."""
    if (alert.alert_type or "price") == "percent":
        base = alert.baseline_price or 0
        pct = alert.percent or 0
        if base <= 0 or pct <= 0:
            return False, ""
        change = (price - base) / base * 100
        hit = (alert.direction == "up" and change >= pct) or (
            alert.direction == "down" and change <= -pct
        )
        if not hit:
            return False, ""
        verb = "涨" if change >= 0 else "跌"
        body = (
            f"{alert.symbol} 较基准价 {_fmt(base)} 已{verb} "
            f"{abs(change):.2f}%, 现价 {_fmt(price)}"
        )
        return True, body
    hit = (alert.direction == "up" and price >= alert.target_price) or (
        alert.direction == "down" and price <= alert.target_price
    )
    if not hit:
        return False, ""
    if alert.direction == "up":
        body = (
            f"{alert.symbol} 已涨至 {_fmt(price)}, "
            f"突破预警价 {_fmt(alert.target_price)}"
        )
    else:
        body = (
            f"{alert.symbol} 已跌至 {_fmt(price)}, "
            f"跌破预警价 {_fmt(alert.target_price)}"
        )
    return True, body


async def check_alerts() -> None:
    """扫所有未触发预警, 按 symbol 分组查一次价, 命中即推送并标记."""
    async with SessionLocal() as db:
        result = await db.execute(
            select(HkPriceAlert).where(HkPriceAlert.triggered.is_(False))
        )
        alerts = result.scalars().all()
        if not alerts:
            return

        by_symbol: dict[str, list[HkPriceAlert]] = defaultdict(list)
        for a in alerts:
            by_symbol[a.symbol].append(a)

        changed = False
        for symbol, rows in by_symbol.items():
            price = await _fetch_price(symbol)
            if price is None:
                continue  # 该 symbol 查价失败, 跳过不影响其它
            for alert in rows:
                hit, body = _check_hit(alert, price)
                if not hit:
                    continue
                alert.triggered = True
                changed = True
                title = f"{symbol} 价格预警"
                await push_service.push_if_offline(
                    db,
                    alert.user_id,
                    title,
                    body,
                    {"type": "price_alert", "symbol": symbol},
                )
                # 邮件渠道: 注册邮箱直达, 覆盖 PC 网页/安卓等无 APNs 端
                user = await db.get(HkUser, alert.user_id)
                if user is not None and user.email:
                    ok = await email_service.send_email(
                        user.email,
                        f"【明策】{title}",
                        f"{body}\n\n登录终端查看行情: https://mingcevip.com\n"
                        "本邮件由行情预警触发, 预警已自动关闭, 如需继续监控请重新设置。",
                    )
                    if not ok:
                        logger.warning(
                            "alert_email_failed",
                            user_id=alert.user_id,
                            symbol=symbol,
                        )
        if changed:
            await db.commit()
