"""运营参数覆盖表 (后台「参数配置」页, 2026-10-08).

与 models.hk.HkConfig (hk_configs, 功能开关 key-value) 是两套东西:
那张表管模块开关; 这张表管运营数值参数 (费率/限额/限流),
env 是默认值兜底, 后台保存的值落这张表并覆盖进内存缓存, 即时生效.
"""
from __future__ import annotations

from sqlalchemy import Column, DateTime, String, Text

from models.hk import HkBase, utc_now


class HkParam(HkBase):
    __tablename__ = "hk_params"

    key = Column(String(64), primary_key=True)
    value = Column(Text, nullable=False)
    updated_by = Column(String(64), nullable=True)
    updated_at = Column(DateTime, default=utc_now, onupdate=utc_now)
