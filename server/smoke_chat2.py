"""IM 扩展冒烟: 文件上传/富媒体消息/群管理/留存清理. 端口 8124.

用法:
  python smoke_chat2.py          # HTTP + WS 全链路 (需服务已起)
  python smoke_chat2.py cleanup  # 仅留存清理函数 (直连 DB, 服务可停)
"""
import asyncio
import json
import os
import sys
from datetime import timedelta

BASE = "http://127.0.0.1:8124/api"
WS = "ws://127.0.0.1:8124/api/chat/ws"

# 1x1 透明 PNG
PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d494844520000000100000001080600000"
    "01f15c4890000000d49444154789c626001000000ffff030000060005"
    "57bfabd40000000049454e44ae426082"
)


async def register(c, name):
    import httpx
    r = await c.post("/auth/register", json={
        "username": name, "password": "password123",
        "email": f"{name}@test.com", "code": "000000"})
    if r.status_code == 409:
        r = await c.post("/auth/login", json={
            "username": name, "password": "password123"})
    r.raise_for_status()
    d = r.json()
    return d["token"], d["user"]["id"], d["user"]["username"]


async def http_flow():
    import httpx
    import websockets
    async with httpx.AsyncClient(base_url=BASE, timeout=15) as c:
        ta, ida, ua = await register(c, "smoke2_a")
        tb, idb, ub = await register(c, "smoke2_b")
        ha = {"Authorization": f"Bearer {ta}"}
        hb = {"Authorization": f"Bearer {tb}"}
        print("register ok:", ida, idb)

        # 好友 + 拉群
        await c.post("/chat/friends/request", json={"to_user_id": idb}, headers=ha)
        await c.post("/chat/friends/accept", json={"from_user_id": ida}, headers=hb)
        r = await c.post("/chat/conversations/group",
                         json={"name": "富媒体群", "member_ids": [idb]}, headers=ha)
        print("group:", r.status_code)
        gid = r.json()["id"]

        # 1. 上传 PNG
        r = await c.post("/chat/files", headers=ha,
                         files={"file": ("pic.png", PNG, "image/png")})
        print("upload:", r.status_code, r.json())
        assert r.status_code == 201
        file_url = r.json()["file_url"]
        assert file_url.startswith("/api/chat/files/")

        # 2. 回源文件 (无鉴权)
        r = await c.get(file_url)  # 相对 base_url=/api -> 需全路径
        if r.status_code == 404:  # base_url 前缀问题, 用绝对 url 重试
            r = await c.get("http://127.0.0.1:8124" + file_url)
        print("serve file:", r.status_code, "bytes:", len(r.content))
        assert r.status_code == 200 and r.content == PNG

        # 坏扩展名
        r = await c.post("/chat/files", headers=ha,
                         files={"file": ("x.exe", PNG, "application/octet-stream")})
        print("bad ext (expect 400):", r.status_code)
        assert r.status_code == 400

        # 3. WS b 在线, a 发图片消息
        async with websockets.connect(f"{WS}?token={tb}") as ws:
            r = await c.post(f"/chat/conversations/{gid}/messages",
                             json={"msg_type": "image", "file_url": file_url,
                                   "duration": None}, headers=ha)
            m = r.json()
            print("image msg:", r.status_code,
                  {k: m[k] for k in ("msg_type", "file_url", "duration", "content")})
            assert r.status_code == 201
            assert m["msg_type"] == "image" and m["file_url"] == file_url
            assert m["content"] == "" and m["duration"] is None
            # 既有字段不变
            assert {"id", "sender", "reply_to", "created_at", "reactions"} <= set(m)

            ev = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws msg event fields:",
                  {k: ev["message"][k] for k in ("msg_type", "file_url", "duration")})
            assert ev["type"] == "message"
            assert ev["message"]["msg_type"] == "image"
            assert ev["message"]["file_url"] == file_url

            # 4. 文本规则不变 + msg_type 白名单
            r = await c.post(f"/chat/conversations/{gid}/messages",
                             json={"content": "纯文本"}, headers=ha)
            print("text msg:", r.status_code, r.json()["msg_type"])
            assert r.status_code == 201 and r.json()["msg_type"] == "text"
            await ws.recv()  # 吞掉文本推送
            r = await c.post(f"/chat/conversations/{gid}/messages",
                             json={"msg_type": "image"}, headers=ha)
            print("image no file ok (content default ''):", r.status_code)
            await ws.recv()
            r = await c.post(f"/chat/conversations/{gid}/messages",
                             json={"content": "x", "msg_type": "bogus"}, headers=ha)
            print("bad msg_type (expect 422):", r.status_code)
            assert r.status_code == 422
            r = await c.post(f"/chat/conversations/{gid}/messages",
                             json={"msg_type": "text", "content": ""}, headers=ha)
            print("empty text (expect 422):", r.status_code)
            assert r.status_code == 422

            # 5. 成员列表 role
            r = await c.get(f"/chat/conversations/{gid}/members", headers=ha)
            print("members:", r.json())
            mem = r.json()
            assert mem[0]["role"] == "owner" and mem[0]["id"] == ida
            assert mem[1]["role"] == "member" and mem[1]["id"] == idb

            # 6. 改名: 群主 200, 非群主 403
            r = await c.put(f"/chat/conversations/{gid}",
                            json={"name": "新群名"}, headers=hb)
            print("rename non-owner (expect 403):", r.status_code)
            assert r.status_code == 403
            r = await c.put(f"/chat/conversations/{gid}",
                            json={"name": "新群名"}, headers=ha)
            print("rename owner:", r.status_code, r.json()["name"])
            assert r.status_code == 200 and r.json()["name"] == "新群名"
            ev = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws group_updated:", ev)
            assert ev["type"] == "group_updated" and ev["name"] == "新群名"

            # 7. 踢人: 群主 204, 被踢者收到 member_removed
            r = await c.delete(f"/chat/conversations/{gid}/members/{ida}", headers=ha)
            print("kick owner (expect 400):", r.status_code)
            assert r.status_code == 400
            r = await c.delete(f"/chat/conversations/{gid}/members/{idb}", headers=hb)
            print("kick non-owner (expect 403):", r.status_code)
            assert r.status_code == 403
            r = await c.delete(f"/chat/conversations/{gid}/members/{idb}", headers=ha)
            print("kick member:", r.status_code)
            assert r.status_code == 204
            ev = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws member_removed:", ev)
            assert ev["type"] == "member_removed" and ev["user_id"] == idb
            assert ev["username"] == ub

    print("HTTP-WS-SMOKE-OK")


