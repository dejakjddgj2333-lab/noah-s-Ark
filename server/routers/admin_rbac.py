"""后台 RBAC 路由: 当前管理员信息 / 权限树 / 角色管理 / 管理员管理 / 仪表盘统计."""
from __future__ import annotations

import json
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkDepositRecord, HkWithdrawal
from models.hk import HkRole, HkUser
from models.order import HkOrder
from models.product import HkProduct
from services import admin_service
from services.permissions import ALL_CODES, PERMISSION_TREE

router = APIRouter(prefix="/admin", tags=["后台-RBAC"])


@router.get("/me")
async def admin_me(
    user: HkUser = Depends(admin_service.require_admin),
    db: AsyncSession = Depends(get_db),
):
    """当前管理员: 用户信息 + 角色 + 权限码 (前端菜单/按钮过滤用)."""
    perms = await admin_service.get_perms(db, user)
    role = None
    if user.role_id is not None:
        r = (
            await db.execute(select(HkRole).where(HkRole.id == user.role_id))
        ).scalar_one_or_none()
        if r is not None:
            role = {"id": r.id, "code": r.code, "name": r.name}
    return {
        "user": {"id": user.id, "username": user.username,
                 "nickname": user.nickname, "avatar_url": user.avatar_url},
        "role": role,
        "perms": perms,
    }


@router.get("/permissions")
async def permission_tree(
    user: HkUser = Depends(admin_service.require_perm("page:roles")),
):
    """权限树 (角色编辑勾选框)."""
    return {"tree": PERMISSION_TREE}


# ---------- 角色管理 ----------


class RoleIn(BaseModel):
    name: str = Field(min_length=1, max_length=32)
    perms: list[str] = Field(default_factory=list)


def _role_out(r: HkRole) -> dict:
    return {
        "id": r.id, "code": r.code, "name": r.name,
        "perms": json.loads(r.perms or "[]"), "builtin": r.builtin,
        "created_at": str(r.created_at),
    }


@router.get("/roles")
async def list_roles(
    user: HkUser = Depends(admin_service.require_perm("page:roles")),
    db: AsyncSession = Depends(get_db),
):
    rows = (await db.execute(select(HkRole).order_by(HkRole.id))).scalars().all()
    return [_role_out(r) for r in rows]


@router.post("/roles")
async def create_role(
    body: RoleIn,
    user: HkUser = Depends(admin_service.require_perm("btn:role:manage")),
    db: AsyncSession = Depends(get_db),
):
    bad = [p for p in body.perms if p != "*" and p not in ALL_CODES]
    if bad:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"未知权限码: {bad}")
    code = f"custom_{int(datetime.utcnow().timestamp())}"
    role = HkRole(code=code, name=body.name,
                  perms=json.dumps(body.perms), builtin=False)
    db.add(role)
    await db.flush()
    await admin_service.audit(db, user, "role_create", "role", role.id,
                              f"name={body.name} perms={body.perms}")
    await db.commit()
    return _role_out(role)


@router.put("/roles/{role_id}")
async def update_role(
    role_id: int,
    body: RoleIn,
    user: HkUser = Depends(admin_service.require_perm("btn:role:manage")),
    db: AsyncSession = Depends(get_db),
):
    role = (
        await db.execute(select(HkRole).where(HkRole.id == role_id))
    ).scalar_one_or_none()
    if role is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "角色不存在")
    if role.code == "superadmin":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "超级管理员不可修改")
    bad = [p for p in body.perms if p != "*" and p not in ALL_CODES]
    if bad:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"未知权限码: {bad}")
    role.name = body.name
    role.perms = json.dumps(body.perms)
    await db.flush()
    await admin_service.audit(db, user, "role_update", "role", role.id,
                              f"name={body.name} perms={body.perms}")
    await db.commit()
    return _role_out(role)


@router.delete("/roles/{role_id}")
async def delete_role(
    role_id: int,
    user: HkUser = Depends(admin_service.require_perm("btn:role:manage")),
    db: AsyncSession = Depends(get_db),
):
    role = (
        await db.execute(select(HkRole).where(HkRole.id == role_id))
    ).scalar_one_or_none()
    if role is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "角色不存在")
    if role.builtin:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "内置角色不可删除")
    in_use = (
        await db.execute(
            select(func.count()).select_from(HkUser).where(HkUser.role_id == role_id)
        )
    ).scalar_one()
    if in_use:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            f"仍有 {in_use} 个管理员挂在该角色, 先移除")
    await db.delete(role)
    await admin_service.audit(db, user, "role_delete", "role", role_id,
                              f"name={role.name}")
    await db.commit()
    return {"ok": True}


