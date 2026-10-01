"""聊天路由: 好友 / 会话 / 消息 / 表情回应 / 文件 / WebSocket 实时推送."""
from __future__ import annotations

import asyncio
import json
import logging
import re
from pathlib import Path
from uuid import uuid4

from fastapi import (
    APIRouter,
    Depends,
    File,
    HTTPException,
    Query,
    Request,
    Response,
    UploadFile,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.encoders import jsonable_encoder
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field, model_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from config import config
from database import SessionLocal, get_db
from models.hk import (
    HkChatMessage,
    HkConversation,
    HkConversationMember,
    HkFriendRequest,
    HkFriendship,
    HkMessageReaction,
    HkUser,
)
from services import auth_service
from services.chat_ws import chat_ws

router = APIRouter(prefix="/chat", tags=["聊天"])

logger = logging.getLogger(__name__)

ALLOWED_EMOJIS = ("👍", "❤️", "🔥", "😂", "😮", "😢")

# 富媒体消息
MSG_TYPES = ("text", "image", "audio", "video")
# 文件上传: 50MB, 扩展名白名单
MAX_FILE_SIZE = 50 * 1024 * 1024
ALLOWED_EXTS = {
    "jpg", "jpeg", "png", "webp", "gif",
    "mp4", "mov", "m4a", "aac", "mp3", "wav", "opus",
}
CHAT_UPLOAD_DIR = Path(config.upload_dir) / "chat"


# ---------- Schemas ----------


class FriendRequestIn(BaseModel):
    to_user_id: int


class FriendFromIn(BaseModel):
    from_user_id: int


class DirectConvIn(BaseModel):
    other_user_id: int


class GroupConvIn(BaseModel):
    name: str = Field(min_length=1, max_length=32)
    member_ids: list[int] = Field(default_factory=list)


class MessageIn(BaseModel):
    # 非文本消息 content 可省略 (默认 ''); 文本仍 1..2000, 由 validator 保证 422
    content: str = Field(default="", max_length=2000)
    reply_to_id: int | None = None
    msg_type: str = Field(default="text", max_length=16)
    file_url: str | None = Field(default=None, max_length=512)
    duration: int | None = None

    @model_validator(mode="after")
    def _check(self) -> "MessageIn":
        if self.msg_type not in MSG_TYPES:
            raise ValueError("不支持的消息类型")
        if self.msg_type == "text" and not 1 <= len(self.content) <= 2000:
            raise ValueError("文本内容长度需 1..2000")
        return self


class ConvRenameIn(BaseModel):
    name: str = Field(min_length=1, max_length=32)


class MemberAddIn(BaseModel):
    user_id: int


class ReadIn(BaseModel):
    message_id: int


class ReactionIn(BaseModel):
    emoji: str


# ---------- Helpers ----------


async def _are_friends(db: AsyncSession, a: int, b: int) -> bool:
    row = (
        await db.scalars(
            select(HkFriendship).where(
                HkFriendship.user_id == a, HkFriendship.friend_id == b
            )
        )
    ).first()
    return row is not None


async def _add_friendship(db: AsyncSession, a: int, b: int) -> None:
    """双向各插一行 (已存在则跳过)."""
    for u, f in ((a, b), (b, a)):
        if not await _are_friends(db, u, f):
            db.add(HkFriendship(user_id=u, friend_id=f))


async def _require_member(
    db: AsyncSession, conversation_id: int, user_id: int
) -> HkConversationMember:
    m = (
        await db.scalars(
            select(HkConversationMember).where(
                HkConversationMember.conversation_id == conversation_id,
                HkConversationMember.user_id == user_id,
            )
        )
    ).first()
    if m is None:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="非会话成员"
        )
    return m


async def _member_ids(db: AsyncSession, conversation_id: int) -> list[int]:
    rows = await db.scalars(
        select(HkConversationMember.user_id).where(
            HkConversationMember.conversation_id == conversation_id
        )
    )
    return list(rows.all())


