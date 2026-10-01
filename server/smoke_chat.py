"""IM 冒烟测试: 注册→好友→会话→消息→表情→未读→WS."""
import asyncio
import json

import httpx
import websockets

BASE = "http://127.0.0.1:8123/api"
WS = "ws://127.0.0.1:8123/api/chat/ws"


async def main():
    async with httpx.AsyncClient(base_url=BASE, timeout=15) as c:
        # 1. 注册两个用户 (EMAIL_VERIFY_ENABLED=false, 跳过验证码)
        async def register(name):
            r = await c.post("/auth/register", json={
                "username": name, "password": "password123",
                "email": f"{name}@test.com", "code": "000000"})
            if r.status_code == 409:  # 已存在则登录
                r = await c.post("/auth/login", json={
                    "username": name, "password": "password123"})
            r.raise_for_status()
            d = r.json()
            return d["token"], d["user"]["id"], d["user"]["username"]

        ta, ida, _ = await register("chat_test_a")
        tb, idb, _ = await register("chat_test_b")
        ha = {"Authorization": f"Bearer {ta}"}
        hb = {"Authorization": f"Bearer {tb}"}
        print("register ok:", ida, idb)

        # 2. 搜索用户
        r = await c.get("/chat/users/search", params={"q": "chat_test"}, headers=ha)
        print("search:", r.status_code, r.json())

        # 3. 好友请求 a->b, b 接受
        r = await c.post("/chat/friends/request", json={"to_user_id": idb}, headers=ha)
        print("friend request:", r.status_code, r.json())
        r = await c.post("/chat/friends/request", json={"to_user_id": idb}, headers=ha)
        print("dup request (expect 400):", r.status_code)
        r = await c.get("/chat/friends/requests", headers=hb)
        print("b requests:", r.json())
        r = await c.post("/chat/friends/accept", json={"from_user_id": ida}, headers=hb)
        print("accept:", r.status_code, r.json())
        r = await c.get("/chat/friends", headers=ha)
        print("a friends:", r.json())

        # 4. 单聊会话
        r = await c.post("/chat/conversations/direct", json={"other_user_id": idb}, headers=ha)
        print("direct conv:", r.status_code, r.json())
        conv_id = r.json()["id"]
        r2 = await c.post("/chat/conversations/direct", json={"other_user_id": ida}, headers=hb)
        print("reuse conv (same id):", r2.json()["id"] == conv_id)

        # 5. WS 连接 b, 收 a 的消息推送
        async with websockets.connect(f"{WS}?token={tb}") as ws:
            # 6. a 发消息
            r = await c.post(f"/chat/conversations/{conv_id}/messages",
                             json={"content": "你好 b"}, headers=ha)
            print("send msg:", r.status_code, r.json())
            msg_id = r.json()["id"]
            push = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws push:", push["type"], push["conversation_id"] == conv_id,
                  push["message"]["content"], push["message"]["reactions"])

            # 7. b 回消息 (回复 a 的)
            r = await c.post(f"/chat/conversations/{conv_id}/messages",
                             json={"content": "你好 a", "reply_to_id": msg_id}, headers=hb)
            print("reply msg:", r.status_code, r.json()["reply_to"])
            # 收 b 自己消息的推送 (发送者也收, 多设备同步)
            ev = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws own-msg push:", ev["type"], ev["message"]["id"] == r.json()["id"])

            # 8. a 对 b 的消息表情 toggle 两次
            mid2 = r.json()["id"]
            r = await c.post(f"/chat/messages/{mid2}/reactions", json={"emoji": "👍"}, headers=ha)
            print("react on:", r.status_code, r.json())
            ev = json.loads(await asyncio.wait_for(ws.recv(), timeout=5))
            print("ws reaction event:", ev["type"], ev["reactions"])
            r = await c.post(f"/chat/messages/{mid2}/reactions", json={"emoji": "👍"}, headers=ha)
            print("react off:", r.json())
            r = await c.post(f"/chat/messages/{mid2}/reactions", json={"emoji": "😀"}, headers=ha)
            print("bad emoji (expect 400):", r.status_code)

        # 9. 消息列表 + 未读
        r = await c.get(f"/chat/conversations/{conv_id}/messages", headers=ha)
        print("messages:", r.status_code, [m["content"] for m in r.json()])
        r = await c.get("/chat/conversations", headers=ha)
        conv = [x for x in r.json() if x["id"] == conv_id][0]
        print("a unread (expect 1):", conv["unread_count"], "name:", conv["name"],
              "last:", conv["last_message"]["content"])
        r = await c.post(f"/chat/conversations/{conv_id}/read",
                         json={"message_id": mid2}, headers=ha)
        print("read:", r.json())
        r = await c.get("/chat/conversations", headers=ha)
        conv = [x for x in r.json() if x["id"] == conv_id][0]
        print("a unread after read (expect 0):", conv["unread_count"])

        # 10. 群聊
        r = await c.post("/chat/conversations/group",
                         json={"name": "测试群", "member_ids": [idb]}, headers=ha)
        print("group:", r.status_code, r.json()["type"], r.json()["member_count"])

        # 11. 非好友单聊 (expect 400) — 用第三个用户
        tc, idc, _ = await register("chat_test_c")
        hc = {"Authorization": f"Bearer {tc}"}
        r = await c.post("/chat/conversations/direct", json={"other_user_id": idc}, headers=ha)
        print("non-friend direct (expect 400):", r.status_code)

        # 12. 无认证 (expect 401/403)
        r = await c.get("/chat/conversations")
        print("no auth (expect 401/403):", r.status_code)

        # 13. WS 坏 token 断开
        try:
            async with websockets.connect(f"{WS}?token=bad") as ws:
                await ws.recv()
            print("ws bad token: NOT rejected (unexpected)")
        except websockets.exceptions.ConnectionClosedError as e:
            print("ws bad token closed:", e.code)

        # 14. 删好友
        r = await c.delete(f"/chat/friends/{idb}", headers=ha)
        print("delete friend:", r.status_code)
        r = await c.get("/chat/friends", headers=ha)
        print("a friends after delete:", r.json())

    print("SMOKE-ALL-DONE")


asyncio.run(main())
