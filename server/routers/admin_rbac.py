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
from models.hk import HkAdminUser, HkRole, HkUser
from models.order import HkOrder
from models.product import HkProduct
from services import admin_service, auth_service
from services.permissions import ALL_CODES, PERMISSION_TREE

router = APIRouter(prefix="/admin", tags=["后台-RBAC"])


@router.get("/me")
async def admin_me(
    admin: HkAdminUser = Depends(auth_service.get_current_admin_raw),
    db: AsyncSession = Depends(get_db),
):
    """当前管理员: 信息 + 角色 + 权限码 + TOTP 绑定状态 (前端过滤用).
    用 raw 依赖: 未绑 TOTP 的管理员也要能拿到 need_totp 状态去绑定."""
    perms = await admin_service.get_admin_perms(db, admin)
    role = (
        await db.execute(select(HkRole).where(HkRole.id == admin.role_id))
    ).scalar_one_or_none()
    return {
        "user": {"id": admin.id, "username": admin.username},
        "role": {"id": role.id, "code": role.code, "name": role.name}
        if role else None,
        "perms": perms,
        "totp_bound": admin.totp_bound,
        "need_totp": not admin.totp_bound and admin.username != "admin",
    }


@router.get("/permissions")
async def permission_tree(
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:roles")),
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
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:roles")),
    db: AsyncSession = Depends(get_db),
):
    rows = (await db.execute(select(HkRole).order_by(HkRole.id))).scalars().all()
    return [_role_out(r) for r in rows]


@router.post("/roles")
async def create_role(
    body: RoleIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:role:manage")),
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
    await admin_service.audit_admin(db, admin, "role_create", "role", role.id,
                              f"name={body.name} perms={body.perms}")
    await db.commit()
    return _role_out(role)


@router.put("/roles/{role_id}")
async def update_role(
    role_id: int,
    body: RoleIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:role:manage")),
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
    await admin_service.audit_admin(db, admin, "role_update", "role", role.id,
                              f"name={body.name} perms={body.perms}")
    await db.commit()
    return _role_out(role)


@router.delete("/roles/{role_id}")
async def delete_role(
    role_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:role:manage")),
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
            select(func.count()).select_from(HkAdminUser).where(
                HkAdminUser.role_id == role_id)
        )
    ).scalar_one()
    if in_use:
        raise HTTPException(status.HTTP_400_BAD_REQUEST,
                            f"仍有 {in_use} 个管理员挂在该角色, 先移除")
    await db.delete(role)
    await admin_service.audit_admin(db, admin, "role_delete", "role", role_id,
                              f"name={role.name}")
    await db.commit()
    return {"ok": True}


# ---------- 管理员管理 (独立于 App 注册用户) ----------


def _admin_user_out(a: HkAdminUser, role: HkRole | None) -> dict:
    return {
        "id": a.id, "username": a.username, "status": a.status,
        "totp_bound": a.totp_bound,
        "role": {"id": role.id, "code": role.code, "name": role.name}
        if role else None,
        "created_at": str(a.created_at),
    }


@router.get("/admins")
async def list_admins(
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:admins")),
    db: AsyncSession = Depends(get_db),
):
    """管理员列表 (hk_admin_users, 与注册用户无关)."""
    rows = (
        await db.execute(select(HkAdminUser).order_by(HkAdminUser.id))
    ).scalars().all()
    out = []
    for a in rows:
        role = (
            await db.execute(select(HkRole).where(HkRole.id == a.role_id))
        ).scalar_one_or_none()
        out.append(_admin_user_out(a, role))
    return out


class AdminCreateIn(BaseModel):
    username: str = Field(min_length=3, max_length=32, pattern=r"^[a-zA-Z0-9_]+$")
    password: str = Field(min_length=8, max_length=128)
    role_id: int


@router.post("/admins", status_code=201)
async def create_admin(
    body: AdminCreateIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """新建管理员: 独立账号, 初始未绑谷歌验证, 首次登录须绑定."""
    username = body.username.lower()
    dup = (
        await db.execute(
            select(HkAdminUser).where(HkAdminUser.username == username)
        )
    ).scalar_one_or_none()
    if dup is not None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "用户名已存在")
    role = (
        await db.execute(select(HkRole).where(HkRole.id == body.role_id))
    ).scalar_one_or_none()
    if role is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "角色不存在")
    a = HkAdminUser(
        username=username,
        password_hash=auth_service.hash_password(body.password),
        role_id=body.role_id,
        status="active",
    )
    db.add(a)
    await db.flush()
    await admin_service.audit_admin(
        db, admin, "admin_create", "admin_user", a.id,
        f"username={username} role={role.code}")
    await db.commit()
    return _admin_user_out(a, role)


