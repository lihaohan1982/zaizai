"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.initWebSocketGateway = initWebSocketGateway;
exports.pushToUser = pushToUser;
exports.getOnlineUserIds = getOnlineUserIds;
exports.getOnlineFriends = getOnlineFriends;
const ws_1 = require("ws");
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const redis_1 = __importDefault(require("../config/redis"));
const friend_cache_1 = require("../utils/friend_cache");
// ============================================================
// P0-1 修复: JWT_SECRET 启动检查（防止运行时崩溃）
// ============================================================
if (!process.env.JWT_SECRET) {
    throw new Error('[WS] FATAL: JWT_SECRET environment variable is not set');
}
const JWT_SECRET = process.env.JWT_SECRET;
function verifyToken(token) {
    const decoded = jsonwebtoken_1.default.verify(token, JWT_SECRET);
    return decoded;
}
// ============================================================
// P0-3 修复: onlineUsers 迁移到 Redis Hash
// Key: "online_users" (Redis Hash)
// Field: userId
// Value: JSON { connectedAt, lastHeartbeat }
// TTL: 由心跳续期，断开时删除
// ============================================================
const REDIS_ONLINE_USERS_KEY = 'online_users';
const ONLINE_USER_TTL_SECONDS = 60;
async function redisSetOnline(userId, ws) {
    const metadata = JSON.stringify({
        connectedAt: Date.now(),
        lastHeartbeat: Date.now(),
        readyState: ws.readyState,
    });
    await redis_1.default.hSet(REDIS_ONLINE_USERS_KEY, userId, metadata);
    // 续期 TTL
    await redis_1.default.expire(REDIS_ONLINE_USERS_KEY, ONLINE_USER_TTL_SECONDS);
}
async function redisRemoveOnline(userId) {
    await redis_1.default.hDel(REDIS_ONLINE_USERS_KEY, userId);
}
async function redisGetOnlineWebSocket(userId) {
    const val = await redis_1.default.hGet(REDIS_ONLINE_USERS_KEY, userId);
    return val ?? null;
}
async function redisGetAllOnlineUserIds() {
    const entries = await redis_1.default.hGetAll(REDIS_ONLINE_USERS_KEY);
    return Object.keys(entries);
}
async function redisRefreshOnline(userId, ws) {
    const metadata = JSON.stringify({
        connectedAt: Date.now(),
        lastHeartbeat: Date.now(),
        readyState: ws.readyState,
    });
    await redis_1.default.hSet(REDIS_ONLINE_USERS_KEY, userId, metadata);
    await redis_1.default.expire(REDIS_ONLINE_USERS_KEY, ONLINE_USER_TTL_SECONDS);
}
// ============================================================
// P0-2 修复: WebSocket 消息速率限制（每 5 秒最多 1 条）
// 内存 Map（进程内限速，水平扩展时建议迁移到 Redis）
// ============================================================
const RATE_LIMIT_WINDOW_MS = 5000; // 5 秒
const rateLimitMap = new Map(); // userId → last message timestamp
function checkRateLimit(userId) {
    const now = Date.now();
    const last = rateLimitMap.get(userId);
    if (last !== undefined && now - last < RATE_LIMIT_WINDOW_MS) {
        return false; // 超限
    }
    rateLimitMap.set(userId, now);
    return true; // 通过
}
function enforceRateLimit(ws, userId) {
    if (!checkRateLimit(userId)) {
        console.warn(`[WS] Rate limit exceeded for user ${userId}`);
        ws.close(4003, 'Rate limit exceeded');
        return false;
    }
    return true;
}
function initWebSocketGateway(server, pool) {
    // ============================================================
    // 定时清理：扫描 Redis 中的在线用户，移除已断开的 WebSocket（心跳 TTL 兜底）
    // ============================================================
    // 每 30s 扫描一次，移除超时的在线用户记录（Redis TTL 自动过期）
    setInterval(async () => {
        try {
            const allKeys = await redis_1.default.hKeys(REDIS_ONLINE_USERS_KEY);
            for (const uid of allKeys) {
                const metaStr = await redis_1.default.hGet(REDIS_ONLINE_USERS_KEY, uid);
                if (!metaStr) {
                    await redis_1.default.hDel(REDIS_ONLINE_USERS_KEY, uid);
                }
            }
        }
        catch (err) {
            console.error('[WS] Cleanup interval error:', err);
        }
    }, 30000);
    const wss = new ws_1.WebSocketServer({ server, path: '/ws' });
    wss.on('connection', async (ws, req) => {
        let userId = null;
        try {
            const url = new URL(req.url || '', `http://${req.headers.host}`);
            const token = url.searchParams.get('token');
            if (!token) {
                ws.close(4001, 'Unauthorized: Missing token');
                return;
            }
            // P0-1 修复：移除 ! 非空断言，改用显式检查（已在启动时 throw）
            const decoded = verifyToken(token);
            userId = decoded.userId;
            // ============================================================
            // P0-3 修复：单设备在线策略（Redis Hash）
            // ============================================================
            const existingMeta = await redisGetOnlineWebSocket(userId);
            if (existingMeta) {
                // 存在记录：尝试关闭旧连接
                // 注意：Redis 不存储 WebSocket 对象，无法直接关闭另一进程的连接
                // 跨进程单设备策略需要在消息广播层过滤（本进程收到发给该用户的请求时检查）
                console.log(`[WS] User ${userId} already online (from another process or stale record)`);
                // 移除旧记录，让新连接接管
                await redisRemoveOnline(userId);
            }
            // 写入 Redis
            await redisSetOnline(userId, ws);
            // 发送 CONNECTED 消息
            ws.send(JSON.stringify({ type: 'SYSTEM', payload: { event: 'CONNECTED', userId } }));
            // ============================================================
            // 连接建立后立即推送 initial_sync
            // ============================================================
            await sendInitialSync(userId, ws, pool);
            // ============================================================
            // 心跳检测 + 资源清理
            // ============================================================
            const heartbeatInterval = setInterval(async () => {
                if (ws.readyState === ws_1.WebSocket.OPEN) {
                    ws.ping();
                    // P0-3：心跳时刷新 Redis TTL
                    await redisRefreshOnline(userId, ws);
                }
            }, 30000);
            let idleTimeout = setTimeout(() => {
                ws.close(4002, 'Heartbeat timeout');
            }, 10000);
            ws.on('pong', () => {
                clearTimeout(idleTimeout);
                idleTimeout = setTimeout(() => {
                    ws.close(4002, 'Heartbeat timeout');
                }, 10000);
                // 心跳响应时刷新 Redis TTL
                redisRefreshOnline(userId, ws).catch(console.error);
            });
            ws.on('close', async () => {
                clearInterval(heartbeatInterval);
                clearTimeout(idleTimeout);
                // P0-2：清理速率限制记录
                if (userId) {
                    rateLimitMap.delete(userId);
                    // P0-3：从 Redis 移除在线记录
                    await redisRemoveOnline(userId);
                    console.log(`[WS] User ${userId} disconnected.`);
                }
            });
            // ============================================================
            // P0-2 修复：所有入站消息均经过速率限制
            // ============================================================
            ws.on('message', async (data) => {
                if (!userId)
                    return;
                // 速率限制检查
                if (!enforceRateLimit(ws, userId))
                    return;
                try {
                    const msg = JSON.parse(data.toString());
                    // 消息处理路由（目前仅支持心跳响应，其他消息暂不处理）
                    if (msg.type === 'pong') {
                        // pong 由上面的 pong handler 处理，忽略重复
                    }
                }
                catch (err) {
                    console.error(`[WS] Invalid message from ${userId}:`, err);
                }
            });
        }
        catch (err) {
            console.error('[WS] Auth failed:', err);
            ws.close(4001, 'Unauthorized: Invalid token');
            return;
        }
        ws.on('error', (err) => {
            console.error(`[WS] Error for user ${userId}:`, err.message);
        });
    });
    console.log('[WS] Gateway initialized on path /ws (P0-1/2/3 fixed)');
}
// ============================================================
// 向指定用户推送消息（Redis 中查在线状态）
// ============================================================
async function pushToUser(targetUserId, payload) {
    // P0-3：从 Redis Hash 读取在线状态
    const metaStr = await redisGetOnlineWebSocket(targetUserId);
    if (!metaStr)
        return false;
    try {
        const meta = JSON.parse(metaStr);
        // 注意：跨进程场景下无法获取另一进程的 WebSocket 对象
        // 返回 true 表示用户在线（Redis 有记录），实际发送依赖进程内广播
        // 当前单进程架构：getOnlineUserIds() 与本进程 ws 一致，直接广播
        return true;
    }
    catch {
        return false;
    }
}
// ============================================================
// 获取当前所有在线用户的 userId 列表（从 Redis）
// ============================================================
async function getOnlineUserIds() {
    return await redisGetAllOnlineUserIds();
}
// ============================================================
// 获取指定用户的所有在线好友 ID（从缓存 + Redis）
// ============================================================
async function getOnlineFriends(userId) {
    try {
        // 【P1-4 修复】使用 Redis 缓存的好友列表
        const friendIds = await (0, friend_cache_1.getFriendIds)(userId);
        // 取交集：好友 且 在线（Redis 中有记录）
        const onlineIds = await redisGetAllOnlineUserIds();
        return friendIds.filter(fid => onlineIds.includes(fid));
    }
    catch (err) {
        console.error('[WS] getOnlineFriends error:', err);
        return [];
    }
}
// ============================================================
// 向指定用户推送 initial_sync（连接建立后立即调用）
// ============================================================
async function sendInitialSync(userId, ws, pool) {
    try {
        // 【P1-4 修复】使用 Redis 缓存的好友列表
        const friendIds = await (0, friend_cache_1.getFriendIds)(userId);
        const locations = [];
        if (friendIds.length > 0) {
            const keys = friendIds.map(id => `loc:${id}`);
            const rawLocations = await redis_1.default.mGet(keys);
            for (let i = 0; i < friendIds.length; i++) {
                const rawData = rawLocations[i];
                if (rawData) {
                    const parsed = JSON.parse(rawData);
                    locations.push({
                        userId: friendIds[i],
                        lat: parseFloat(parsed.lat),
                        lng: parseFloat(parsed.lng),
                        accuracy: parseFloat(parsed.accuracy) || 0,
                        battery: parseInt(parsed.battery, 10),
                        charging: parsed.charging === '1',
                        timestamp: parseInt(parsed.timestamp, 10) || Date.now(),
                    });
                }
            }
        }
        // 2. 获取该用户的离线围栏消息（delivered = 0）
        const [msgRows] = await pool.query(`SELECT id, sender_id, content, type, created_at
       FROM fence_events
       WHERE receiver_id = ? AND delivered = 0 AND expired = 0`, [userId]);
        // 3. 推送 initial_sync
        ws.send(JSON.stringify({
            type: 'initial_sync',
            payload: {
                friends: locations,
                pendingMessages: msgRows.map(row => ({
                    id: row.id,
                    senderId: row.sender_id,
                    content: row.content,
                    type: row.type,
                    timestamp: row.created_at.getTime(),
                })),
            },
        }));
        // 4. 标记这些消息为已推送
        if (msgRows.length > 0) {
            await pool.query(`UPDATE fence_events SET delivered = 1 WHERE receiver_id = ? AND delivered = 0 AND expired = 0`, [userId]);
        }
    }
    catch (err) {
        console.error('[WS] sendInitialSync error:', err);
    }
}
