"""聊天路由: 好友 / 会话 / 消息 / 表情回应 / WebSocket 实时推送."""
from __future__ import annotations

import asyncio

from fastapi import (
    APIRouter,
    Depends,
    HTTPException,
    Query,
    Response,
    WebSocket,
    WebSocketDisconnect,
    status,
)
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, Field
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

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

ALLOWED_EMOJIS = ("👍", "❤️", "🔥", "😂", "😮", "😢")


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
    content: str = Field(min_length=1, max_length=2000)
    reply_to_id: int | None = None


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
        },
        "content": msg.content,
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
                other_user = {"id": u.id, "username": u.username}
                name = u.username
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
        last_message = {
            "content": last.content,
            "sender_name": lsender.username if lsender else "",
            "created_at": last.created_at,
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
        {"id": u.id, "username": u.username, "relation": _relation(u.id)}
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
            select(HkUser.id, HkUser.username)
            .join(HkFriendship, HkFriendship.friend_id == HkUser.id)
            .where(HkFriendship.user_id == me.id)
            .order_by(HkUser.id)
        )
    ).all()
    return [{"id": r.id, "username": r.username} for r in rows]


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


# ---------- WebSocket ----------


@router.websocket("/ws")
async def chat_websocket(websocket: WebSocket, token: str = Query(default="")):
    """JWT 鉴权 + 心跳; 入站消息一律忽略 (已读走 REST)."""
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
            await websocket.receive_text()  # pong 等入站帧直接忽略
    except WebSocketDisconnect:
        pass
    finally:
        hb.cancel()
        await chat_ws.disconnect(user.id, websocket)
