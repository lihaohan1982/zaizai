"""
Location Chat Backend - FastAPI Server
"""
import asyncio
import json
import uuid
import hashlib
from datetime import datetime, timedelta
from typing import Optional, List, Dict, Any

from fastapi import FastAPI, WebSocket, WebSocketDisconnect, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
import aiomysql
import redis.asyncio as redis

# ============ Config ============
MYSQL_CONF = {
    "host": "127.0.0.1",
    "port": 3307,
    "user": "root",
    "password": "qclaw_root_pass_2026",
    "db": "location_chat",
    "charset": "utf8mb4",
    "autocommit": True,
}
REDIS_CONF = {"host": "127.0.0.1", "port": 6380, "db": 0, "decode_responses": True}
JWT_SECRET = "location-chat-secret-2026"
JWT_ALG = "HS256"

# ============ App ============
app = FastAPI(title="Location Chat API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ============ DB Pool ============
pool: Optional[aiomysql.Pool] = None
redis_client: Optional[redis.Redis] = None


@app.on_event("startup")
async def startup():
    global pool, redis_client
    pool = await aiomysql.create_pool(**MYSQL_CONF, minsize=1, maxsize=10)
    redis_client = redis.Redis(**REDIS_CONF)


@app.on_event("shutdown")
async def shutdown():
    pool.close()
    await pool.wait_closed()
    await redis_client.close()


# ============ Helpers ============
def md5(text: str) -> str:
    return hashlib.md5(text.encode()).hexdigest()


def make_token(user_id: str) -> str:
    payload = f"{user_id}:{datetime.utcnow().isoformat()}:{JWT_SECRET}"
    return md5(payload)


def json_response(data: Any, code: int = 0, message: str = "ok"):
    return {"code": code, "message": message, "data": data}


# ============ Health ============
@app.get("/api/health")
async def health():
    return json_response({"status": "ok", "timestamp": datetime.now().isoformat()})


# ============ Auth ============
@app.get("/api/auth/send_code")
async def send_code(phone: str = Query(...)):
    """发送验证码（固定 123456）"""
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, nickname FROM users WHERE phone = %s", (phone,)
            )
            row = await cur.fetchone()
            if not row:
                user_id = str(uuid.uuid4())
                await cur.execute(
                    "INSERT INTO users (id, phone, password_hash) VALUES (%s, %s, %s)",
                    (user_id, phone, md5("")),
                )
            if redis_client:
                await redis_client.setex(f"code:{phone}", 300, "123456")
    return json_response({"code": "123456", "message": "验证码已发送"})


@app.get("/api/auth/login")
async def login(phone: str = Query(...), code: str = Query(...)):
    """手机号 + 验证码登录"""
    if redis_client:
        real = await redis_client.get(f"code:{phone}")
        if real and real != code:
            raise HTTPException(status_code=401, detail="验证码错误")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "SELECT id, phone, nickname, avatar_url FROM users WHERE phone = %s",
                (phone,),
            )
            row = await cur.fetchone()
            if not row:
                user_id = str(uuid.uuid4())
                await cur.execute(
                    "INSERT INTO users (id, phone, password_hash) VALUES (%s, %s, %s)",
                    (user_id, phone, md5("")),
                )
                await cur.execute(
                    "SELECT id, phone, nickname, avatar_url FROM users WHERE phone = %s",
                    (phone,),
                )
                row = await cur.fetchone()
            user_id, phone_num, nickname, avatar = row
            token = make_token(user_id)
            await redis_client.setex(f"token:{token}", 86400 * 7, user_id)
    return json_response(
        {
            "token": token,
            "user": {
                "id": user_id,
                "phone": phone_num,
                "nickname": nickname or "用户" + phone_num[-4:],
                "avatarUrl": avatar or "",
            },
        }
    )


# ============ Friends ============
def friend_row(row) -> dict:
    return {
        "id": row[0],
        "phone": row[1],
        "nickname": row[2] or "未知",
        "avatarUrl": row[3] or "",
        "status": row[4],
    }


def request_row(row) -> dict:
    return {
        "friendship_id": row[0],
        "id": row[1],
        "phone": row[2],
        "nickname": row[3] or "未知",
        "avatar_url": row[4] or "",
        "status": row[5],
        "initiator_id": row[6],
    }


@app.get("/api/friends")
async def get_friends(token: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """SELECT u.id, u.phone, u.nickname, u.avatar_url, f.status
                FROM friendships f
                JOIN users u ON (u.id = f.user_id_1 OR u.id = f.user_id_2) AND u.id != %s
                WHERE (f.user_id_1 = %s OR f.user_id_2 = %s) AND f.status = 'accepted'
                ORDER BY f.created_at DESC""",
                (user_id, user_id, user_id),
            )
            rows = await cur.fetchall()
    return json_response([friend_row(r) for r in rows])


@app.get("/api/friends/requests")
async def get_requests(token: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                """SELECT f.id, u.id, u.phone, u.nickname, u.avatar_url, f.status, f.initiator_id
                FROM friendships f
                JOIN users u ON u.id = f.initiator_id
                WHERE (f.user_id_1 = %s OR f.user_id_2 = %s) AND f.status = 'pending'
                ORDER BY f.created_at DESC""",
                (user_id, user_id),
            )
            rows = await cur.fetchall()
    return json_response([request_row(r) for r in rows])


