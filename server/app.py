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
from routers import (
    admin_deposit,
    admin_products,
    admin_rbac,
    admin_sweep,
    admin_users,
    admin_withdrawals,
    auth,
    chat,
    deposit,
    interaction,
    invite,
    market,
    news,
    orders,
    overview,
    products,
    settlements,
    team,
    vip,
    withdrawals,
)
from routers.chat import CHAT_UPLOAD_DIR

logger = logging.getLogger(__name__)

# 老库 hk_chat_messages 已存在, create_all 不会加列: 幂等补列 (仅 PG 支持 IF NOT EXISTS)
_MSG_MIGRATIONS = (
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS msg_type VARCHAR(16) NOT NULL DEFAULT 'text'",
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS file_url VARCHAR(512)",
    "ALTER TABLE hk_chat_messages ADD COLUMN IF NOT EXISTS duration INTEGER",
    "ALTER TABLE hk_users ADD COLUMN IF NOT EXISTS nickname VARCHAR(32)",
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


async def _news_collect_loop() -> None:
    """资讯采集常驻循环 (hk 接管, 两项目分离准备). 启动 30s 后首轮."""
    from services.news_collector import run_collect

    await asyncio.sleep(30)  # 启动先稳数据库连接
    while True:
        try:
            n = await run_collect()
            if n:
                logger.info("news_collect_run", extra={"inserted": n})
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("news_collect_error")
        await asyncio.sleep(config.news_collect_interval_sec)


# hk 表新增列的轻量迁移 (create_all 不会给已存在表加列; 重复执行仅报列已存在, 忽略)
_MIGRATIONS = [
    ("hk_orders", "product_name", "VARCHAR(64)"),
    ("hk_orders", "base_daily_rate", "NUMERIC(10,6)"),
    ("hk_orders", "duration_days", "INTEGER"),
    ("hk_orders", "return_method", "VARCHAR(16)"),
    ("hk_orders", "vip_level", "INTEGER"),
    ("hk_orders", "lock_bonus_rate", "NUMERIC(10,6)"),
    ("hk_orders", "rule_version", "VARCHAR(16)"),
    ("hk_orders", "expires_at", "TIMESTAMP"),
    ("hk_orders", "settled_periods", "INTEGER"),
    ("hk_orders", "next_settle_at", "TIMESTAMP"),
    ("hk_withdrawals", "processed_by", "VARCHAR(32)"),
    ("hk_users", "role_id", "INTEGER"),
    ("hk_withdrawals", "idempotency_key", "VARCHAR(64)"),
    # 注意: 生产为 PostgreSQL, 无 DATETIME 类型, 须用 TIMESTAMP (MySQL/SQLite 亦兼容)
    ("hk_settlement_records", "due_at", "TIMESTAMP"),
    ("hk_commission_records", "base_amount", "NUMERIC(18, 2) DEFAULT 0"),
    ("hk_commission_records", "due_at", "TIMESTAMP"),
    ("hk_commission_records", "status", "VARCHAR(16) DEFAULT 'settled'"),
    ("hk_orders", "team_level", "INTEGER"),
    ("hk_email_codes", "attempts", "INTEGER DEFAULT 0"),
    # 安全设置: 资金密码 / 谷歌验证 / 防钓鱼码
    ("hk_users", "fund_password_hash", "VARCHAR(128)"),
    ("hk_users", "totp_secret", "VARCHAR(64)"),
    ("hk_users", "anti_phishing_code", "VARCHAR(32)"),
]


async def _migrate() -> None:
    # 新增列无法用 ADD COLUMN 附带 UNIQUE (sqlite 不支持), 唯一索引单独建
    _INDEXES = [
        # 幂等键唯一约束升级为 (user_id, idempotency_key): 先删旧的全局唯一索引
        "DROP INDEX IF EXISTS uq_hk_withdrawals_idem",
        "CREATE UNIQUE INDEX IF NOT EXISTS uq_hk_withdrawals_user_idem "
        "ON hk_withdrawals (user_id, idempotency_key)",
    ]
    # 每条独立事务: PG 单事务内一条失败会中止全部, "列已存在" 会殃及后续新列
    for table, column, col_type in _MIGRATIONS:
        try:
            async with engine.begin() as conn:
                await conn.execute(
                    text(f"ALTER TABLE {table} ADD COLUMN {column} {col_type}")
                )
        except Exception:
            pass  # 列已存在, 跳过
    for ddl in _INDEXES:
        try:
            async with engine.begin() as conn:
                await conn.execute(text(ddl))
        except Exception:
            pass  # 索引已存在或表尚未建, 跳过
    # 列类型变更 (PG): sqlite 动态类型无需处理
    try:
        async with engine.begin() as conn:
            await conn.execute(text(
                "ALTER TABLE hk_settlement_records ALTER COLUMN period_days "
                "TYPE NUMERIC(10, 6)"
            ))
    except Exception:
        pass  # 已是目标类型或不支持该语法, 跳过


@asynccontextmanager
async def lifespan(app: FastAPI):
    # 启动安全自检
    import logging

    logger = logging.getLogger("hk.security")
    if "*" in config.cors_origins:
        logger.warning("[安全] CORS 允许任意来源 (*), 生产环境应收窄为指定域名")
    if not config.admin_usernames:
        logger.warning("[安全] ADMIN_USERNAMES 为空, 后台接口 /api/admin/* 无人可访问")
    if config.secret_key in ("dev-only-change-me", ""):
        logger.warning("[安全] SECRET_KEY 为默认值, 生产环境必须设置强随机密钥")

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
    collector = None
    if config.news_collect_enabled and not config.database_url.startswith("sqlite"):
        collector = asyncio.create_task(_news_collect_loop())
    # HL 大额成交流: 常驻 (巨鲸异动固定用免费源, 比 CoinGlass whale-alert 全);
    # 爆仓 WS 聚合仅免费数据源模式需要 (coinglass 模式爆仓走 API 透传).
    from services import hl_whale

    market_tasks: list[asyncio.Task] = [hl_whale.start()]
    if config.market_data_source.lower() != "coinglass":
        from services import liq_aggregator

        market_tasks += liq_aggregator.start()
    await _migrate()
    # RBAC: 预置角色 upsert + ADMIN_USERNAMES 自动绑超管
    async with SessionLocal() as db:
        from services import admin_service as _admin_svc

        await _admin_svc.seed_roles(db)
    # 充值扫链监听 (自动到账); 测试可设 DEPOSIT_MONITOR_ENABLED=false 关闭
    monitor_task = None
    if config.deposit_monitor_enabled:
        from services import deposit_monitor

        monitor_task = asyncio.create_task(deposit_monitor.run_forever())
    # 结算引擎 (产品收益/佣金/到期返本); 测试可设 SETTLEMENT_ENABLED=false 关闭
    settle_task = None
    if config.settlement_enabled:
        from services import settlement_service

        settle_task = asyncio.create_task(settlement_service.run_forever())
    yield
    retention.cancel()
    if collector is not None:
        collector.cancel()
        try:
            await collector
        except asyncio.CancelledError:
            pass
    for t in market_tasks:
        t.cancel()
    try:
        await retention
    except asyncio.CancelledError:
        pass
    if monitor_task is not None:
        monitor_task.cancel()
    if settle_task is not None:
        settle_task.cancel()
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
app.include_router(products.router, prefix="/api")
app.include_router(orders.router, prefix="/api")
app.include_router(vip.router, prefix="/api")
app.include_router(team.router, prefix="/api")
app.include_router(settlements.router, prefix="/api")
app.include_router(withdrawals.router, prefix="/api")
app.include_router(admin_withdrawals.router, prefix="/api")
app.include_router(admin_products.router, prefix="/api")
app.include_router(admin_users.router, prefix="/api")
app.include_router(deposit.router, prefix="/api")
app.include_router(admin_deposit.router, prefix="/api")
app.include_router(admin_rbac.router, prefix="/api")
app.include_router(admin_sweep.router, prefix="/api")
app.include_router(overview.router, prefix="/api")
app.include_router(chat.router, prefix="/api")


@app.get("/health")
async def health():
    return {"status": "ok"}
