"""产品测试数据种子脚本. 用法 (server 目录, venv):
    python scripts/seed_products.py
重复执行会按名字去重, 不会插入重复产品.
"""
from __future__ import annotations

import asyncio
import os
import sys
from decimal import Decimal
from pathlib import Path

# 允许从 scripts/ 目录直接运行
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///./hk_dev.db")

from sqlalchemy import select  # noqa: E402

from database import SessionLocal, engine  # noqa: E402
from models.hk import HkBase  # noqa: E402
from models.product import HkProduct  # noqa: E402

# (名称, 描述, 日收益率, 周期天, 返还方式, 最低, 最高, VIP门槛, 团队门槛, 状态)
SEED_PRODUCTS = [
    # 文档第五节试算基准: 10,000U / 2%/日 / 30天 / 到期返还 -> 总支出 17,087.68U
    ("稳健盈 30天", "到期一次性结算, 适合作为验收算例基准",
     "0.02", 30, "expiry", "1000", "100000", None, None, "published"),
    ("新手体验 7天", "每日返还, 低门槛体验",
     "0.005", 7, "daily", "100", "5000", None, None, "published"),
    ("进阶双门槛 30天", "要求个人VIP 3 且团队等级 5 (验收场景)",
     "0.022", 30, "period_30d", "5000", "200000", 3, 5, "published"),
    ("周返盈 28天", "每7天结算一期, 共4期",
     "0.01", 28, "period_7d", "500", "50000", None, None, "published"),
    ("高净值 90天", "每30天结算, 高门槛专享",
     "0.025", 90, "period_30d", "20000", "500000", 5, 3, "published"),
    ("只限VIP 14天", "仅设个人VIP门槛示例",
     "0.008", 14, "daily", "1000", "30000", 2, None, "published"),
    ("内部测试产品", "草稿状态, 不应出现在 APP 产品页",
     "0.03", 30, "expiry", "100", "9999", None, None, "draft"),
]


async def main() -> None:
    async with engine.begin() as conn:
        await conn.run_sync(HkBase.metadata.create_all)

    async with SessionLocal() as db:
        inserted = 0
        for row in SEED_PRODUCTS:
            name = row[0]
            exists = await db.execute(
                select(HkProduct.id).where(HkProduct.name == name)
            )
            if exists.first() is not None:
                print(f"跳过(已存在): {name}")
                continue
            db.add(
                HkProduct(
                    name=name,
                    description=row[1],
                    base_daily_rate=Decimal(row[2]),
                    duration_days=row[3],
                    return_method=row[4],
                    min_amount=Decimal(row[5]),
                    max_amount=Decimal(row[6]),
                    vip_level_req=row[7],
                    team_level_req=row[8],
                    status=row[9],
                )
            )
            inserted += 1
            print(f"插入: {name}")
        await db.commit()
    print(f"完成, 新插入 {inserted} 个产品")


if __name__ == "__main__":
    asyncio.run(main())
