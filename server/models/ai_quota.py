"""AI 功能试用配额表: 每用户一行, 按 UTC 日计数.

试用期以注册日 (hk_users.created_at) 起算, 天数/每日次数/总开关走 param_service:
ai_trial_enabled / ai_trial_days / ai_trial_daily_limit (后台参数配置可改).
K线分析/市场对话/每日综述三个接口共用每日次数; 缓存命中不计次 (不入这表).
"""
from __future__ import annotations

from sqlalchemy import Column, Date, Integer

from models.hk import HkBase


class HkAiQuota(HkBase):
    __tablename__ = "hk_ai_quota"

    user_id = Column(Integer, primary_key=True)
    day = Column(Date, nullable=False)  # 当前计数所属日 (UTC)
    count = Column(Integer, nullable=False, default=0)