# ---------- 管理员管理 ----------


def _admin_out(u: HkUser, role: HkRole | None) -> dict:
    return {
        "id": u.id, "username": u.username, "nickname": u.nickname,
        "email": u.email, "status": u.status,
        "role": {"id": role.id, "code": role.code, "name": role.name}
        if role else None,
        "created_at": str(u.created_at),
    }


@router.get("/admins")
async def list_admins(
    user: HkUser = Depends(admin_service.require_perm("page:admins")),
    db: AsyncSession = Depends(get_db),
):
    """管理员列表 = 绑了角色的用户."""
    rows = (
        await db.execute(
            select(HkUser).where(HkUser.role_id.isnot(None)).order_by(HkUser.id)
        )
    ).scalars().all()
    out = []
    for u in rows:
        role = (
            await db.execute(select(HkRole).where(HkRole.id == u.role_id))
        ).scalar_one_or_none()
        out.append(_admin_out(u, role))
    return out


class AdminBindIn(BaseModel):
    username: str = Field(min_length=1, max_length=32)
    role_id: int


async def _bind_role(db: AsyncSession, operator: HkUser, username: str,
                     role_id: int | None) -> dict:
    u = (
        await db.execute(select(HkUser).where(HkUser.username == username))
    ).scalar_one_or_none()
    if u is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    if u.id == operator.id and role_id is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能移除自己的管理员角色")
    role = None
    if role_id is not None:
        role = (
            await db.execute(select(HkRole).where(HkRole.id == role_id))
        ).scalar_one_or_none()
        if role is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "角色不存在")
    u.role_id = role_id
    await db.flush()
    await admin_service.audit(
        db, operator, "admin_bind_role", "user", u.id,
        f"username={username} role={role.code if role else 'None'}")
    await db.commit()
    return _admin_out(u, role)


@router.post("/admins")
async def bind_admin(
    body: AdminBindIn,
    user: HkUser = Depends(admin_service.require_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """绑定管理员: 按用户名挂角色 (用户须已注册)."""
    return await _bind_role(db, user, body.username, body.role_id)


@router.put("/admins/{user_id}")
async def change_admin_role(
    user_id: int,
    body: AdminBindIn,
    user: HkUser = Depends(admin_service.require_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    target = (
        await db.execute(select(HkUser).where(HkUser.id == user_id))
    ).scalar_one_or_none()
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    return await _bind_role(db, user, target.username, body.role_id)


@router.delete("/admins/{user_id}")
async def remove_admin(
    user_id: int,
    user: HkUser = Depends(admin_service.require_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    target = (
        await db.execute(select(HkUser).where(HkUser.id == user_id))
    ).scalar_one_or_none()
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")
    return await _bind_role(db, user, target.username, None)


# ---------- 仪表盘统计 ----------


@router.get("/stats")
async def admin_stats(
    user: HkUser = Depends(admin_service.require_perm("page:dashboard")),
    db: AsyncSession = Depends(get_db),
):
    today = datetime.utcnow().replace(hour=0, minute=0, second=0, microsecond=0)
    tomorrow = today + timedelta(days=1)

    async def count(stmt):
        return (await db.execute(stmt)).scalar_one()

    total_users = await count(select(func.count()).select_from(HkUser))
    today_users = await count(
        select(func.count()).select_from(HkUser).where(
            HkUser.created_at >= today, HkUser.created_at < tomorrow))
    deposit_today = (
        await db.execute(
            select(func.coalesce(func.sum(HkDepositRecord.amount), 0)).where(
                HkDepositRecord.status == "credited",
                HkDepositRecord.credited_at >= today,
                HkDepositRecord.credited_at < tomorrow,
            )
        )
    ).scalar_one()
    deposit_total = (
        await db.execute(
            select(func.coalesce(func.sum(HkDepositRecord.amount), 0)).where(
                HkDepositRecord.status == "credited")
        )
    ).scalar_one()
    pending_withdrawals = await count(
        select(func.count()).select_from(HkWithdrawal).where(
            HkWithdrawal.status == "pending"))
    order_total = (
        await db.execute(
            select(func.coalesce(func.sum(HkOrder.amount), 0)).where(
                HkOrder.status.in_(["effective", "finished"]))
        )
    ).scalar_one()
    product_count = await count(
        select(func.count()).select_from(HkProduct).where(
            HkProduct.status == "published"))
    return {
        "total_users": total_users,
        "today_users": today_users,
        "deposit_today": str(deposit_today),
        "deposit_total": str(deposit_total),
        "pending_withdrawals": pending_withdrawals,
        "order_total": str(order_total),
        "product_count": product_count,
    }
