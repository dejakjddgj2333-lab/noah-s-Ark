"""明策 hk FastAPI 入口. 精简自 okx backend: 只保留 auth/news/market/overview."""
from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from config import config
from database import engine
from models.hk import HkBase
from routers import auth, market, news, overview


@asynccontextmanager
async def lifespan(app: FastAPI):
    # hk 自有表不存在则建 (共享表由 okx 侧 Alembic 管理, hk 不建不改)
    async with engine.begin() as conn:
        await conn.run_sync(HkBase.metadata.create_all)
        # 本地 sqlite 开发库无 okx 共享表, 建空表便于联调; 生产共享库跳过
        if config.database_url.startswith("sqlite"):
            from models.shared import SharedBase

            await conn.run_sync(SharedBase.metadata.create_all)
    yield
    await engine.dispose()


app = FastAPI(title="明策 MINGCE API", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=list(config.cors_origins),
    # 本地开发: flutter web / http.server 端口不固定, 放行任意 localhost/127.0.0.1 端口
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router, prefix="/api")
app.include_router(news.router, prefix="/api")
app.include_router(market.router, prefix="/api")
app.include_router(overview.router, prefix="/api")


@app.get("/health")
async def health():
    return {"status": "ok"}