class AdminUpdateIn(BaseModel):
    role_id: int | None = None
    password: str | None = Field(default=None, min_length=8, max_length=128)
    status: str | None = Field(default=None, pattern="^(active|disabled)$")


async def _get_admin_or_404(db: AsyncSession, admin_id: int) -> HkAdminUser:
    a = (
        await db.execute(select(HkAdminUser).where(HkAdminUser.id == admin_id))
    ).scalar_one_or_none()
    if a is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "管理员不存在")
    return a


@router.put("/admins/{admin_id}")
async def update_admin(
    admin_id: int,
    body: AdminUpdateIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """改角色/重置密码/启停. 不能禁用自己, 不能动超管的超管角色."""
    target = await _get_admin_or_404(db, admin_id)
    target_role = (
        await db.execute(select(HkRole).where(HkRole.id == target.role_id))
    ).scalar_one_or_none()
    if target_role is not None and target_role.code == "superadmin" and (
        body.role_id is not None or body.status == "disabled"
    ):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能改超级管理员的角色或状态")
    if body.status == "disabled" and target.id == admin.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能禁用自己的账号")
    if body.role_id is not None:
        role = (
            await db.execute(select(HkRole).where(HkRole.id == body.role_id))
        ).scalar_one_or_none()
        if role is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "角色不存在")
        target.role_id = body.role_id
    if body.password:
        target.password_hash = auth_service.hash_password(body.password)
    if body.status is not None:
        target.status = body.status
    await db.flush()
    await admin_service.audit_admin(
        db, admin, "admin_update", "admin_user", target.id,
        f"role_id={body.role_id} status={body.status} pwd_reset={bool(body.password)}")
    await db.commit()
    role = (
        await db.execute(select(HkRole).where(HkRole.id == target.role_id))
    ).scalar_one_or_none()
    return _admin_user_out(target, role)


@router.post("/admins/{admin_id}/reset-totp")
async def reset_admin_totp(
    admin_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """重置谷歌验证 (换手机/丢密钥): 清密钥, 下次登录重新绑定."""
    target = await _get_admin_or_404(db, admin_id)
    target.totp_secret = None
    target.totp_bound = False
    await db.flush()
    await admin_service.audit_admin(
        db, admin, "admin_totp_reset", "admin_user", target.id)
    await db.commit()
    return {"ok": True}


@router.post("/admins/{admin_id}/totp-setup")
async def admin_totp_setup(
    admin_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """管理页代绑定谷歌验证: 生成/重取目标管理员的绑定密钥 (返回 otpauth URI)."""
    import urllib.parse

    target = await _get_admin_or_404(db, admin_id)
    if not target.totp_secret:
        target.totp_secret = auth_service.generate_totp_secret()
        await db.commit()
    label = urllib.parse.quote(f"NoahAdmin:{target.username}")
    uri = (
        f"otpauth://totp/{label}?secret={target.totp_secret}"
        f"&issuer=NoahAdmin&algorithm=SHA1&digits=6&period=30"
    )
    return {"secret": target.totp_secret, "uri": uri}


class TotpConfirmIn(BaseModel):
    code: str = Field(min_length=6, max_length=8)


@router.post("/admins/{admin_id}/totp-confirm")
async def admin_totp_confirm(
    admin_id: int,
    body: TotpConfirmIn,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """管理页代绑定: 校验动态码后确认绑定."""
    target = await _get_admin_or_404(db, admin_id)
    if not target.totp_secret:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "请先生成绑定密钥")
    if not auth_service.verify_totp(target.totp_secret, body.code):
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "验证码错误, 请重试")
    target.totp_bound = True
    await db.flush()
    await admin_service.audit_admin(
        db, admin, "admin_totp_bind", "admin_user", target.id,
        f"operator={admin.username}")
    await db.commit()
    return {"ok": True}


@router.delete("/admins/{admin_id}")
async def delete_admin(
    admin_id: int,
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("btn:admin:manage")),
    db: AsyncSession = Depends(get_db),
):
    """删除管理员. 不能删自己, 不能删超管."""
    target = await _get_admin_or_404(db, admin_id)
    if target.id == admin.id:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能删除自己的账号")
    target_role = (
        await db.execute(select(HkRole).where(HkRole.id == target.role_id))
    ).scalar_one_or_none()
    if target_role is not None and target_role.code == "superadmin":
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "不能删除超级管理员")
    await db.delete(target)
    await admin_service.audit_admin(
        db, admin, "admin_delete", "admin_user", admin_id,
        f"username={target.username}")
    await db.commit()
    return {"ok": True}