@app.get("/api/friends/add")
async def add_friend(token: str = Query(...), phone: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute("SELECT id FROM users WHERE phone = %s", (phone,))
            target = await cur.fetchone()
            if not target:
                raise HTTPException(status_code=404, detail="用户不存在")
            target_id = target[0]
            if target_id == user_id:
                raise HTTPException(status_code=400, detail="不能添加自己")
            await cur.execute(
                """SELECT id FROM friendships
                WHERE (user_id_1 = %s AND user_id_2 = %s)
                   OR (user_id_1 = %s AND user_id_2 = %s)""",
                (user_id, target_id, target_id, user_id),
            )
            if await cur.fetchone():
                raise HTTPException(status_code=400, detail="已是好友或请求已存在")
            fid = str(uuid.uuid4())
            await cur.execute(
                "INSERT INTO friendships (id, user_id_1, user_id_2, initiator_id, status) VALUES (%s,%s,%s,%s,'pending')",
                (fid, user_id, target_id, user_id),
            )
    return json_response({"friendshipId": fid})


@app.get("/api/friends/accept")
async def accept_friend(token: str = Query(...), friendship_id: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE friendships SET status='accepted' WHERE id=%s AND (user_id_1=%s OR user_id_2=%s) AND status='pending'",
                (friendship_id, user_id, user_id),
            )
    return json_response({"status": "accepted"})


@app.get("/api/friends/reject")
async def reject_friend(token: str = Query(...), friendship_id: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "UPDATE friendships SET status='rejected' WHERE id=%s AND (user_id_1=%s OR user_id_2=%s) AND status='pending'",
                (friendship_id, user_id, user_id),
            )
    return json_response({"status": "rejected"})


# ============ Geofences ============
@app.get("/api/geofences/create")
async def create_geofence(
    token: str = Query(...),
    name: str = Query(...),
    lat: float = Query(...),
    lng: float = Query(...),
    radius: float = Query(default=100),
):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    fid = str(uuid.uuid4())
    async with pool.acquire() as conn:
        async with conn.cursor() as cur:
            await cur.execute(
                "INSERT INTO geo_fences (id, user_id, name, lat, lng, radius) VALUES (%s,%s,%s,%s,%s,%s)",
                (fid, user_id, name, lat, lng, radius),
            )
    return json_response({"id": fid, "name": name, "lat": lat, "lng": lng, "radius": radius})


@app.get("/api/geofences")
async def get_geofences(token: str = Query(...)):
    user_id = await redis_client.get(f"token:{token}") if redis_client else None
    if not user_id:
        raise HTTPException(status_code=401, detail="未授权")
    async with pool.acquire() as conn:
        async with conn.cursor(aiomysql.DictCursor) as cur:
            await cur.execute(
                "SELECT id, name, lat, lng, radius FROM geo_fences WHERE user_id=%s",
                (user_id,),
            )
            rows = await cur.fetchall()
    return json_response(rows)


# ============ WebSocket ============
class ConnectionManager:
    def __init__(self):
        self.active: Dict[str, WebSocket] = {}

    async def connect(self, ws: WebSocket, user_id: str):
        await ws.accept()
        self.active[user_id] = ws

    def disconnect(self, user_id: str):
        self.active.pop(user_id, None)

    async def send_to(self, user_id: str, msg: dict):
        ws = self.active.get(user_id)
        if ws:
            try:
                await ws.send_json(msg)
            except Exception:
                self.disconnect(user_id)

    async def broadcast(self, msg: dict, exclude: Optional[str] = None):
        for uid, ws in list(self.active.items()):
            if uid == exclude:
                continue
            try:
                await ws.send_json(msg)
            except Exception:
                self.disconnect(uid)


manager = ConnectionManager()


@app.websocket("/ws")
async def websocket_endpoint(ws: WebSocket, token: Optional[str] = None):
    user_id = None

    if token:
        user_id = await redis_client.get(f"token:{token}") if redis_client else None

    await ws.accept()

    if not user_id:
        try:
            auth_data = await asyncio.wait_for(ws.receive_json(), timeout=5.0)
            if auth_data.get("type") == "auth":
                token = auth_data.get("token")
                user_id = await redis_client.get(f"token:{token}") if redis_client else None
        except asyncio.TimeoutError:
            pass

    if not user_id:
        await ws.close(code=4001, reason="鉴权失败")
        return

    await manager.connect(ws, user_id)
    try:
        while True:
            data = await ws.receive_json()
            msg_type = data.get("type", "")
            if msg_type == "message_quick":
                target_phone = data.get("to")
                content = data.get("content", "")
                async with pool.acquire() as conn:
                    async with conn.cursor() as cur:
                        await cur.execute(
                            "SELECT id FROM users WHERE phone = %s", (target_phone,)
                        )
                        target = await cur.fetchone()
                        if target:
                            t_uid = target[0]
                            await manager.send_to(
                                t_uid,
                                {
                                    "type": "message_quick",
                                    "from": user_id,
                                    "content": content,
                                    "timestamp": datetime.now().isoformat(),
                                },
                            )
                await ws.send_json(
                    {"type": "message_quick_ack", "status": "sent"}
                )
            elif msg_type == "ping":
                await ws.send_json({"type": "pong"})
    except WebSocketDisconnect:
        manager.disconnect(user_id)
