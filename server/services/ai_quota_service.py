"""AI 功能试用配额: 注册日起 N 天免费, 期内每天 M 次, 超限锁死.

- 三个 AI 接口 (K线分析/市场对话/每日综述) 共用每日次数;
- 缓存命中不计次: 调用方只在"新生成"时 consume;
- 超限: 试用到期 403 trial_expired, 当日次数用尽 429 daily_limit;
- ai_trial_enabled=0 完全开放 (不校验不计次, check 返回 None).
"""
from __future__ import annotations

from datetime import date, datetime, timezone

from fastapi import HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.ai_quota import HkAiQuota
from models.hk import HkUser
from services import param_service


def _today() -> date:
    return datetime.now(timezone.utc).date()


def _days() -> int:
    return int(param_service.get("ai_trial_days"))


def _limit() -> int:
    return int(param_service.get("ai_trial_daily_limit"))


def enabled() -> bool:
    return int(param_service.get("ai_trial_enabled")) == 1


def trial_state(user: HkUser, used_today: int) -> dict:
    """试用状态快照 (端上展示用): days_left=0 即已到期锁死."""
    days = _days()
    start = user.created_at.date() if user.created_at else _today()
    elapsed = (_today() - start).days
    days_left = max(days - elapsed, 0)
    return {
        "enabled": True,
        "trial_days": days,
        "daily_limit": _limit(),
        "days_left": days_left,
        "remaining_today": max(_limit() - used_today, 0),
        "expired": days_left <= 0,
    }


async def check(db: AsyncSession, user: HkUser) -> HkAiQuota | None:
    """校验配额并返回当日计数行 (供 consume 计次). 超限抛 403/429.

    到期/超次一律拦截 (缓存命中也不放行); 通过后才由调用方决定是否计次.
    开关关闭返回 None (完全开放).
    """
    if not enabled():
        return None
    start = user.created_at.date() if user.created_at else _today()
    if (_today() - start).days >= _days():
        raise HTTPException(status.HTTP_403_FORBIDDEN, "trial_expired")
    row = (
        await db.execute(
            select(HkAiQuota).where(HkAiQuota.user_id == user.id)
        )
    ).scalar_one_or_none()
    if row is not None and row.day == _today() and row.count >= _limit():
        raise HTTPException(status.HTTP_429_TOO_MANY_REQUESTS, "daily_limit")
    # 归一化到"今日行": 新用户建行, 跨天重置 (flush 不入库, 由调用方 commit)
    if row is None:
        row = HkAiQuota(user_id=user.id, day=_today(), count=0)
        db.add(row)
        await db.flush()
    elif row.day != _today():
        row.day = _today()
        row.count = 0
    return row


async def consume(db: AsyncSession, row: HkAiQuota | None) -> None:
    """新生成一次计一次 (缓存命中不调)."""
    if row is None:
        return
    row.count += 1
    await db.commit()


async def quota_view(db: AsyncSession, user: HkUser) -> dict:
    """GET /ai/quota: 端上展示剩余天数/次数, 不校验不抛错不计次."""
    if not enabled():
        return {"enabled": False}
    row = (
        await db.execute(
            select(HkAiQuota).where(HkAiQuota.user_id == user.id)
        )
    ).scalar_one_or_none()
    used = row.count if row is not None and row.day == _today() else 0
    return trial_state(user, used)
