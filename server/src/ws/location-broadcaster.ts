import { pushToUser } from './ws-gateway';
import pool from '../config/database';
import redisClient from '../config/redis';
import { v4 as uuidv4 } from 'uuid';
import { RowDataPacket } from 'mysql2';
import { getFriendIds } from '../utils/friend_cache';

/**
 * 位置变更广播（由任务 4.1 的 update 接口调用）
 * 含广播合并：基于时间戳去重，5 秒 TTL 内仅推送时间戳最大的消息
 */
export async function broadcastLocationUpdate(userId: string): Promise<void> {
  try {
    // 从 Redis 读取位置数据
    const redisKey = `loc:${userId}`;
    const rawData = await redisClient.get(redisKey);
    if (!rawData) return;

    const parsed = JSON.parse(rawData);
    const currentTs = parseInt(parsed.timestamp, 10) || Date.now();

    // 【去重已由 locations.ts 入口层保证，此处仅负责向已确认好友广播】
    // friendIds 过滤掉离线的用户（broadcastToFriends 内部已按 onlineUsers 过滤）

    // 使用 Redis 缓存的好友列表
    const friendIds = await getFriendIds(userId);

    const payload = {
      type: 'LOCATION_UPDATE',
      payload: {
        userId,
        lat: parseFloat(parsed.lat),
        lng: parseFloat(parsed.lng),
        accuracy: parseFloat(parsed.accuracy) || 0,
        battery: parseInt(parsed.battery, 10),
        charging: parsed.charging === '1',
        timestamp: currentTs,
      },
    };

    for (const friendId of friendIds) {
      pushToUser(friendId, payload);
    }
  } catch (err) {
    // Redis 异常时不阻塞正常业务，兜底直接推送
    console.error('[Broadcast] 广播合并异常:', err);
    await broadcastToFriendsFallback(userId);
  }
}

/**
 * Redis 异常时的兜底推送（不经过时间戳合并）
 */
async function broadcastToFriendsFallback(userId: string): Promise<void> {
  try {
    const redisKey = `loc:${userId}`;
    const rawData = await redisClient.get(redisKey);
    if (!rawData) return;

    const parsed = JSON.parse(rawData);
    const friendIds = await getFriendIds(userId);

    const payload = {
      type: 'LOCATION_UPDATE',
      payload: {
        userId,
        lat: parseFloat(parsed.lat),
        lng: parseFloat(parsed.lng),
        accuracy: parseFloat(parsed.accuracy) || 0,
        battery: parseInt(parsed.battery, 10),
        charging: parsed.charging === '1',
        timestamp: parseInt(parsed.timestamp, 10) || Date.now(),
      },
    };

    for (const friendId of friendIds) {
      pushToUser(friendId, payload);
    }
  } catch (err) {
    console.error('[Broadcast] 兜底推送也失败:', err);
  }
}

/**
 * 围栏进出事件触发器
 */
export async function triggerFenceEvent(
  userId: string,
  eventType: 'GEOFENCE_ENTER' | 'GEOFENCE_LEAVE',
  fenceName: string
) {
  const warmMessage = eventType === 'GEOFENCE_ENTER'
    ? `我刚刚安全到达【${fenceName}】啦！`
    : `我刚刚离开【${fenceName}】了哦！`;

  try {
    // 【P1-4 修复】使用 Redis 缓存的好友列表
    const friendIds = await getFriendIds(userId);

    for (const friendId of friendIds) {
      // 【修正三】对齐 QuickMessageService 契约
      const messagePayload = {
        type: 'message:quick',
        payload: {
          id: uuidv4(),
          type: 'system',
          senderId: userId,
          receiverId: friendId,
          fenceId: fenceName,
          contentKey: eventType === 'GEOFENCE_ENTER' ? 'fence_enter' : 'fence_leave',
          customText: warmMessage,
          timestamp: Date.now()
        }
      };

      const isOnline = pushToUser(friendId, messagePayload);

      // 【修正四】离线兜底写入 fence_events 表
      if (!isOnline) {
        await pool.query(
          'INSERT INTO fence_events (id, receiver_id, sender_id, content, type, delivered, expired, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())',
          [uuidv4(), friendId, userId, warmMessage, 'fence_auto', 0, 0]
        );
      }
    }
  } catch (err) {
    console.error('Trigger fence event error:', err);
  }
}

/**
 * 隐私模式变更广播（暂停/恢复时调用）
 */
export async function broadcastPrivacyChange(
  userId: string,
  status: 'paused' | 'resumed'
): Promise<void> {
  try {
    // 【P1-4 修复】使用 Redis 缓存的好友列表
    const friendIds = await getFriendIds(userId);

    const payload = {
      type: 'friend_privacy_change',
      payload: {
        userId,
        status,
        message: status === 'paused' ? '对方暂时关闭了位置共享' : '对方恢复了位置共享',
      },
    };

    for (const friendId of friendIds) {
      pushToUser(friendId, payload);
    }
  } catch (err) {
    console.error('Broadcast privacy change error:', err);
  }
}