async def cleanup_flow():
    """直连 DB: 造一条过期带文件消息 + 表情, 调 cleanup_old_messages 验证删除."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    from sqlalchemy import select
    from database import SessionLocal
    from models.hk import HkChatMessage, HkConversation, HkMessageReaction, utc_now
    from routers.chat import CHAT_UPLOAD_DIR
    from app import cleanup_old_messages

    async with SessionLocal() as db:
        conv = (await db.scalars(select(HkConversation).limit(1))).first()
        sender_id = conv.created_by
        old = HkChatMessage(
            conversation_id=conv.id, sender_id=sender_id, content="old",
            msg_type="image", file_url="/api/chat/files/olddead.png",
            status="visible", created_at=utc_now() - timedelta(days=8))
        db.add(old)
        await db.flush()
        db.add(HkMessageReaction(message_id=old.id, user_id=sender_id, emoji="👍"))
        await db.commit()
        old_id = old.id
    # 造对应磁盘文件
    CHAT_UPLOAD_DIR.mkdir(parents=True, exist_ok=True)
    fp = CHAT_UPLOAD_DIR / "olddead.png"
    fp.write_bytes(PNG)

    msgs, files = await cleanup_old_messages()
    print("cleanup counts: messages=%d files=%d" % (msgs, files))
    assert msgs >= 1 and files >= 1
    async with SessionLocal() as db:
        gone = await db.get(HkChatMessage, old_id)
        react = (await db.scalars(
            select(HkMessageReaction).where(
                HkMessageReaction.message_id == old_id))).all()
    print("old msg deleted:", gone is None, "| reactions deleted:", react == [],
          "| file deleted:", not fp.exists())
    assert gone is None and react == [] and not fp.exists()
    print("CLEANUP-SMOKE-OK")


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "cleanup":
        asyncio.run(cleanup_flow())
    else:
        asyncio.run(http_flow())
