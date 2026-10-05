"""明策 hk 后端配置. 环境变量驱动, 参考 okx/backend/config.py 精简."""
from __future__ import annotations

import os
from dataclasses import dataclass
from decimal import Decimal

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
    # 市场数据源: free=免费源直连(默认) / coinglass=CoinGlass (续 key 后切回).
    # free 模式实际生效还需对应源可用; coinglass 模式需 key 存在, 否则自动回落 free.
    market_data_source: str = os.getenv("MARKET_DATA_SOURCE", "free")
    okx_base_url: str = os.getenv("OKX_BASE_URL", "https://www.okx.com")
    # TronGrid API key (充值扫链; 空 = 公共 3 QPS 限流)
    trongrid_api_key: str = os.getenv("TRONGRID_API_KEY", "")
    # Etherscan V2 API key (EVM 三网扫链; 一把 key 多链, etherscan.io 免费注册)
    etherscan_api_key: str = os.getenv("ETHERSCAN_API_KEY", "")
    # 充值地址池: 空闲低于下限自动补足到目标数
    deposit_pool_min: int = int(os.getenv("DEPOSIT_POOL_MIN", "20"))
    deposit_pool_target: int = int(os.getenv("DEPOSIT_POOL_TARGET", "50"))

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
    # 同一验证码校验失败次数上限, 超限须重新获取 (防暴力枚举 6 位码)
    email_code_max_attempts: int = int(os.getenv("EMAIL_CODE_MAX_ATTEMPTS", "5"))

    # 反代信任: 置 true 才采信 X-Forwarded-For (nginx/云负载后); 直连必须保持 false
    trust_x_forwarded_for: bool = os.getenv("TRUST_X_FORWARDED_FOR", "").lower() in (
        "1", "true", "yes",
    )

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

    # 后台管理员用户名 (逗号分隔; 仅这些用户可访问 /api/admin/*)
    admin_usernames: tuple[str, ...] = tuple(
        u.strip()
        for u in os.getenv("ADMIN_USERNAMES", "").split(",")
        if u.strip()
    )
    # 充值扫链监听开关 (测试时可关闭)
    deposit_monitor_enabled: bool = (
        os.getenv("DEPOSIT_MONITOR_ENABLED", "true").lower() == "true"
    )
    # 结算引擎开关与轮询间隔 (测试时可关闭)
    settlement_enabled: bool = (
        os.getenv("SETTLEMENT_ENABLED", "true").lower() == "true"
    )
    settlement_interval_sec: int = int(
        os.getenv("SETTLEMENT_INTERVAL_SEC", "60")
    )

    # ── 安全防护 ──
    # 登录限流: 同一 IP+用户名 窗口内允许的最大失败尝试次数
    login_rate_limit: int = int(os.getenv("LOGIN_RATE_LIMIT", "5"))
    login_rate_window_sec: int = int(os.getenv("LOGIN_RATE_WINDOW_SEC", "300"))
    # 注册限流: 同一 IP 窗口内最大注册数 (防批量养号)
    register_rate_limit: int = int(os.getenv("REGISTER_RATE_LIMIT", "100"))
    register_rate_window_sec: int = int(
        os.getenv("REGISTER_RATE_WINDOW_SEC", "3600")
    )
    # 发码限流: 同一 IP 窗口内最大发码数 (防邮件轰炸)
    email_code_rate_limit: int = int(os.getenv("EMAIL_CODE_RATE_LIMIT", "10"))
    email_code_rate_window_sec: int = int(
        os.getenv("EMAIL_CODE_RATE_WINDOW_SEC", "3600")
    )
    # 提现限额 (USDT; 按扣费前申请金额计). 0 = 不限制
    withdraw_max_per_request: Decimal = Decimal(
        os.getenv("WITHDRAW_MAX_PER_REQUEST", "100000")
    )
    # 提现单日累计上限 (同一用户, 处理中+已通过计入;  rejected 已退回不计)
    withdraw_daily_limit: Decimal = Decimal(
        os.getenv("WITHDRAW_DAILY_LIMIT", "200000")
    )


def load_config() -> Config:
    cfg = Config()
    if cfg.secret_key in ("dev-only-change-me", "") and os.getenv(
        "APP_ENV", "dev"
    ) == "prod":
        raise RuntimeError("SECRET_KEY must be set in prod")
    return cfg


config = load_config()
