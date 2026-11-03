"""AI 助手接口: 市场对话 (SSE 流式) + K线技术分析 + 每日综述。

POST /ai/market-chat   body {message, history?, lang} → text/event-stream
GET  /ai/kline-analysis?inst_id&bar → 五维度结构化报告 (按周期缓存)
GET  /ai/daily-summary?lang → 当日市场综述 (按日缓存)
全部需登录 (DeepSeek token 计费, 防匿名刷)。
"""
from __future__ import annotations

import json

from fastapi import APIRouter, Depends, HTTPException, Query, status
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field

from models.hk import HkUser
from routers.market import _okx_get
from services import ai_kline, ai_service, auth_service

router = APIRouter(prefix="/ai", tags=["AI 助手"])

_BARS = tuple(ai_kline._BAR_TTL)  # 合法周期白名单


@router.get("/daily-summary")
async def get_daily_summary(
    lang: str = Query("zh"),
    user: HkUser = Depends(auth_service.get_current_user),
):
    """当日 AI 市场综述。同 (日, 语种) 缓存, 全用户共享一次生成。"""
    return await ai_service.daily_summary(lang)


@router.get("/kline-analysis")
async def kline_analysis(
    inst_id: str = Query("BTC-USDT", max_length=32),
    bar: str = Query("1D"),
    user: HkUser = Depends(auth_service.get_current_user),
):
    """AI K线技术分析: 后端算指标注入, AI 出结构化 JSON; 按周期缓存。"""
    if bar not in _BARS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不支持的周期")
    cached = ai_kline.cache_get(inst_id, bar)
    if cached:
        return {"ok": True, "cached": True, "report": cached}

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
    return {"ok": True, "cached": False, "report": report}


class ChatReq(BaseModel):
    message: str = Field(max_length=2000)
    history: list[dict] | None = None
    lang: str = "zh"


@router.post("/market-chat")
async def market_chat(
    req: ChatReq,
    user: HkUser = Depends(auth_service.get_current_user),
):
    """AI 市场对话, SSE 流式: 每条 data: {"delta": "..."}, 结束 data: [DONE]."""
    if not req.message.strip():
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "消息为空")

    async def gen():
        async for piece in ai_service.chat_stream(req.message, req.history, req.lang):
            yield f"data: {json.dumps({'delta': piece}, ensure_ascii=False)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
