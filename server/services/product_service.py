"""产品配置校验 (需求文档第二节上架校验)."""
from __future__ import annotations

from decimal import Decimal

from fastapi import HTTPException, status

from models.product import RETURN_METHODS


def validate_product(
    *,
    base_daily_rate: Decimal,
    duration_days: int,
    return_method: str,
    min_amount: Decimal,
    max_amount: Decimal,
    vip_level_req: int | None,
    team_level_req: int | None,
) -> None:
    """上架前校验: 不通过则抛 400. 金额/比例用 Decimal 定点比较."""
    if return_method not in RETURN_METHODS:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail=f"无效的返还方式: {return_method}",
        )
    if base_daily_rate <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="基础每日收益率必须大于 0"
        )
    if duration_days <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="产品周期必须大于 0 天"
        )
    if min_amount <= 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="最低购买金额必须大于 0"
        )
    if min_amount > max_amount:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST, detail="最低金额不得高于最高金额"
        )
    # 周期与返还间隔匹配, 不出现不足结算周期
    if return_method == "period_7d" and duration_days % 7 != 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="每7天返还的产品, 周期必须是 7 的整数倍",
        )
    if return_method == "period_30d" and duration_days % 30 != 0:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="每30天返还的产品, 周期必须是 30 的整数倍",
        )
    if return_method == "period_1h" and duration_days * 24 < 1:
        raise HTTPException(
            status.HTTP_400_BAD_REQUEST,
            detail="每小时返还的产品, 周期至少 1 小时",
        )
    for label, lv in (("个人VIP", vip_level_req), ("团队等级", team_level_req)):
        if lv is not None and not (0 <= lv <= 10):
            raise HTTPException(
                status.HTTP_400_BAD_REQUEST, detail=f"{label}门槛须在 0~10 之间"
            )
