"""用户查询后台路由 (管理员, Phase 8.3): 用户列表 / 单用户全量档案.

档案聚合: 账户余额 / 邀请关系 / 订单 / 充值 / 收益结算 / 佣金 / 提现 / 资金明细 / 等级变动.
只读, 不做任何修改 (调整权限矩阵 Phase 0.11 未拍板).
"""
from __future__ import annotations

from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import desc, select
from sqlalchemy.ext.asyncio import AsyncSession

from database import get_db
from models.account import HkAccount, HkBalanceLog, HkWithdrawal
from models.hk import HkUser
from models.invite import HkInvite
from models.level_log import HkLevelLog
from models.order import HkOrder
from models.account import HkDepositRecord
from models.settlement import HkCommissionRecord, HkSettlementRecord
from services import admin_service, auth_service, team_service, vip_service

router = APIRouter(prefix="/admin/users", tags=["后台-用户"])


class UserListItem(BaseModel):
    id: int
    username: str
    email: str
    status: str
    created_at: str
    vip_level: int
    team_level: int
    principal_balance: Decimal
    income_balance: Decimal
    principal_pending: Decimal
    income_pending: Decimal


@router.get("", response_model=list[UserListItem])
async def list_users(
    q: str | None = Query(default=None, description="用户名/邮箱模糊搜索"),
    limit: int = Query(default=100, le=500),
    user: HkUser = Depends(admin_service.require_admin),
    db: AsyncSession = Depends(get_db),
):
    """用户列表: 账户余额 + 当前 VIP/团队等级."""
    query = select(HkUser).order_by(desc(HkUser.id)).limit(limit)
    if q:
        like = f"%{q}%"
        query = select(HkUser).where(
            (HkUser.username.like(like)) | (HkUser.email.like(like))
        ).order_by(desc(HkUser.id)).limit(limit)
    rows = (await db.execute(query)).scalars().all()
    out = []
    for u in rows:
        acc = (
            await db.execute(select(HkAccount).where(HkAccount.user_id == u.id))
        ).scalar_one_or_none()
        vip = await vip_service.current_vip(db, u.id)
        members, holding = await team_service.team_stats(db, u.id)
        out.append(UserListItem(
            id=u.id, username=u.username, email=u.email, status=u.status,
            created_at=str(u.created_at),
            vip_level=vip["vip_level"],
            team_level=team_service.team_level(members, holding),
            principal_balance=acc.principal_balance if acc else 0,
            income_balance=acc.income_balance if acc else 0,
            principal_pending=acc.principal_pending if acc else 0,
            income_pending=acc.income_pending if acc else 0,
        ))
    return out


@router.get("/{user_id}")
async def user_profile(
    user_id: int,
    user: HkUser = Depends(admin_service.require_admin),
    db: AsyncSession = Depends(get_db),
):
    """单用户全量档案 (只读聚合)."""
    u = (
        await db.execute(select(HkUser).where(HkUser.id == user_id))
    ).scalar_one_or_none()
    if u is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "用户不存在")

    async def all_(stmt, limit=200):
        return list((await db.execute(stmt.limit(limit))).scalars().all())

    invite = (
        await db.execute(select(HkInvite).where(HkInvite.user_id == u.id))
    ).scalar_one_or_none()
    inviter_name = None
    if invite is not None and invite.inviter_id is not None:
        inviter = (
            await db.execute(select(HkUser).where(HkUser.id == invite.inviter_id))
        ).scalar_one_or_none()
        inviter_name = inviter.username if inviter else None

    vip = await vip_service.current_vip(db, u.id)
    members, holding = await team_service.team_stats(db, u.id)
    acc = (
        await db.execute(select(HkAccount).where(HkAccount.user_id == u.id))
    ).scalar_one_or_none()

    return {
        "user": {"id": u.id, "username": u.username, "email": u.email,
                 "status": u.status, "created_at": str(u.created_at)},
        "invite": {"invite_code": invite.invite_code if invite else None,
                   "inviter": inviter_name,
                   "bound_at": str(invite.bound_at) if invite else None},
        "levels": {"vip_level": vip["vip_level"],
                   "effective_holding": str(vip["effective_holding"]),
                   "team_level": team_service.team_level(members, holding),
                   "team_members": members, "team_holding": str(holding)},
        "account": {
            "principal_balance": str(acc.principal_balance) if acc else "0",
            "income_balance": str(acc.income_balance) if acc else "0",
            "principal_pending": str(acc.principal_pending) if acc else "0",
            "income_pending": str(acc.income_pending) if acc else "0",
        },
        "orders": [dict(id=o.id, product_name=o.product_name, amount=str(o.amount),
                        status=o.status, vip_level=o.vip_level,
                        lock_bonus_rate=str(o.lock_bonus_rate) if o.lock_bonus_rate is not None else None,
                        effective_at=str(o.effective_at), expires_at=str(o.expires_at))
                   for o in await all_(select(HkOrder).where(HkOrder.user_id == u.id).order_by(desc(HkOrder.id)))],
        "deposits": [dict(id=d.id, network=d.network, amount=str(d.amount), txid=d.txid,
                          status=d.status, confirmations=d.confirmations,
                          credited_at=str(d.credited_at))
                     for d in await all_(select(HkDepositRecord).where(HkDepositRecord.user_id == u.id).order_by(desc(HkDepositRecord.id)))],
        "settlements": [dict(id=s.id, order_id=s.order_id, period_no=s.period_no,
                             income_amount=str(s.income_amount),
                             principal_amount=str(s.principal_amount), created_at=str(s.created_at))
                        for s in await all_(select(HkSettlementRecord).where(HkSettlementRecord.user_id == u.id).order_by(desc(HkSettlementRecord.id)))],
        "commissions": [dict(id=x.id, order_id=x.order_id, gen=x.gen,
                             receiver_team_level=x.receiver_team_level, rate=str(x.rate),
                             amount=str(x.amount), created_at=str(x.created_at))
                        for x in await all_(select(HkCommissionRecord).where(HkCommissionRecord.receiver_id == u.id).order_by(desc(HkCommissionRecord.id)))],
        "withdrawals": [dict(id=w.id, account=w.account, network=w.network, address=w.address,
                             amount=str(w.amount), service_fee=str(w.service_fee),
                             network_fee=str(w.network_fee), status=w.status, txid=w.txid,
                             created_at=str(w.created_at))
                        for w in await all_(select(HkWithdrawal).where(HkWithdrawal.user_id == u.id).order_by(desc(HkWithdrawal.id)))],
        "balance_logs": [dict(id=b.id, account=b.account, change_type=b.change_type,
                              amount=str(b.amount), balance_after=str(b.balance_after),
                              ref_type=b.ref_type, ref_id=b.ref_id, created_at=str(b.created_at))
                         for b in await all_(select(HkBalanceLog).where(HkBalanceLog.user_id == u.id).order_by(desc(HkBalanceLog.id)))],
        "level_logs": [dict(id=l.id, kind=l.kind, level=l.level,
                            holding=str(l.holding) if l.holding is not None else None,
                            member_count=l.member_count, source=l.source,
                            created_at=str(l.created_at))
                       for l in await all_(select(HkLevelLog).where(HkLevelLog.user_id == u.id).order_by(desc(HkLevelLog.id)))],
    }
