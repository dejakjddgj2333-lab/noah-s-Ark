"""数据库引擎与会话. 共享库: hk 只读 okx 的资讯/行情表, hk_ 前缀表自持."""
from __future__ import annotations

from sqlalchemy.ext.asyncio import (
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from config import config

engine = create_async_engine(config.database_url, pool_pre_ping=True)
SessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncSession:  # FastAPI dependency
    async with SessionLocal() as session:
        yield session