async def _reactions_map(
    db: AsyncSession, message_ids: list[int], me_id: int
) -> dict[int, list[dict]]:
    """{message_id: [{emoji, count, mine}]} 按 count 降序."""
    if not message_ids:
        return {}
    rows = (
        await db.scalars(
            select(HkMessageReaction).where(
                HkMessageReaction.message_id.in_(message_ids)
            )
        )
    ).all()
    agg: dict[int, dict[str, dict]] = {}
    for r in rows:
        slot = agg.setdefault(r.message_id, {}).setdefault(
            r.emoji, {"emoji": r.emoji, "count": 0, "mine": False}
        )
        slot["count"] += 1
        if r.user_id == me_id:
            slot["mine"] = True
    return {
        mid: sorted(em.values(), key=lambda x: -x["count"])
        for mid, em in agg.items()
    }


async def _message_out(
    db: AsyncSession, msg: HkChatMessage, me_id: int,
    reactions: list[dict] | None = None,
) -> dict:
    sender = await db.get(HkUser, msg.sender_id)
    reply_to = None
    if msg.reply_to_id is not None:
        parent = await db.get(HkChatMessage, msg.reply_to_id)
        if parent is not None and parent.status == "visible":
            psender = await db.get(HkUser, parent.sender_id)
            reply_to = {
                "id": parent.id,
                "sender_name": psender.username if psender else "",
                "content": parent.content,
            }
    if reactions is None:
        reactions = (await _reactions_map(db, [msg.id], me_id)).get(msg.id, [])
    return {
        "id": msg.id,
        "sender": {
            "id": msg.sender_id,
            "username": sender.username if sender else "",
            "nickname": sender.nickname if sender else None,
            "avatar_url": sender.avatar_url if sender else None,
        },
        "content": msg.content,
        "msg_type": msg.msg_type,
        "file_url": msg.file_url,
        "duration": msg.duration,
        "reply_to": reply_to,
        "created_at": msg.created_at,
        "reactions": reactions,
    }


async def _conv_out(
    db: AsyncSession, conv: HkConversation, me: HkUser
) -> tuple[dict, float | None]:
    """会话对象 + 排序时间戳 (无消息为 None)."""
    members = (
        await db.scalars(
            select(HkConversationMember).where(
                HkConversationMember.conversation_id == conv.id
            )
        )
    ).all()
    other_user = None
    name = conv.name
    if conv.type == "direct":
        other_id = next((m.user_id for m in members if m.user_id != me.id), None)
        if other_id is not None:
            u = await db.get(HkUser, other_id)
            if u is not None:
                other_user = {
                    "id": u.id,
                    "username": u.username,
                    "nickname": u.nickname,
                    "avatar_url": u.avatar_url,
                }
                name = u.nickname or u.username
    last = (
        await db.scalars(
            select(HkChatMessage)
            .where(
                HkChatMessage.conversation_id == conv.id,
                HkChatMessage.status == "visible",
            )
            .order_by(HkChatMessage.id.desc())
            .limit(1)
        )
    ).first()
    last_message = None
    sort_ts = None
    if last is not None:
        lsender = await db.get(HkUser, last.sender_id)
        is_mine = last.sender_id == me.id
        # 已读回执: 仅单聊且最后一条是我发的才有意义
        read = None
        if conv.type == "direct" and is_mine:
            other_member = next(
                (m for m in members if m.user_id != me.id), None
            )
            if other_member is not None:
                read = other_member.last_read_message_id >= last.id
        last_message = {
            "id": last.id,  # 前端 WS read 事件按 id 比对回执
            "msg_type": last.msg_type,  # 列表预览 [图片]/[语音]/[视频]
            "content": last.content,
            "sender_name": (lsender.nickname or lsender.username) if lsender else "",
            "created_at": last.created_at,
            "is_mine": is_mine,
            "read": read,
        }
        sort_ts = last.created_at.timestamp()
    my = next((m for m in members if m.user_id == me.id), None)
    unread = 0
    if my is not None:
        unread = (
            await db.scalar(
                select(func.count())
                .select_from(HkChatMessage)
                .where(
                    HkChatMessage.conversation_id == conv.id,
                    HkChatMessage.id > my.last_read_message_id,
                    HkChatMessage.sender_id != me.id,
                    HkChatMessage.status == "visible",
                )
            )
            or 0
        )
    return {
        "id": conv.id,
        "type": conv.type,
        "name": name,
        "member_count": len(members),
        "other_user": other_user,
        "last_message": last_message,
        "unread_count": unread,
    }, sort_ts


