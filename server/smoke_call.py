"""WebRTC 通话信令中继冒烟: 好友转发 / 非好友拒绝 / 离线不可达."""
import asyncio
import json

import httpx
import websockets

BASE = "http://127.0.0.1:8126/api"
WS = "ws://127.0.0.1:8126/api/chat/ws"


async def register(c, name):
    r = await c.post("/auth/register", json={
        "username": name, "password": "password123",
        "email": f"{name}@test.com", "code": "000000"})
    if r.status_code == 409:
        r = await c.post("/auth/login", json={
            "username": name, "password": "password123"})
    r.raise_for_status()
    d = r.json()
    return d["token"], d["user"]["id"], d["user"]["username"]


async def recv(ws, t=5):
    return json.loads(await asyncio.wait_for(ws.recv(), timeout=t))


async def expect_silence(ws, t=1.5):
    try:
        m = await asyncio.wait_for(ws.recv(), timeout=t)
        return f"UNEXPECTED: {m}"
    except asyncio.TimeoutError:
        return "silent-ok"


async def main():
    async with httpx.AsyncClient(base_url=BASE, timeout=15) as c:
        ta, ida, na = await register(c, "call_a")
        tb, idb, nb = await register(c, "call_b")
        tc, idc, nc = await register(c, "call_c")
        td, idd, nd = await register(c, "call_d")
        ha = {"Authorization": f"Bearer {ta}"}
        hb = {"Authorization": f"Bearer {tb}"}
        print("users:", ida, idb, idc, idd)

        # a-b 好友, a-d 好友(d 永不上线), c 与所有人非好友
        for (h, fid) in ((ha, idb), (ha, idd)):
            await c.post("/chat/friends/request", json={"to_user_id": fid}, headers=h)
        await c.post("/chat/friends/accept", json={"from_user_id": ida}, headers=hb)
        hd = {"Authorization": f"Bearer {td}"}
        await c.post("/chat/friends/accept", json={"from_user_id": ida}, headers=hd)
        print("friends established: a-b, a-d")

        cid = "uuid-1"
        async with websockets.connect(f"{WS}?token={ta}") as wsa, \
                   websockets.connect(f"{WS}?token={tb}") as wsb, \
                   websockets.connect(f"{WS}?token={tc}") as wsc:
            # 1. A 邀请 B -> B 收 call_invite 带 from_user
            await wsa.send(json.dumps({"type": "call_invite", "call_id": cid,
                                       "to_user_id": idb, "conversation_id": 1}))
            m = await recv(wsb)
            print("1 B got invite:", m["type"] == "call_invite",
                  m.get("from_user") == {"id": ida, "username": na})

            # 2. B 回信号 -> A 收 call_signal 带 from_user
            await wsb.send(json.dumps({"type": "call_signal", "call_id": cid,
                                       "to_user_id": ida,
                                       "data": {"sdp": "offer-x"}}))
            m = await recv(wsa)
            print("2 A got signal:", m["type"] == "call_signal",
                  m["data"] == {"sdp": "offer-x"},
                  m.get("from_user") == {"id": idb, "username": nb})

            # 3. C(非好友) 邀请 A -> A 无消息, C 收 not_friend
            await wsc.send(json.dumps({"type": "call_invite", "call_id": "uuid-c",
                                       "to_user_id": ida}))
            m = await recv(wsc)
            print("3 C got not_friend:", m["type"] == "call_error",
                  m["reason"] == "not_friend")
            print("3 A silence:", await expect_silence(wsa))

            # 4. A 邀请离线 D(好友) -> A 收 call_unavailable
            await wsa.send(json.dumps({"type": "call_invite", "call_id": "uuid-d",
                                       "to_user_id": idd}))
            m = await recv(wsa)
            print("4 A got unavailable:", m["type"] == "call_unavailable",
                  m["to_user_id"] == idd)

            # 5. 畸形帧忽略: 缺 to_user_id / 非 JSON
            await wsa.send(json.dumps({"type": "call_invite", "call_id": "x"}))
            await wsa.send("not-json")
            print("5 malformed ignored:", await expect_silence(wsa))

    print("SMOKE-CALL-DONE")


asyncio.run(main())
