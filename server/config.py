"""明策 hk 后端配置. 环境变量驱动, 参考 okx/backend/config.py 精简."""
from __future__ import annotations

import os
from dataclasses import dataclass

from dotenv import load_dotenv

load_dotenv()
# 本地敏感 key (APITUBE/DEEPSEEK 等) 放 .env.local, gitignored 不入库
load_dotenv(".env.local", override=True)


@dataclass(frozen=True)
class Config:
    # 与 okx 后端共用同一个库 (只读共享 news_articles / market 相关表).
    # 本地开发可回退 sqlite; 生产指向共享 PostgreSQL.
    database_url: str = os.getenv(
        "DATABASE_URL", "sqlite+aiosqlite:///./hk_dev.db"
    )
    secret_key: str = os.getenv("SECRET_KEY", "dev-only-change-me")
    jwt_expire_hours: int = int(os.getenv("JWT_EXPIRE_HOURS", "24"))

    # 聊天文件上传根目录 (实际存 <upload_dir>/chat/)
    upload_dir: str = os.getenv("UPLOAD_DIR", "uploads")

    cors_origins: tuple[str, ...] = tuple(
        o.strip()
        for o in os.getenv(
            "CORS_ORIGINS", "http://localhost:8088,http://localhost:5217"
        ).split(",")
        if o.strip()
    )

    # 第三方 (与 okx 相同来源)
    coinglass_api_key: str = os.getenv("COINGLASS_API_KEY", "")
    okx_base_url: str = os.getenv("OKX_BASE_URL", "https://www.okx.com")

    # SMTP 注册验证码邮件
    smtp_host: str = os.getenv("SMTP_HOST", "")
    smtp_port: int = int(os.getenv("SMTP_PORT", "465"))
    smtp_user: str = os.getenv("SMTP_USER", "")
    smtp_password: str = os.getenv("SMTP_PASSWORD", "")
    smtp_from: str = os.getenv("SMTP_FROM", os.getenv("SMTP_USER", ""))
    smtp_use_ssl: bool = os.getenv("SMTP_USE_SSL", "true").lower() == "true"
    # 关闭后: 注册跳过验证码校验, send-email-code 直接回显 debug_code (测试用)
    email_verify_enabled: bool = (
        os.getenv("EMAIL_VERIFY_ENABLED", "true").lower() == "true"
    )

    # 验证码策略
    email_code_ttl_sec: int = int(os.getenv("EMAIL_CODE_TTL_SEC", "600"))
    email_code_interval_sec: int = int(os.getenv("EMAIL_CODE_INTERVAL_SEC", "60"))

    # WebRTC TURN (与 okx 共用 coturn; 空 = 仅 STUN)
    turn_urls: str = os.getenv("TURN_URLS", "")  # 逗号分隔
    turn_username: str = os.getenv("TURN_USERNAME", "")
    turn_credential: str = os.getenv("TURN_CREDENTIAL", "")

    # 资讯采集 (hk 侧接管, 为两项目分离做准备)
    apitube_api_key: str = os.getenv("APITUBE_API_KEY", "")
    deepseek_api_key: str = os.getenv("DEEPSEEK_API_KEY", "")
    news_collect_enabled: bool = (
        os.getenv("NEWS_COLLECT_ENABLED", "true").lower() == "true"
    )
    news_collect_interval_sec: int = int(
        os.getenv("NEWS_COLLECT_INTERVAL_SEC", "1800")  # 30 分钟
    )


def load_config() -> Config:
    cfg = Config()
    if cfg.secret_key in ("dev-only-change-me", "") and os.getenv(
        "APP_ENV", "dev"
    ) == "prod":
        raise RuntimeError("SECRET_KEY must be set in prod")
    return cfg


config = load_config()