# ---------- 用户搜索 ----------


@router.get("/users/search")
async def search_users(
    q: str = Query(min_length=1),
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    users = (
        await db.scalars(
            select(HkUser)
            .where(HkUser.username.ilike(f"%{q}%"))
            .order_by(HkUser.id)
            .limit(20)
        )
    ).all()
    if not users:
        return []
    ids = [u.id for u in users]
    friend_ids = set(
        (
            await db.scalars(
                select(HkFriendship.friend_id).where(
                    HkFriendship.user_id == me.id,
                    HkFriendship.friend_id.in_(ids),
                )
            )
        ).all()
    )
    outgoing = set(
        (
            await db.scalars(
                select(HkFriendRequest.to_user_id).where(
                    HkFriendRequest.from_user_id == me.id,
                    HkFriendRequest.to_user_id.in_(ids),
                    HkFriendRequest.status == "pending",
                )
            )
        ).all()
    )
    incoming = set(
        (
            await db.scalars(
                select(HkFriendRequest.from_user_id).where(
                    HkFriendRequest.to_user_id == me.id,
                    HkFriendRequest.from_user_id.in_(ids),
                    HkFriendRequest.status == "pending",
                )
            )
        ).all()
    )

    def _relation(uid: int) -> str:
        if uid == me.id:
            return "self"
        if uid in friend_ids:
            return "friend"
        if uid in outgoing:
            return "outgoing"
        if uid in incoming:
            return "incoming"
        return "none"

    return [
        {
            "id": u.id,
            "username": u.username,
            "nickname": u.nickname,
            "avatar_url": u.avatar_url,
            "relation": _relation(u.id),
        }
        for u in users
    ]


# ---------- 好友 ----------


@router.post("/friends/request", status_code=201)
async def send_friend_request(
    data: FriendRequestIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    if data.to_user_id == me.id:
        raise HTTPException(status_code=400, detail="不能添加自己")
    target = await db.get(HkUser, data.to_user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="用户不存在")
    if await _are_friends(db, me.id, data.to_user_id):
        raise HTTPException(status_code=400, detail="已是好友")
    dup = (
        await db.scalars(
            select(HkFriendRequest).where(
                HkFriendRequest.from_user_id == me.id,
                HkFriendRequest.to_user_id == data.to_user_id,
                HkFriendRequest.status == "pending",
            )
        )
    ).first()
    if dup is not None:
        raise HTTPException(status_code=400, detail="申请已发送, 请勿重复")
    # 对方已向我发过申请: 直接互相通过
    reverse = (
        await db.scalars(
            select(HkFriendRequest).where(
                HkFriendRequest.from_user_id == data.to_user_id,
                HkFriendRequest.to_user_id == me.id,
                HkFriendRequest.status == "pending",
            )
        )
    ).first()
    if reverse is not None:
        reverse.status = "accepted"
        await _add_friendship(db, me.id, data.to_user_id)
        await db.commit()
        return {"ok": True}
    db.add(
        HkFriendRequest(
            from_user_id=me.id, to_user_id=data.to_user_id, status="pending"
        )
    )
    await db.commit()
    await chat_ws.deliver_to_user(
        data.to_user_id,
        {
            "type": "friend_request",
            "from_user": {"id": me.id, "username": me.username},
        },
    )
    return {"ok": True}


@router.post("/friends/accept")
async def accept_friend_request(
    data: FriendFromIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    req = (
        await db.scalars(
            select(HkFriendRequest).where(
                HkFriendRequest.from_user_id == data.from_user_id,
                HkFriendRequest.to_user_id == me.id,
                HkFriendRequest.status == "pending",
            )
        )
    ).first()
    if req is None:
        raise HTTPException(status_code=404, detail="无待处理申请")
    req.status = "accepted"
    await _add_friendship(db, me.id, data.from_user_id)
    await db.commit()
    return {"ok": True}


@router.post("/friends/reject")
async def reject_friend_request(
    data: FriendFromIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    req = (
        await db.scalars(
            select(HkFriendRequest).where(
                HkFriendRequest.from_user_id == data.from_user_id,
                HkFriendRequest.to_user_id == me.id,
                HkFriendRequest.status == "pending",
            )
        )
    ).first()
    if req is None:
        raise HTTPException(status_code=404, detail="无待处理申请")
    req.status = "rejected"
    await db.commit()
    return {"ok": True}


@router.delete("/friends/{user_id}", status_code=204)
async def delete_friend(
    user_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    await db.execute(
        delete(HkFriendship).where(
            (
                (HkFriendship.user_id == me.id)
                & (HkFriendship.friend_id == user_id)
            )
            | (
                (HkFriendship.user_id == user_id)
                & (HkFriendship.friend_id == me.id)
            )
        )
    )
    await db.commit()
    return Response(status_code=204)


@router.get("/friends")
async def list_friends(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    rows = (
        await db.execute(
            select(HkUser.id, HkUser.username, HkUser.nickname, HkUser.avatar_url)
            .join(HkFriendship, HkFriendship.friend_id == HkUser.id)
            .where(HkFriendship.user_id == me.id)
            .order_by(HkUser.id)
        )
    ).all()
    return [
        {
            "id": r.id,
            "username": r.username,
            "nickname": r.nickname,
            "avatar_url": r.avatar_url,
        }
        for r in rows
    ]


@router.get("/friends/online")
async def list_online_friends(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """我的好友中当前在线 (有 WS 连接) 的用户 id 列表."""
    friend_ids = set(
        (
            await db.scalars(
                select(HkFriendship.friend_id).where(
                    HkFriendship.user_id == me.id
                )
            )
        ).all()
    )
    online = await chat_ws.online_user_ids()
    return {"online_ids": sorted(friend_ids & online)}


@router.get("/turn-servers")
async def get_turn_servers(
    me: HkUser = Depends(auth_service.get_current_user),
):
    """通话 TURN 配置下发 (与 okx 共用 coturn; 未配置返回空列表, 前端退回仅 STUN)."""
    if not config.turn_urls or not config.turn_username:
        return {"servers": []}
    return {
        "servers": [
            {
                "urls": [u.strip() for u in config.turn_urls.split(",") if u.strip()],
                "username": config.turn_username,
                "credential": config.turn_credential,
            }
        ]
    }


@router.get("/friends/requests")
async def list_friend_requests(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    incoming = (
        await db.execute(
            select(HkUser.id, HkUser.username, HkFriendRequest.created_at)
            .join(HkFriendRequest, HkFriendRequest.from_user_id == HkUser.id)
            .where(
                HkFriendRequest.to_user_id == me.id,
                HkFriendRequest.status == "pending",
            )
            .order_by(HkFriendRequest.id.desc())
        )
    ).all()
    outgoing = (
        await db.execute(
            select(HkUser.id, HkUser.username, HkFriendRequest.created_at)
            .join(HkFriendRequest, HkFriendRequest.to_user_id == HkUser.id)
            .where(
                HkFriendRequest.from_user_id == me.id,
                HkFriendRequest.status == "pending",
            )
            .order_by(HkFriendRequest.id.desc())
        )
    ).all()

    def _rows(rows):
        return [
            {"id": r.id, "username": r.username, "created_at": r.created_at}
            for r in rows
        ]

    return {"incoming": _rows(incoming), "outgoing": _rows(outgoing)}


# ---------- 会话 ----------


@router.post("/conversations/direct", status_code=201)
async def create_direct_conversation(
    data: DirectConvIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    other = await db.get(HkUser, data.other_user_id)
    if other is None:
        raise HTTPException(status_code=404, detail="用户不存在")
    if not await _are_friends(db, me.id, data.other_user_id):
        raise HTTPException(status_code=400, detail="非好友不能发起单聊")
    # 复用已有单聊: 我的会话中与对方共存的 direct 会话
    my_convs = select(HkConversationMember.conversation_id).where(
        HkConversationMember.user_id == me.id
    )
    existing = (
        await db.scalars(
            select(HkConversation)
            .join(
                HkConversationMember,
                HkConversationMember.conversation_id == HkConversation.id,
            )
            .where(
                HkConversation.type == "direct",
                HkConversationMember.conversation_id.in_(my_convs),
                HkConversationMember.user_id == data.other_user_id,
            )
            .limit(1)
        )
    ).first()
    conv = existing
    if conv is None:
        conv = HkConversation(type="direct", created_by=me.id)
        db.add(conv)
        await db.flush()
        db.add(HkConversationMember(conversation_id=conv.id, user_id=me.id))
        db.add(
            HkConversationMember(conversation_id=conv.id, user_id=other.id)
        )
        await db.commit()
        await db.refresh(conv)
    out, _ = await _conv_out(db, conv, me)
    return out


@router.post("/conversations/group", status_code=201)
async def create_group_conversation(
    data: GroupConvIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    member_ids = [i for i in dict.fromkeys(data.member_ids) if i != me.id]
    for uid in member_ids:
        if not await _are_friends(db, me.id, uid):
            raise HTTPException(
                status_code=400, detail=f"用户 {uid} 不是好友, 无法拉群"
            )
    conv = HkConversation(type="group", name=data.name, created_by=me.id)
    db.add(conv)
    await db.flush()
    db.add(HkConversationMember(conversation_id=conv.id, user_id=me.id))
    for uid in member_ids:
        db.add(HkConversationMember(conversation_id=conv.id, user_id=uid))
    await db.commit()
    await db.refresh(conv)
    out, _ = await _conv_out(db, conv, me)
    return out


@router.get("/conversations")
async def list_conversations(
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    convs = (
        await db.scalars(
            select(HkConversation)
            .join(
                HkConversationMember,
                HkConversationMember.conversation_id == HkConversation.id,
            )
            .where(HkConversationMember.user_id == me.id)
        )
    ).all()
    items = [await _conv_out(db, c, me) for c in convs]
    # 最新消息时间降序, 无消息排最后
    items.sort(key=lambda x: (x[1] is None, -(x[1] or 0)))
    return [it[0] for it in items]


@router.delete("/conversations/{conversation_id}", status_code=204)
async def delete_conversation(
    conversation_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    member = await _require_member(db, conversation_id, me.id)
    await db.delete(member)  # 单聊=对我隐藏, 群聊=退群
    await db.commit()
    return Response(status_code=204)


@router.get("/conversations/{conversation_id}/members")
async def list_members(
    conversation_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """成员列表: owner(创建者) 在前, role owner/member."""
    await _require_member(db, conversation_id, me.id)
    conv = await db.get(HkConversation, conversation_id)
    rows = (
        await db.execute(
            select(HkUser.id, HkUser.username, HkUser.nickname, HkUser.avatar_url)
            .join(
                HkConversationMember,
                HkConversationMember.user_id == HkUser.id,
            )
            .where(HkConversationMember.conversation_id == conversation_id)
            .order_by(HkConversationMember.id)
        )
    ).all()
    members = [
        {
            "id": r.id,
            "username": r.username,
            "nickname": r.nickname,
            "avatar_url": r.avatar_url,
            "role": "owner" if conv and r.id == conv.created_by else "member",
        }
        for r in rows
    ]
    members.sort(key=lambda m: 0 if m["role"] == "owner" else 1)
    return members


@router.put("/conversations/{conversation_id}")
async def rename_conversation(
    conversation_id: int,
    data: ConvRenameIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """改群名: 仅群聊群主."""
    await _require_member(db, conversation_id, me.id)
    conv = await db.get(HkConversation, conversation_id)
    if conv is None or conv.type != "group" or conv.created_by != me.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="仅群主可修改群信息"
        )
    conv.name = data.name
    await db.commit()
    await db.refresh(conv)
    member_ids = await _member_ids(db, conversation_id)
    await chat_ws.deliver_to_users(
        member_ids,
        {
            "type": "group_updated",
            "conversation_id": conversation_id,
            "name": conv.name,
        },
    )
    out, _ = await _conv_out(db, conv, me)
    return out


@router.post("/conversations/{conversation_id}/members", status_code=201)
async def add_member(
    conversation_id: int,
    data: MemberAddIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """拉人进群: 群内任一成员均可添加 (微信式), 无需群主."""
    await _require_member(db, conversation_id, me.id)
    conv = await db.get(HkConversation, conversation_id)
    if conv is None or conv.type != "group":
        raise HTTPException(status_code=400, detail="仅群聊可添加成员")
    target = await db.get(HkUser, data.user_id)
    if target is None:
        raise HTTPException(status_code=404, detail="用户不存在")
    exists = (
        await db.scalars(
            select(HkConversationMember).where(
                HkConversationMember.conversation_id == conversation_id,
                HkConversationMember.user_id == data.user_id,
            )
        )
    ).first()
    if exists is not None:
        raise HTTPException(status_code=400, detail="对方已在群内")
    db.add(
        HkConversationMember(
            conversation_id=conversation_id, user_id=data.user_id
        )
    )
    await db.commit()
    # 含新成员在内的全员广播: 老成员更新人数, 新成员刷新会话列表出现该群.
    member_ids = await _member_ids(db, conversation_id)
    await chat_ws.deliver_to_users(
        member_ids,
        {
            "type": "member_added",
            "conversation_id": conversation_id,
            "user_id": target.id,
            "username": target.username,
            "member_count": len(member_ids),
        },
    )
    return {"ok": True, "member_count": len(member_ids)}


@router.delete("/conversations/{conversation_id}/members/{user_id}", status_code=204)
async def remove_member(
    conversation_id: int,
    user_id: int,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """踢人: 仅群聊群主; 不能移除群主."""
    await _require_member(db, conversation_id, me.id)
    conv = await db.get(HkConversation, conversation_id)
    if conv is None or conv.type != "group" or conv.created_by != me.id:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN, detail="仅群主可移除成员"
        )
    if user_id == conv.created_by:
        raise HTTPException(status_code=400, detail="不能移除群主")
    target = (
        await db.scalars(
            select(HkConversationMember).where(
                HkConversationMember.conversation_id == conversation_id,
                HkConversationMember.user_id == user_id,
            )
        )
    ).first()
    if target is None:
        raise HTTPException(status_code=404, detail="成员不存在")
    target_user = await db.get(HkUser, user_id)
    username = target_user.username if target_user else ""
    # 推给所有当前成员 + 被踢者 (删除前先取名单)
    member_ids = await _member_ids(db, conversation_id)
    await db.delete(target)
    await db.commit()
    await chat_ws.deliver_to_users(
        member_ids,
        {
            "type": "member_removed",
            "conversation_id": conversation_id,
            "user_id": user_id,
            "username": username,
        },
    )
    return Response(status_code=204)


@router.post("/conversations/{conversation_id}/read")
async def mark_read(
    conversation_id: int,
    data: ReadIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    member = await _require_member(db, conversation_id, me.id)
    if data.message_id > member.last_read_message_id:
        member.last_read_message_id = data.message_id
        await db.commit()
        # 推已读事件给其他成员: 发送方列表回执实时变双勾
        others = (
            await db.scalars(
                select(HkConversationMember.user_id).where(
                    HkConversationMember.conversation_id == conversation_id,
                    HkConversationMember.user_id != me.id,
                )
            )
        ).all()
        await chat_ws.deliver_to_users(
            list(others),
            {
                "type": "read",
                "conversation_id": conversation_id,
                "reader_id": me.id,
                "message_id": data.message_id,
            },
        )
    return {"ok": True}


# ---------- 消息 ----------


@router.get("/conversations/{conversation_id}/messages")
async def list_messages(
    conversation_id: int,
    before_id: int | None = None,
    limit: int = Query(50, ge=1, le=100),
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    await _require_member(db, conversation_id, me.id)
    stmt = select(HkChatMessage).where(
        HkChatMessage.conversation_id == conversation_id,
        HkChatMessage.status == "visible",
    )
    if before_id is not None:
        stmt = stmt.where(HkChatMessage.id < before_id)
    msgs = (
        await db.scalars(
            stmt.order_by(HkChatMessage.id.desc()).limit(limit)
        )
    ).all()
    reactions = await _reactions_map(db, [m.id for m in msgs], me.id)
    return [
        await _message_out(db, m, me.id, reactions.get(m.id, []))
        for m in msgs
    ]


@router.post("/conversations/{conversation_id}/messages", status_code=201)
async def send_message(
    conversation_id: int,
    data: MessageIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    await _require_member(db, conversation_id, me.id)
    if data.reply_to_id is not None:
        parent = await db.get(HkChatMessage, data.reply_to_id)
        if parent is None or parent.conversation_id != conversation_id:
            raise HTTPException(status_code=400, detail="被回复的消息不存在")
    msg = HkChatMessage(
        conversation_id=conversation_id,
        sender_id=me.id,
        content=data.content,
        reply_to_id=data.reply_to_id,
        msg_type=data.msg_type,
        file_url=data.file_url,
        duration=data.duration,
        status="visible",
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    out = await _message_out(db, msg, me.id, reactions=[])
    member_ids = await _member_ids(db, conversation_id)
    # jsonable_encoder: created_at datetime 需转 ISO, send_json 直接 json.dumps
    await chat_ws.deliver_to_users(
        member_ids,
        {
            "type": "message",
            "conversation_id": conversation_id,
            "message": jsonable_encoder(out),
        },
    )
    return out


# ---------- 表情回应 ----------


@router.post("/messages/{message_id}/reactions")
async def toggle_reaction(
    message_id: int,
    data: ReactionIn,
    db: AsyncSession = Depends(get_db),
    me: HkUser = Depends(auth_service.get_current_user),
):
    if data.emoji not in ALLOWED_EMOJIS:
        raise HTTPException(status_code=400, detail="不支持的表情")
    msg = await db.get(HkChatMessage, message_id)
    if msg is None or msg.status != "visible":
        raise HTTPException(status_code=404, detail="消息不存在")
    await _require_member(db, msg.conversation_id, me.id)
    existing = (
        await db.scalars(
            select(HkMessageReaction).where(
                HkMessageReaction.message_id == message_id,
                HkMessageReaction.user_id == me.id,
                HkMessageReaction.emoji == data.emoji,
            )
        )
    ).first()
    if existing is None:
        db.add(
            HkMessageReaction(
                message_id=message_id, user_id=me.id, emoji=data.emoji
            )
        )
    else:
        await db.delete(existing)
    await db.commit()
    reactions = (await _reactions_map(db, [message_id], me.id)).get(
        message_id, []
    )
    member_ids = await _member_ids(db, msg.conversation_id)
    await chat_ws.deliver_to_users(
        member_ids,
        {
            "type": "reaction",
            "conversation_id": msg.conversation_id,
            "message_id": message_id,
            "reactions": reactions,
        },
    )
    return {"reactions": reactions}


# ---------- 文件 ----------


@router.post("/files", status_code=201)
async def upload_chat_file(
    request: Request,
    file: UploadFile = File(...),
    me: HkUser = Depends(auth_service.get_current_user),
):
    """聊天附件上传: multipart 字段名 file, 50MB 上限, 扩展名白名单."""
    cl = request.headers.get("content-length")
    if cl and cl.isdigit() and int(cl) > MAX_FILE_SIZE:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="文件超过 50MB",
        )
    ext = ""
    if file.filename and "." in file.filename:
        ext = file.filename.rsplit(".", 1)[-1].lower()
    if ext not in ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail="不支持的文件类型")
    name = f"{uuid4().hex}.{ext}"
    dest = CHAT_UPLOAD_DIR / name
    CHAT_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    size = 0
    try:
        with open(dest, "wb") as f:
            while chunk := await file.read(1024 * 1024):
                size += len(chunk)
                if size > MAX_FILE_SIZE:
                    raise HTTPException(
                        status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                        detail="文件超过 50MB",
                    )
                f.write(chunk)
    except Exception:
        dest.unlink(missing_ok=True)  # 失败清理半成品
        raise
    # URL 不带扩展名: 宝塔/nginx 按 .png 等后缀拦截静态请求, 会绕过代理 404
    return {"file_url": f"/api/chat/files/{name.split('.')[0]}"}


@router.get("/files/{name}")
async def get_chat_file(name: str):
    """按文件 id 回源 (uuid 无扩展名, 磁盘按 uuid.* glob); 防路径穿越. 无需鉴权."""
    safe = Path(name).name
    if not safe or safe != name:
        raise HTTPException(status_code=404, detail="文件不存在")
    path: Path | None = None
    if re.fullmatch(r"[A-Za-z0-9]+", safe):  # 纯 uuid 才走 glob, 防通配符注入
        matches = list(CHAT_UPLOAD_DIR.glob(f"{safe}.*"))
        if matches:
            path = matches[0]
    if path is None and "." in safe:  # 兼容存量 uuid.ext 直链
        p = CHAT_UPLOAD_DIR / safe
        if p.is_file():
            path = p
    if path is None:
        raise HTTPException(status_code=404, detail="文件不存在")
    return FileResponse(path)


# ---------- WebSocket ----------

# WebRTC 通话信令中继: 仅转发, 无状态/不存储/不管媒体
CALL_TYPES = ("call_invite", "call_accept", "call_reject", "call_cancel",
              "call_end", "call_signal")


async def _relay_call(me: HkUser, frame: dict) -> None:
    """校验好友关系 + 在线状态后转发信令给目标; 异常帧静默忽略."""
    to_user_id = frame.get("to_user_id")
    if not isinstance(to_user_id, int):
        return
    call_id = frame.get("call_id")
    async with SessionLocal() as db:
        if not await _are_friends(db, me.id, to_user_id):
            # 非好友: 回错误给主叫, 不转发
            await chat_ws.deliver_to_user(
                me.id,
                {"type": "call_error", "call_id": call_id, "reason": "not_friend"},
            )
            return
    if to_user_id not in await chat_ws.online_user_ids():
        # 目标离线: 告知主叫不可达
        await chat_ws.deliver_to_user(
            me.id,
            {"type": "call_unavailable", "call_id": call_id, "to_user_id": to_user_id},
        )
        return
    if frame.get("type") in ("call_invite", "call_end"):
        logger.info(
            "call_relay",
            extra={"type": frame["type"], "call_id": call_id,
                   "from": me.id, "to": to_user_id},
        )
    # 注入主叫身份后原样转发
    frame["from_user"] = {"id": me.id, "username": me.username}
    await chat_ws.deliver_to_user(to_user_id, frame)


@router.websocket("/ws")
async def chat_websocket(websocket: WebSocket, token: str = Query(default="")):
    """JWT 鉴权 + 心跳; 通话信令中继, 其余入站帧忽略 (已读走 REST)."""
    payload = auth_service.decode_token(token)
    user_id = None
    if payload and payload.get("sub"):
        try:
            user_id = int(payload["sub"])
        except (TypeError, ValueError):
            user_id = None
    user = None
    if user_id is not None:
        async with SessionLocal() as db:
            user = await db.get(HkUser, user_id)
    if user is None:
        # 先 accept 再 close: 未 accept 时 close 只会变成 HTTP 403 握手拒绝,
        # 4401 自定义码发不到客户端
        await websocket.accept()
        await websocket.close(code=4401)
        return
    await websocket.accept()
    await chat_ws.connect(user.id, websocket)

    async def _heartbeat() -> None:
        try:
            while True:
                await asyncio.sleep(25)
                await websocket.send_json({"type": "ping"})
        except Exception:
            pass

    hb = asyncio.create_task(_heartbeat())
    try:
        while True:
            raw = await websocket.receive_text()
            try:
                frame = json.loads(raw)
            except (TypeError, ValueError):
                continue  # 非 JSON: pong 等, 忽略
            if isinstance(frame, dict) and frame.get("type") in CALL_TYPES:
                await _relay_call(user, frame)
    except WebSocketDisconnect:
        pass
    finally:
        hb.cancel()
        await chat_ws.disconnect(user.id, websocket)
