"""AI 助手接口: 市场对话 (SSE 流式) + K线技术分析 + 每日综述。

POST /ai/market-chat   body {message, history?, lang} → text/event-stream
GET  /ai/kline-analysis?inst_id&bar → 五维度结构化报告 (按周期缓存)
GET  /ai/daily-summary?lang → 当日市场综述 (按日缓存)
GET  /ai/quota → 试用配额状态 (端上展示剩余天数/次数)
全部需登录 (DeepSeek token 计费, 防匿名刷)。
试用限制: 注册日起 ai_trial_days 天, 期内每天 ai_trial_daily_limit 次,
三接口共用, 缓存命中不计次; 超限 403 trial_expired / 429 daily_limit
(后台参数配置 ai_trial_* 可调, ai_trial_enabled=0 完全开放)。
"""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkUser
from routers.market import _okx_get
from services import ai_kline, ai_quota_service, ai_service, auth_service

router = APIRouter(prefix="/ai", tags=["AI 助手"])

_BARS = tuple(ai_kline._BAR_TTL)  # 合法周期白名单


@router.get("/quota")
async def ai_quota(
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """试用配额状态: 剩余天数/今日剩余次数. 不校验不抛错不计次。"""
    return await ai_quota_service.quota_view(db, user)


@router.get("/daily-summary")
async def get_daily_summary(
    lang: str = Query("zh"),
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """当日 AI 市场综述。同 (日, 语种) 缓存, 全用户共享一次生成。"""
    quota = await ai_quota_service.check(db, user)
    res = await ai_service.daily_summary(lang)
    if not res.get("cached"):
        await ai_quota_service.consume(db, quota)  # 缓存命中不计次
    return res


@router.get("/kline-analysis")
async def kline_analysis(
    inst_id: str = Query("BTC-USDT", max_length=32),
    bar: str = Query("1D"),
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """AI K线技术分析: 后端算指标注入, AI 出结构化 JSON; 按周期缓存。"""
    if bar not in _BARS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不支持的周期")
    quota = await ai_quota_service.check(db, user)
    trial = (
        ai_quota_service.trial_state(user, quota.count)
        if quota is not None
        else None
    )
    cached = ai_kline.cache_get(inst_id, bar)
    if cached:
        # 缓存命中: 不计次
        return {"ok": True, "cached": True, "report": cached, "trial": trial}

    try:
        raw = await _okx_get(
            "/api/v5/market/candles",
            {"instId": inst_id, "bar": bar, "limit": "300"},
        )
    except Exception as exc:
        raise HTTPException(status.HTTP_502_BAD_GATEWAY, f"OKX 上游错误: {exc}") from exc
    rows = raw.get("data") or []
    # OKX 新在前数组 → 升序 dict (build_snapshot 需要)
    candles = [
        {
            "open": float(r[1]), "high": float(r[2]), "low": float(r[3]),
            "close": float(r[4]), "vol": float(r[5]),
        }
        for r in reversed(rows)
        if len(r) >= 6
    ]
    block, last_price = ai_kline.build_snapshot(candles, inst_id, bar)
    if not block:
        return {"ok": False, "error": "insufficient_data"}

    report = await ai_service.kline_analyze(block, inst_id, bar, current_price=last_price)
    if not report:
        return {"ok": False, "error": "ai_unavailable"}
    ai_kline.cache_put(inst_id, bar, report)
    await ai_quota_service.consume(db, quota)  # 新生成才计次
    if trial is not None and quota is not None:
        trial = ai_quota_service.trial_state(user, quota.count)
    return {"ok": True, "cached": False, "report": report, "trial": trial}


class ChatReq(BaseModel):
    message: str = Field(max_length=2000)
    history: list[dict] | None = None
    lang: str = "zh"


@router.post("/market-chat")
async def market_chat(
    req: ChatReq,
    user: HkUser = Depends(auth_service.get_current_user),
    db: AsyncSession = Depends(get_db),
):
    """AI 市场对话, SSE 流式: 每条 data: {"delta": "..."}, 结束 data: [DONE]."""
    if not req.message.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "消息为空")
    quota = await ai_quota_service.check(db, user)
    await ai_quota_service.consume(db, quota)  # 对话无缓存, 每次都计

    async def gen():
        async for piece in ai_service.chat_stream(req.message, req.history, req.lang):
            yield f"data: {json.dumps({'delta': piece}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