# ---------- 仪表盘统计 ----------


@router.get("/stats")
async def admin_stats(
    admin: HkAdminUser = Depends(admin_service.require_admin_perm("page:dashboard")),
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

    # ── 图表序列 (近 14 天) ──
    day0 = today - timedelta(days=13)

    def _fill_days(rows, value_idx=1, value_cast=int):
        """补全缺日期: [(date, val)] → 连续 14 天."""
        m = {str(r[0]): value_cast(r[value_idx] or 0) for r in rows}
        return [
            {"date": str((day0 + timedelta(days=i)).date()),
             "value": m.get(str((day0 + timedelta(days=i)).date()), 0)}
            for i in range(14)
        ]

    user_rows = (
        await db.execute(
            select(func.date(HkUser.created_at), func.count())
            .where(HkUser.created_at >= day0)
            .group_by(func.date(HkUser.created_at))
        )
    ).all()
    deposit_rows = (
        await db.execute(
            select(func.date(HkDepositRecord.credited_at),
                   func.coalesce(func.sum(HkDepositRecord.amount), 0))
            .where(HkDepositRecord.status == "credited",
                   HkDepositRecord.credited_at >= day0)
            .group_by(func.date(HkDepositRecord.credited_at))
        )
    ).all()
    order_rows = (
        await db.execute(
            select(func.date(HkOrder.created_at),
                   func.coalesce(func.sum(HkOrder.amount), 0))
            .where(HkOrder.created_at >= day0)
            .group_by(func.date(HkOrder.created_at))
        )
    ).all()
    network_rows = (
        await db.execute(
            select(HkDepositRecord.network,
                   func.coalesce(func.sum(HkDepositRecord.amount), 0))
            .where(HkDepositRecord.status == "credited")
            .group_by(HkDepositRecord.network)
        )
    ).all()
    withdraw_rows = (
        await db.execute(
            select(HkWithdrawal.status, func.count())
            .group_by(HkWithdrawal.status)
        )
    ).all()

    return {
        "total_users": total_users,
        "today_users": today_users,
        "deposit_today": str(deposit_today),
        "deposit_total": str(deposit_total),
        "pending_withdrawals": pending_withdrawals,
        "order_total": str(order_total),
        "product_count": product_count,
        "user_series": _fill_days(user_rows),
        "deposit_series": _fill_days(deposit_rows, value_cast=lambda v: round(float(v), 2)),
        "order_series": _fill_days(order_rows, value_cast=lambda v: round(float(v), 2)),
        "network_dist": [
            {"network": n, "amount": round(float(a or 0), 2)}
            for n, a in network_rows
        ],
        "withdraw_status": [
            {"status": s_, "count": c} for s_, c in withdraw_rows
        ],
    }
