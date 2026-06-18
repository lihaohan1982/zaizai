import { Router, Response } from 'express';
import { authenticate, AuthRequest } from '../middleware/auth';
import pool from '../config/database';
import redisClient from '../config/redis';
import { decryptLocation, encryptLocation } from '../utils/crypto';
import { broadcastLocationUpdate } from '../ws/location-broadcaster';

const router = Router();

// POST /api/locations/update — 上报位置（由客户端定期调用）
router.post('/update', authenticate, async (req: AuthRequest, res: Response) => {
  const currentUserId = req.user!.userId;
  const { lat, lng, accuracy, battery, charging } = req.body;

  // 参数防御校验
  if (lat === undefined || lng === undefined) {
    return res.status(400).json({ error: { code: 'INVALID_PARAMS', message: '缺少 lat 或 lng' } });
  }

  const latitude = parseFloat(lat);
  const longitude = parseFloat(lng);
  if (isNaN(latitude) || isNaN(longitude)) {
    return res.status(400).json({ error: { code: 'INVALID_PARAMS', message: '坐标格式错误' } });
  }

  try {
    // 【对齐设计文档 v1.1】服务端加密坐标后存入 Redis
    const { lat: encLat, lng: encLng } = encryptLocation(latitude, longitude);

    const redisKey = `loc:${currentUserId}`;
    const tsKey = `loc:latest_ts:${currentUserId}`;
    const incomingTs = parseInt(req.body.timestamp, 10) || Date.now();

    // 【广播合并】从 Redis 读取最新已记录时间戳
    const latestTsStr = await redisClient.get(tsKey);
    const latestTs = latestTsStr ? parseInt(latestTsStr, 10) : 0;

    // 写 Redis（无论 timestamp 是否更新，均需写入保证数据最新）
    const locationData = JSON.stringify({
      lat: encLat,
      lng: encLng,
      accuracy: accuracy ?? 0,
      battery: battery ?? -1,
      charging: charging ? '1' : '0',
      timestamp: incomingTs,
    });
    await redisClient.setEx(redisKey, 600, locationData); // TTL 10 分钟

    // 仅当时间戳比已推送更新时才触发广播
    if (incomingTs > latestTs) {
      await redisClient.setEx(tsKey, 5, incomingTs.toString());
      await broadcastLocationUpdate(currentUserId);
    }

    res.json({ ok: true, timestamp: incomingTs });
  } catch (err) {
    console.error('Location update error:', err);
    res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '位置更新失败' } });
  }
});

// GET /api/locations/batch?ids=uuid1,uuid2,uuid3
router.get('/batch', authenticate, async (req: AuthRequest, res: Response) => {
  const idsParam = req.query.ids as string;
  const currentUserId = req.user!.userId;

  if (!idsParam) {
    return res.status(400).json({ error: { code: 'INVALID_PARAMS', message: '缺少好友ID列表' } });
  }

  const friendIds = idsParam.split(',').filter(id => id.trim() !== '');
  if (friendIds.length === 0) {
    return res.json({ locations: [] });
  }

  if (friendIds.length > 100) {
    return res.status(400).json({ error: { code: 'TOO_MANY_IDS', message: '单次最多拉取100个好友位置' } });
  }

  try {
    // 【安全防线】MySQL 批量校验好友关系
    const placeholders = friendIds.map(() => '?').join(',');
    const [friendships] = await pool.query(
      `SELECT user_id_1, user_id_2 FROM friendships
       WHERE status = 'accepted'
       AND (
         (user_id_1 = ? AND user_id_2 IN (${placeholders}))
         OR
         (user_id_2 = ? AND user_id_1 IN (${placeholders}))
       )`,
      [currentUserId, ...friendIds, currentUserId, ...friendIds]
    );

    const validFriendIds = new Set<string>();
    (friendships as any[]).forEach((row: any) => {
      if (row.user_id_1 !== currentUserId) validFriendIds.add(row.user_id_1);
      if (row.user_id_2 !== currentUserId) validFriendIds.add(row.user_id_2);
    });

    if (validFriendIds.size === 0) {
      return res.json({ locations: [] });
    }

    // 【性能核心】Redis MGET 批量获取
    const redisKeys = Array.from(validFriendIds).map(id => `loc:${id}`);
    const rawLocations = await redisClient.mGet(redisKeys);

    const locations = [];
    let index = 0;
    for (const friendId of validFriendIds) {
      const rawData = rawLocations[index++];
      if (rawData) {
        try {
          const parsed = JSON.parse(rawData);
          const decrypted = decryptLocation(parsed.lat, parsed.lng);
          locations.push({
            userId: friendId,
            lat: decrypted.lat,
            lng: decrypted.lng,
            accuracy: parseFloat(parsed.accuracy) || 0,
            battery: parseInt(parsed.battery, 10),
            charging: parsed.charging === '1',
            timestamp: parseInt(parsed.timestamp, 10),
          });
        } catch (e) {
          console.error(`Decrypt location failed for user ${friendId}:`, e);
        }
      }
    }

    res.json({ locations });
  } catch (err) {
    console.error('Batch location fetch error:', err);
    res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '批量获取位置失败' } });
  }
});

export default router;
