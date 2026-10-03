"""产品路由: 已上架产品查询 (公开). 配置/上架/下架端点归后台管理, 后续实现."""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.product import HkProduct  # noqa: F401 注册 HkBase 元数据
from services import product_service  # noqa: F401 校验逻辑归购买/后台复用

router = APIRouter(prefix="/products", tags=["产品"])


class ProductOut(BaseModel):
    id: int
    name: str
    description: str | None
    base_daily_rate: Decimal
    duration_days: int
    return_method: str
    min_amount: Decimal
    max_amount: Decimal
    vip_level_req: int | None
    team_level_req: int | None

    model_config = {"from_attributes": True}


@router.get("", response_model=list[ProductOut])
async def list_products(db: AsyncSession = Depends(get_db)):
    """已上架产品列表 (APP 产品页展示)."""
    result = await db.execute(
        select(HkProduct)
        .where(HkProduct.status == "published")
        .order_by(HkProduct.min_amount.asc())
    )
    return result.scalars().all()


@router.get("/{product_id}", response_model=ProductOut)
async def product_detail(product_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(HkProduct).where(
            HkProduct.id == product_id, HkProduct.status == "published"
        )
    )
    product = result.scalar_one_or_none()
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="产品不存在或未上架")
    return product
