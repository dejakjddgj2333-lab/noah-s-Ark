"""自选股模型. 每用户一行一个交易对, 多端同步."""
from __future__ import annotations

from datetime import datetime

from sqlalchemy import Column, DateTime, ForeignKey, Integer, String, UniqueConstraint

from models.hk import HkBase, utc_now


class HkWatchlist(HkBase):
    __tablename__ = "hk_watchlist"
    __table_args__ = (
        UniqueConstraint("user_id", "inst_id", name="uq_hk_watchlist_user_inst"),
    )

    id = Column(Integer, primary_key=True, autoincrement=True)
    user_id = Column(Integer, ForeignKey("hk_users.id"), nullable=False, index=True)
    inst_id = Column(String(32), nullable=False)  # OKX 格式: BTC-USDT / BTC-USDT-SWAP
    created_at = Column(DateTime, default=utc_now)
