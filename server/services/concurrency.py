"""进程内互斥锁: 补绑与购买的"检查-写入"临界区互斥 (需求文档第八节).

文档场景: "购买与补绑并发 —— 先补绑则购买沿用关系, 先购买则补绑失败,
禁止检查和写入之间被绕过." 两个操作各自"先查资格/等级, 后写绑定/订单",
单进程内用 asyncio.Lock 串行化即可堵住检查时点在途事务的竞态.

⚠️ 仅单 uvicorn 进程有效; 多实例部署需换分布式锁 (Redis 或 PG advisory lock).
"""
from __future__ import annotations

import asyncio

# 补绑 ↔ 购买 共用的临界区锁 (不嵌套使用, 无死锁风险)
bind_purchase_lock = asyncio.Lock()
