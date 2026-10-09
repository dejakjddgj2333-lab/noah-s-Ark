"""产品后台路由 (管理员): 配置 / 上架校验 / 发布 / 下架.

生效边界 (Phase 0.9 未拍板前的保守策略):
- 新建产品一律为草稿 draft;
- 已上架 (published) 产品不允许修改配置 —— 需先下架; 已生效订单持有快照不受影响;
- 上架前强制跑 product_service.validate_product 全套校验.
"""
from __future__ import annotations

from datetime import datetime
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.hk import HkAdminUser, HkUser
from models.product import HkProduct, PRODUCT_STATUSES
from services import admin_service, auth_service, product_service

router = APIRouter(prefix="/admin/products", tags=["后台-产品"])


class ProductIn(BaseModel):
    name: str
    description: str | None = None
    base_daily_rate: Decimal
    duration_days: int
    return_method: str
    min_amount: Decimal
    max_amount: Decimal
    vip_level_req: int | None = None
    team_level_req: int | None = None


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
    status: str
    created_at: datetime
    updated_at: datetime

    model_config = {"from_attributes": True}


@router.get("", response_model=list[ProductOut])
async def list_products(
    status_filter: str | None = None,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:product:edit")),
    db: AsyncSession = Depends(get_db),
):
    """全部产品 (含草稿/下架), 可按状态过滤."""
    q = select(HkProduct).order_by(desc(HkProduct.id))
    if status_filter:
        q = q.where(HkProduct.status == status_filter)
    result = await db.execute(q)
    return result.scalars().all()


@router.post("", response_model=ProductOut, status_code=status.HTTP_201_CREATED)
async def create_product(
    data: ProductIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:product:edit")),
    db: AsyncSession = Depends(get_db),
):
    """新建产品 (草稿)."""
    product = HkProduct(**data.model_dump(), status="draft")
    db.add(product)
    await db.flush()
    await admin_service.audit_admin(
        db, admin, "product_create", "product", product.id,
        detail=f"name={product.name} rate={product.base_daily_rate} days={product.duration_days}",
    )
    await db.commit()
    return product


@router.put("/{product_id}", response_model=ProductOut)
async def update_product(
    product_id: int,
    data: ProductIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:product:edit")),
    db: AsyncSession = Depends(get_db),
):
    """修改产品配置. 已上架产品禁止修改 (Phase 0.9 未拍板, 保守策略: 先下架再改)."""
    product = await _get(db, product_id)
    if product.status == "published":
        raise HTTPException(
            status.HTTP_409_CONFLICT, "已上架产品不能修改配置，请先下架"
        )
    for k, v in data.model_dump().items():
        setattr(product, k, v)
    await admin_service.audit_admin(
        db, admin, "product_update", "product", product.id,
        detail=f"name={product.name}",
    )
    await db.commit()
    return product


@router.post("/{product_id}/publish", response_model=ProductOut)
async def publish_product(
    product_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:product:edit")),
    db: AsyncSession = Depends(get_db),
):
    """上架: 强制全套校验, 通过后对 APP 可见."""
    product = await _get(db, product_id)
    product_service.validate_product(
        base_daily_rate=Decimal(product.base_daily_rate),
        duration_days=product.duration_days,
        return_method=product.return_method,
        min_amount=Decimal(product.min_amount),
        max_amount=Decimal(product.max_amount),
        vip_level_req=product.vip_level_req,
        team_level_req=product.team_level_req,
    )
    product.status = "published"
    await admin_service.audit_admin(
        db, admin, "product_publish", "product", product.id, detail=f"name={product.name}"
    )
    await db.commit()
    return product


@router.post("/{product_id}/offline", response_model=ProductOut)
async def offline_product(
    product_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:product:edit")),
    db: AsyncSession = Depends(get_db),
):
    """下架: APP 不再可购买; 存量已生效订单按原快照继续结算至到期."""
    product = await _get(db, product_id)
    product.status = "offline"
    await admin_service.audit_admin(
        db, admin, "product_offline", "product", product.id, detail=f"name={product.name}"
    )
    await db.commit()
    return product


@router.delete("/{product_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_product(
    product_id: int,
    user: HkUser = Depends(admin_service.require_perm("btn:product:delete")),
    db: AsyncSession = Depends(get_db),
):
    """删除产品 (2026-10-09): 保护规则 ——
    已上架禁止删 (先下架); 已有任何购买订单禁止删 (只能下架, 保追溯).
    仅草稿/已下架且无订单的产品可物理删除.
    """
    product = await _get(db, product_id)
    if product.status == "published":
        raise HTTPException(
            status.HTTP_409_CONFLICT, "已上架产品不能删除，请先下架"
        )
    from sqlalchemy import func

    from models.order import HkOrder

    orders = (
        await db.execute(
            select(func.count(HkOrder.id)).where(HkOrder.product_id == product_id)
        )
    ).scalar_one()
    if orders > 0:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"该产品已有 {orders} 笔购买订单，不可删除 (只能下架)",
        )
    name = product.name
    await db.delete(product)
    await admin_service.audit(
        db, user, "product_delete", "product", product_id, detail=f"name={name}"
    )
    await db.commit()


async def _get(db: AsyncSession, product_id: int) -> HkProduct:
    product = (
        await db.execute(select(HkProduct).where(HkProduct.id == product_id))
    ).scalar_one_or_none()
    if product is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, detail="产品不存在")
    return product
