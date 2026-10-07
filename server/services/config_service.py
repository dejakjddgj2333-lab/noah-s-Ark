"""功能开关/站点配置: HkConfig key-value, 种子默认, 公开读取白名单."""
from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from models.hk import HkConfig

# 默认配置种子 (key, 默认值, 后台显示名)
_DEFAULTS = (
    ("wallet_enabled", "0", "充值/提现功能开关"),  # 0=隐藏 1=显示
)

# 允许 app 公开读取的 key 白名单 (不整表倒出, 防泄露内部配置)
PUBLIC_KEYS = ("wallet_enabled",)


async def seed_configs(db: AsyncSession) -> None:
    """缺省插入默认开关 (幂等: 已有该 key 则跳过)."""
    existing = (await db.execute(select(HkConfig.key))).scalars().all()
    have = set(existing)
    for key, value, label in _DEFAULTS:
        if key in have:
            continue
        db.add(HkConfig(key=key, value=value, label=label))
    await db.commit()


async def get_all(db: AsyncSession) -> dict[str, str]:
    """全部配置 key→value (后台用)."""
    rows = (await db.execute(select(HkConfig))).scalars().all()
    return {r.key: r.value for r in rows}


async def get_public(db: AsyncSession) -> dict[str, bool]:
    """公开配置 (app 用): 仅白名单 key, 统一转 bool."""
    rows = (
        await db.execute(select(HkConfig).where(HkConfig.key.in_(PUBLIC_KEYS)))
    ).scalars().all()
    m = {r.key: r.value for r in rows}
    return {k: m.get(k, "0") == "1" for k in PUBLIC_KEYS}


async def set_value(db: AsyncSession, key: str, value: str) -> bool:
    """后台改开关. key 不存在返回 False."""
    row = (
        await db.execute(select(HkConfig).where(HkConfig.key == key))
    ).scalar_one_or_none()
    if row is None:
        return False
    row.value = value
    await db.commit()
    return True
