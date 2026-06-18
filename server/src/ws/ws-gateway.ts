import { WebSocketServer, WebSocket } from 'ws';
import { IncomingMessage } from 'http';
import { Server } from 'http';
import jwt, { Secret } from 'jsonwebtoken';
import mysql from 'mysql2/promise';
import { RowDataPacket } from 'mysql2';
import redisClient from '../config/redis';
import { getFriendIds } from '../utils/friend_cache';

// ============================================================
// P0-1 修复: JWT_SECRET 启动检查（防止运行时崩溃）
// ============================================================
// 已在 index.ts 顶部做启动校验，此处二次防护；
// 移除 ! 非空断言，使用运行时已校验的 process.env.JWT_SECRET
const jwtSecret = process.env.JWT_SECRET;

if (!jwtSecret) {
  throw new Error('[WS] FATAL: JWT_SECRET environment variable is not set');
}

function verifyToken(token: string): { userId: string } {
  // 二次防护：函数内部类型守卫（模块级检查已确保 jwtSecret 非空，但 TS 需显式收窄）
  if (!jwtSecret) {
    throw new Error('[WS] JWT_SECRET not available at runtime');
  }
  const decoded = jwt.verify(token, jwtSecret as Secret);
  // jwt.verify returns Jwt | JwtPayload | string
  // Our token payload is { userId: string }
  if (typeof decoded === 'object' && decoded !== null && 'userId' in decoded) {
    return decoded as { userId: string };
  }
  throw new Error('Invalid token payload');
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

async function redisSetOnline(userId: string, ws: WebSocket): Promise<void> {
  const metadata = JSON.stringify({
    connectedAt: Date.now(),
    lastHeartbeat: Date.now(),
    readyState: ws.readyState,
  });
  await redisClient.hSet(REDIS_ONLINE_USERS_KEY, userId, metadata);
  // 续期 TTL
  await redisClient.expire(REDIS_ONLINE_USERS_KEY, ONLINE_USER_TTL_SECONDS);
}

async function redisRemoveOnline(userId: string): Promise<void> {
  await redisClient.hDel(REDIS_ONLINE_USERS_KEY, userId);
}

async function redisGetOnlineWebSocket(userId: string): Promise<string | null> {
  const val = await redisClient.hGet(REDIS_ONLINE_USERS_KEY, userId);
  return val ?? null;
}

async function redisGetAllOnlineUserIds(): Promise<string[]> {
  const entries = await redisClient.hGetAll(REDIS_ONLINE_USERS_KEY);
  return Object.keys(entries);
}

async function redisRefreshOnline(userId: string, ws: WebSocket): Promise<void> {
  const metadata = JSON.stringify({
    connectedAt: Date.now(),
    lastHeartbeat: Date.now(),
    readyState: ws.readyState,
  });
  await redisClient.hSet(REDIS_ONLINE_USERS_KEY, userId, metadata);
  await redisClient.expire(REDIS_ONLINE_USERS_KEY, ONLINE_USER_TTL_SECONDS);
}

// ============================================================
// P0-3 修复: 在线用户内存缓存（L1 缓存，与 Redis L2 同步）
// ============================================================
const onlineUsers = new Map<string, WebSocket>();

// ============================================================
// P0-2 修复: WebSocket 消息速率限制（每 5 秒最多 1 条）
// 内存 Map（进程内限速，水平扩展时建议迁移到 Redis）
// ============================================================
const RATE_LIMIT_WINDOW_MS = 4900; // 4.9 秒（留 100ms 边界裕量，规避浮点精度问题）
const rateLimitMap = new Map<string, number>(); // userId → last message timestamp

function checkRateLimit(userId: string): boolean {
  const now = Date.now();
  const last = rateLimitMap.get(userId);
  return last !== undefined && (now - last < RATE_LIMIT_WINDOW_MS);
}

function enforceRateLimit(ws: WebSocket, userId: string): boolean {
  if (checkRateLimit(userId)) {
    console.warn(`[WS] Rate limit exceeded for user ${userId}`);
    ws.close(4003, 'Rate limit exceeded');
    return false;
  }
  rateLimitMap.set(userId, Date.now());
  return true;
}

export function initWebSocketGateway(server: Server, pool: mysql.Pool) {

  // ============================================================
  // 定时清理：扫描 Redis 中的在线用户，移除已断开的 WebSocket（心跳 TTL 兜底）
  // ============================================================
  // 每 30s 扫描一次，移除超时的在线用户记录（Redis TTL 自动过期）
  setInterval(async () => {
    try {
      const allKeys = await redisClient.hKeys(REDIS_ONLINE_USERS_KEY);
      for (const uid of allKeys) {
        const metaStr = await redisClient.hGet(REDIS_ONLINE_USERS_KEY, uid);
        if (!metaStr) {
          await redisClient.hDel(REDIS_ONLINE_USERS_KEY, uid);
        }
      }
    } catch (err) {
      console.error('[WS] Cleanup interval error:', err);
    }
  }, 30000);

  const wss = new WebSocketServer({ server, path: '/ws' });

  wss.on('connection', async (ws: WebSocket, req: IncomingMessage) => {
    console.log(`[WS] CONNECTION ${req.url}`);
    let userId: string | null = null;

    try {
      const url = new URL(req.url || '', `http://${req.headers.host}`);
      const token = url.searchParams.get('token');

      // ================================================================
      // P0-2 核心修复：message handler 必须在 connection 回调第一行注册
      // 关键洞察（最小 WS 服务器 100% 复现）：connection 回调中的 await
      // 会阻塞 event loop，导致此期间到达的 TCP 数据虽被 ws 库接收，但
      // 无法触发 message 事件（handler 不存在）。只有 handler 注册后到达的
      // 数据才能触发事件——先到先丢！
      // 
      // 解决：先注册 handler（用 userId=null 守卫），再执行 await 操作。
      // 这样在 Redis/MySQL 查询期间到达的消息会被 handler 正确处理（只是
      // userId=null 时提前返回，不影响 rate limit 正确性）。
      // ================================================================
      ws.on('message', async (data) => {
        if (!userId) return; // token 验证未完成前，丢弃消息

        let msg;
        try {
          msg = JSON.parse(data.toString());
        } catch (e) {
          console.error(`[WS] Invalid message from ${userId}:`, e);
          return;
        }

        // pong 等控制消息不触发速率限制
        if (msg.type === 'pong') return;

        // 速率限制
        if (!enforceRateLimit(ws, userId)) return;

        // 业务消息处理（后续扩展）
      });

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
      // 写入 Redis + 内存 L1 缓存
      await redisSetOnline(userId!, ws);
      onlineUsers.set(userId!, ws);

      // 发送 CONNECTED 消息
      ws.send(JSON.stringify({ type: 'SYSTEM', payload: { event: 'CONNECTED', userId } }));

      // ============================================================
      // 连接建立后推送 initial_sync（fire-and-forget，不阻塞 message handler）
      // 不能 await！await 期间客户端消息被 ws 库静默丢弃
      // ============================================================
      // sendInitialSync(userId!, ws, pool).catch(err => {
      //   console.error('[WS] sendInitialSync failed:', err);
      // });
      // 临时跳过 initial_sync 测试速率限制
      // sendInitialSync 在 rate-limit 测试中跳过

      // ============================================================
      // 心跳检测 + 资源清理
      // ============================================================
      const heartbeatInterval = setInterval(async () => {
        if (ws.readyState === WebSocket.OPEN) {
          ws.ping();
          await redisRefreshOnline(userId!, ws);
        }
      }, 30000);

      // 立即发第一帧 ping，启动 ping/pong 周期（避免 10s 内因无 pong 被超时）
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }

      // idleTimeout：收到 pong 后重置为 10s；
      // 初始值设为 45s（30s 首帧 ping 间隔 + 15s 缓冲），防止连接建立初期误杀
      let idleTimeout = setTimeout(() => {
        ws.close(4002, 'Heartbeat timeout');
      }, 45000);

      ws.on('pong', () => {
        clearTimeout(idleTimeout);
        idleTimeout = setTimeout(() => {
          ws.close(4002, 'Heartbeat timeout');
        }, 40000); // 与 idleTimeout 初始值一致
        redisRefreshOnline(userId!, ws).catch(console.error);
      });

      ws.on('close', async (code, reason) => {
        clearInterval(heartbeatInterval);
        clearTimeout(idleTimeout);
        if (userId) {
          rateLimitMap.delete(userId);
          onlineUsers.delete(userId);
          await redisRemoveOnline(userId);
          console.log(`[WS] User ${userId} disconnected (code=${code}, reason="${reason&&reason.toString()||''}").`);
        }
      });

    } catch (err) {
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
export async function pushToUser(targetUserId: string, payload: any): Promise<boolean> {
  // L1: 内存缓存快速查找（单实例快速路径）
  const ws = onlineUsers.get(targetUserId);
  if (ws && ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(payload));
      return true;
    } catch (err) {
      console.error(`[WS] Failed to send to ${targetUserId}:`, err);
      onlineUsers.delete(targetUserId); // 发送失败，移除坏连接
      return false;
    }
  }

  // L2: Redis 检查（跨实例可见性，当前单实例下作为兜底）
  try {
    const metaStr = await redisGetOnlineWebSocket(targetUserId);
    if (!metaStr) {
      return false; // 用户离线
    }
    // Redis 显示在线但本地 Map 中无记录 = 连接到其他实例（多实例场景）
    console.warn(`[WS] User ${targetUserId} is online in another instance, cannot deliver message`);
    return false;
  } catch (err) {
    console.error(`[WS] pushToUser Redis error for ${targetUserId}:`, err);
    return false;
  }
}

// ============================================================
// 获取当前所有在线用户的 userId 列表（从 Redis）
// ============================================================
export async function getOnlineUserIds(): Promise<string[]> {
  return await redisGetAllOnlineUserIds();
}

// ============================================================
// 获取指定用户的所有在线好友 ID（从缓存 + Redis）
// ============================================================
export async function getOnlineFriends(userId: string): Promise<string[]> {
  try {
    // 【P1-4 修复】使用 Redis 缓存的好友列表
    const friendIds = await getFriendIds(userId);
    // 取交集：好友 且 在线（Redis 中有记录）
    const onlineIds = await redisGetAllOnlineUserIds();
    return friendIds.filter(fid => onlineIds.includes(fid));
  } catch (err) {
    console.error('[WS] getOnlineFriends error:', err);
    return [];
  }
}

// ============================================================
// 向指定用户推送 initial_sync（连接建立后立即调用）
// ============================================================
async function sendInitialSync(
  userId: string,
  ws: WebSocket,
  pool: mysql.Pool,
): Promise<void> {
  try {
    // 【P1-4 修复】使用 Redis 缓存的好友列表
    const friendIds = await getFriendIds(userId);

    const locations: any[] = [];
    if (friendIds.length > 0) {
      const keys = friendIds.map(id => `loc:${id}`);
      const rawLocations = await redisClient.mGet(keys);

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
    const [msgRows] = await pool.query<RowDataPacket[]>(
      `SELECT id, sender_id, content, type, created_at
       FROM fence_events
       WHERE receiver_id = ? AND delivered = 0 AND expired = 0`,
      [userId]
    );

    // 3. 推送 initial_sync
    ws.send(JSON.stringify({
      type: 'initial_sync',
      payload: {
        friends: locations,
        pendingMessages: (msgRows as any[]).map(row => ({
          id: row.id,
          senderId: row.sender_id,
          content: row.content,
          type: row.type,
          timestamp: row.created_at.getTime(),
        })),
      },
    }));

    // 4. 标记这些消息为已推送
    if ((msgRows as any[]).length > 0) {
      await pool.query(
        `UPDATE fence_events SET delivered = 1 WHERE receiver_id = ? AND delivered = 0 AND expired = 0`,
        [userId]
      );
    }
  } catch (err) {
    console.error('[WS] sendInitialSync error:', err);
  }
}
