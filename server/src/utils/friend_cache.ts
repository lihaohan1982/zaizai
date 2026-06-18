import pool from '../config/database';
import redisClient from '../config/redis';
import { RowDataPacket } from 'mysql2';

// ============================================================
// P1-4 修复: 好友列表 Redis 缓存（TTL 5 分钟）
// 解决 N+1 查询问题：避免每次广播/同步都查 MySQL
// ============================================================
const FRIEND_CACHE_TTL_SECONDS = 300; // 5 分钟

function getFriendCacheKey(userId: string): string {
  return `friends:${userId}`;
}

/**
 * 获取用户的好友 ID 列表（优先读 Redis 缓存，未命中则查 MySQL 并写入缓存）
 */
export async function getFriendIds(userId: string): Promise<string[]> {
  const cacheKey = getFriendCacheKey(userId);

  try {
    // 1. 尝试从 Redis 缓存读取
    const cached = await redisClient.get(cacheKey);
    if (cached) {
      return JSON.parse(cached) as string[];
    }

    // 2. 缓存未命中，查 MySQL
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT CASE WHEN user_id_1 = ? THEN user_id_2 ELSE user_id_1 END AS friend_id
       FROM friendships
       WHERE (user_id_1 = ? OR user_id_2 = ?)
         AND status = 'accepted'`,
      [userId, userId, userId]
    );

    const friendIds = (rows as { friend_id: string }[]).map(r => r.friend_id);

    // 3. 写入 Redis 缓存
    if (friendIds.length > 0) {
      await redisClient.setEx(cacheKey, FRIEND_CACHE_TTL_SECONDS, JSON.stringify(friendIds));
    } else {
      // 无好友也缓存（避免频繁查 MySQL）
      await redisClient.setEx(cacheKey, FRIEND_CACHE_TTL_SECONDS, JSON.stringify([]));
    }

    return friendIds;
  } catch (err) {
    console.error('[FriendCache] getFriendIds error:', err);
    // 缓存异常时回退到 MySQL 直接查询
    const [rows] = await pool.query<RowDataPacket[]>(
      `SELECT CASE WHEN user_id_1 = ? THEN user_id_2 ELSE user_id_1 END AS friend_id
       FROM friendships
       WHERE (user_id_1 = ? OR user_id_2 = ?)
         AND status = 'accepted'`,
      [userId, userId, userId]
    );
    return (rows as { friend_id: string }[]).map(r => r.friend_id);
  }
}

/**
 * 使指定用户的好友列表缓存失效（好友关系变更时调用）
 */
export async function invalidateFriendCache(userId: string): Promise<void> {
  try {
    await redisClient.del(getFriendCacheKey(userId));
  } catch (err) {
    console.error('[FriendCache] invalidate error:', err);
  }
}
