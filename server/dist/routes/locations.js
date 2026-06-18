"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const database_1 = __importDefault(require("../config/database"));
const redis_1 = __importDefault(require("../config/redis"));
const crypto_1 = require("../utils/crypto");
const location_broadcaster_1 = require("../ws/location-broadcaster");
const router = (0, express_1.Router)();
// POST /api/locations/update — 上报位置（由客户端定期调用）
router.post('/update', auth_1.authenticate, async (req, res) => {
    const currentUserId = req.user.userId;
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
        const { lat: encLat, lng: encLng } = (0, crypto_1.encryptLocation)(latitude, longitude);
        const redisKey = `loc:${currentUserId}`;
        const locationData = JSON.stringify({
            lat: encLat,
            lng: encLng,
            accuracy: accuracy ?? 0,
            battery: battery ?? -1,
            charging: charging ? '1' : '0',
            timestamp: Date.now()
        });
        await redis_1.default.setEx(redisKey, 600, locationData); // TTL 10 分钟，超时自动过期
        // 【核心】触发 WebSocket 广播给所有在线好友
        await (0, location_broadcaster_1.broadcastLocationUpdate)(currentUserId);
        res.json({ ok: true, timestamp: Date.now() });
    }
    catch (err) {
        console.error('Location update error:', err);
        res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '位置更新失败' } });
    }
});
// GET /api/locations/batch?ids=uuid1,uuid2,uuid3
router.get('/batch', auth_1.authenticate, async (req, res) => {
    const idsParam = req.query.ids;
    const currentUserId = req.user.userId;
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
        const [friendships] = await database_1.default.query(`SELECT user_id_1, user_id_2 FROM friendships
       WHERE status = 'accepted'
       AND (
         (user_id_1 = ? AND user_id_2 IN (${placeholders}))
         OR
         (user_id_2 = ? AND user_id_1 IN (${placeholders}))
       )`, [currentUserId, ...friendIds, currentUserId, ...friendIds]);
        const validFriendIds = new Set();
        friendships.forEach((row) => {
            if (row.user_id_1 !== currentUserId)
                validFriendIds.add(row.user_id_1);
            if (row.user_id_2 !== currentUserId)
                validFriendIds.add(row.user_id_2);
        });
        if (validFriendIds.size === 0) {
            return res.json({ locations: [] });
        }
        // 【性能核心】Redis MGET 批量获取
        const redisKeys = Array.from(validFriendIds).map(id => `loc:${id}`);
        const rawLocations = await redis_1.default.mGet(redisKeys);
        const locations = [];
        let index = 0;
        for (const friendId of validFriendIds) {
            const rawData = rawLocations[index++];
            if (rawData) {
                try {
                    const parsed = JSON.parse(rawData);
                    const decrypted = (0, crypto_1.decryptLocation)(parsed.lat, parsed.lng);
                    locations.push({
                        userId: friendId,
                        lat: decrypted.lat,
                        lng: decrypted.lng,
                        accuracy: parseFloat(parsed.accuracy) || 0,
                        battery: parseInt(parsed.battery, 10),
                        charging: parsed.charging === '1',
                        timestamp: parseInt(parsed.timestamp, 10),
                    });
                }
                catch (e) {
                    console.error(`Decrypt location failed for user ${friendId}:`, e);
                }
            }
        }
        res.json({ locations });
    }
    catch (err) {
        console.error('Batch location fetch error:', err);
        res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '批量获取位置失败' } });
    }
});
exports.default = router;
