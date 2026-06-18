"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.broadcastLocationUpdate = broadcastLocationUpdate;
exports.triggerFenceEvent = triggerFenceEvent;
exports.broadcastPrivacyChange = broadcastPrivacyChange;
const ws_gateway_1 = require("./ws-gateway");
const database_1 = __importDefault(require("../config/database"));
const redis_1 = __importDefault(require("../config/redis"));
const uuid_1 = require("uuid");
const friend_cache_1 = require("../utils/friend_cache");
/**
 * 位置变更广播（由任务 4.1 的 update 接口调用）
 */
async function broadcastLocationUpdate(userId) {
    try {
        // 【修正二】从 Redis 读取完整数据（JSON 字符串格式）
        const redisKey = `loc:${userId}`;
        const rawData = await redis_1.default.get(redisKey);
        if (!rawData)
            return; // 无位置数据，不广播
        const parsed = JSON.parse(rawData);
        // 【P1-4 修复】使用 Redis 缓存的好友列表
        const friendIds = await (0, friend_cache_1.getFriendIds)(userId);
        const payload = {
            type: 'LOCATION_UPDATE',
            payload: {
                userId,
                lat: parseFloat(parsed.lat),
                lng: parseFloat(parsed.lng),
                accuracy: parseFloat(parsed.accuracy) || 0,
                battery: parseInt(parsed.battery, 10),
                charging: parsed.charging === '1',
                timestamp: parseInt(parsed.timestamp, 10) || Date.now()
            }
        };
        for (const friendId of friendIds) {
            (0, ws_gateway_1.pushToUser)(friendId, payload);
        }
    }
    catch (err) {
        console.error('Broadcast location error:', err);
    }
}
/**
 * 围栏进出事件触发器
 */
async function triggerFenceEvent(userId, eventType, fenceName) {
    const warmMessage = eventType === 'GEOFENCE_ENTER'
        ? `我刚刚安全到达【${fenceName}】啦！`
        : `我刚刚离开【${fenceName}】了哦！`;
    try {
        // 【P1-4 修复】使用 Redis 缓存的好友列表
        const friendIds = await (0, friend_cache_1.getFriendIds)(userId);
        for (const friendId of friendIds) {
            // 【修正三】对齐 QuickMessageService 契约
            const messagePayload = {
                type: 'message:quick',
                payload: {
                    id: (0, uuid_1.v4)(),
                    type: 'system',
                    senderId: userId,
                    receiverId: friendId,
                    fenceId: fenceName,
                    contentKey: eventType === 'GEOFENCE_ENTER' ? 'fence_enter' : 'fence_leave',
                    customText: warmMessage,
                    timestamp: Date.now()
                }
            };
            const isOnline = (0, ws_gateway_1.pushToUser)(friendId, messagePayload);
            // 【修正四】离线兜底写入 fence_events 表
            if (!isOnline) {
                await database_1.default.query('INSERT INTO fence_events (id, receiver_id, sender_id, content, type, delivered, expired, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, NOW())', [(0, uuid_1.v4)(), friendId, userId, warmMessage, 'fence_auto', 0, 0]);
            }
        }
    }
    catch (err) {
        console.error('Trigger fence event error:', err);
    }
}
/**
 * 隐私模式变更广播（暂停/恢复时调用）
 */
async function broadcastPrivacyChange(userId, status) {
    try {
        // 【P1-4 修复】使用 Redis 缓存的好友列表
        const friendIds = await (0, friend_cache_1.getFriendIds)(userId);
        const payload = {
            type: 'friend_privacy_change',
            payload: {
                userId,
                status,
                message: status === 'paused' ? '对方暂时关闭了位置共享' : '对方恢复了位置共享',
            },
        };
        for (const friendId of friendIds) {
            (0, ws_gateway_1.pushToUser)(friendId, payload);
        }
    }
    catch (err) {
        console.error('Broadcast privacy change error:', err);
    }
}
