"""明策 hk FastAPI 入口. 精简自 okx backend: 只保留 auth/news/market/overview."""
from __future__ import annotations

import asyncio
import logging
from contextlib import asynccontextmanager
from datetime import timedelta

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import delete, select, text

from config import config
from database import SessionLocal, engine
from models.hk import HkBase, HkChatMessage, HkMessageReaction, utc_now
from routers import auth, chat, interaction, invite, market, news, overview
from routers.chat import CHAT_UPLOAD_DIR

logger = logging.getLogger(__name__)

# 老库 hk_chat_messages 已存在, create_all 不会加列: 幂等补列 (仅 PG 支持 IF NOT EXISTS)
_MSG_MIGRATIONS = (
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS msg_type VARCHAR(16) NOT NULL DEFAULT 'text'",
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS file_url VARCHAR(512)",
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS duration INTEGER",
)

# 消息留存: 服务端仅做中继, 7 天清理, 每 6h 一轮
RETENTION_DAYS = 7
RETENTION_INTERVAL_SEC = 6 * 3600


async def cleanup_old_messages() -> tuple[int, int]:
    """删除过期消息 + 其表情回应 + 磁盘文件; 返回 (消息数, 文件数)."""
    cutoff = utc_now() - timedelta(days=RETENTION_DAYS)
    async with SessionLocal() as db:
        old = (
            await db.scalars(
                select(HkChatMessage).where(HkChatMessage.created_at < cutoff)
            )
        ).all()
        if not old:
            return 0, 0
        ids = [m.id for m in old]
        files = 0
        for m in old:
            if m.file_url and m.file_url.startswith("/api/chat/files/"):
                name = m.file_url.rsplit("/", 1)[-1]
                try:
                    (CHAT_UPLOAD_DIR / name).unlink(missing_ok=True)
                    files += 1
                except OSError:
                    pass  # 孤儿文件尽力而为
        await db.execute(
            delete(HkMessageReaction).where(HkMessageReaction.message_id.in_(ids))
        )
        await db.execute(delete(HkChatMessage).where(HkChatMessage.id.in_(ids)))
        await db.commit()
        return len(ids), files


async def _retention_loop() -> None:
    while True:
        try:
            msgs, files = await cleanup_old_messages()
            if msgs or files:
                logger.info(
                    "chat_retention_cleanup",
                    extra={"messages": msgs, "files": files},
                )
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("chat_retention_error")
        await asyncio.sleep(RETENTION_INTERVAL_SEC)


@asynccontextmanager
async def lifespan(app: FastAPI):
    # hk 自有表不存在则建 (共享表由 okx 侧 Alembic 管理, hk 不建不改)
    async with engine.begin() as conn:
        await conn.run_sync(HkBase.metadata.create_all)
        # 本地 sqlite 开发库无 okx 共享表, 建空表便于联调; 生产共享库跳过
        if config.database_url.startswith("sqlite"):
            from models.shared import SharedBase

            await conn.run_sync(SharedBase.metadata.create_all)
        else:
            for stmt in _MSG_MIGRATIONS:  # 生产 PG: 老表补新列
                await conn.execute(text(stmt))
    CHAT_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    retention = asyncio.create_task(_retention_loop())
    yield
    retention.cancel()
    try:
        await retention
    except asyncio.CancelledError:
        pass
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
app.include_router(invite.router, prefix="/api")
app.include_router(news.router, prefix="/api")
app.include_router(interaction.router, prefix="/api")
app.include_router(market.router, prefix="/api")
app.include_router(overview.router, prefix="/api")
app.include_router(chat.router, prefix="/api")


@app.get("/health")
async def health():
    return {"status": "ok"}
