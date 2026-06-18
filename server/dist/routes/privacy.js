"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = require("express");
const auth_1 = require("../middleware/auth");
const location_broadcaster_1 = require("../ws/location-broadcaster");
const redis_1 = __importDefault(require("../config/redis"));
const router = (0, express_1.Router)();
// ============================================================
// P1-5 修复: pauseSharing 添加 24 小时上限
// ============================================================
const MAX_PAUSE_DURATION_HOURS = 24;
// Redis Key: pause:${userId}
function getPauseKey(userId) {
    return `pause:${userId}`;
}
/**
 * POST /api/privacy/pause
 * 暂停位置共享（可选 duration 参数，最大 24 小时）
 *
 * 请求体: { duration?: number }  // 小时数，默认 24，上限 24
 */
router.post('/pause', auth_1.authenticate, async (req, res) => {
    const userId = req.user.userId;
    const { duration } = req.body;
    // 校验暂停时长
    let durationHours = MAX_PAUSE_DURATION_HOURS; // 默认 24 小时
    if (duration !== undefined) {
        if (typeof duration !== 'number' || duration <= 0) {
            return res.status(400).json({
                error: { code: 'INVALID_DURATION', message: '暂停时长必须为正数' }
            });
        }
        if (duration > MAX_PAUSE_DURATION_HOURS) {
            return res.status(400).json({
                error: { code: 'INVALID_DURATION', message: `暂停时长不能超过 ${MAX_PAUSE_DURATION_HOURS} 小时` }
            });
        }
        durationHours = duration;
    }
    try {
        const now = Date.now();
        const pauseRecord = {
            pausedAt: now,
            expiresAt: now + durationHours * 60 * 60 * 1000,
        };
        // 写入 Redis（TTL = 暂停时长 + 1 小时缓冲）
        const pauseKey = getPauseKey(userId);
        await redis_1.default.setEx(pauseKey, (durationHours + 1) * 3600, JSON.stringify(pauseRecord));
        // 广播隐私变更
        await (0, location_broadcaster_1.broadcastPrivacyChange)(userId, 'paused');
        res.json({
            ok: true,
            status: 'paused',
            durationHours,
            expiresAt: pauseRecord.expiresAt,
        });
    }
    catch (err) {
        console.error('Privacy pause error:', err);
        res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '暂停失败' } });
    }
});
/**
 * POST /api/privacy/resume
 * 恢复位置共享（手动取消暂停）
 */
router.post('/resume', auth_1.authenticate, async (req, res) => {
    const userId = req.user.userId;
    try {
        const pauseKey = getPauseKey(userId);
        const existing = await redis_1.default.get(pauseKey);
        if (!existing) {
            return res.status(400).json({
                error: { code: 'NOT_PAUSED', message: '当前未处于暂停状态' }
            });
        }
        // 删除暂停记录
        await redis_1.default.del(pauseKey);
        // 广播隐私恢复
        await (0, location_broadcaster_1.broadcastPrivacyChange)(userId, 'resumed');
        res.json({ ok: true, status: 'resumed' });
    }
    catch (err) {
        console.error('Privacy resume error:', err);
        res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '恢复失败' } });
    }
});
/**
 * GET /api/privacy/status
 * 查询当前暂停状态（供前端和 WebSocket 使用）
 */
router.get('/status', auth_1.authenticate, async (req, res) => {
    const userId = req.user.userId;
    try {
        const pauseKey = getPauseKey(userId);
        const raw = await redis_1.default.get(pauseKey);
        if (!raw) {
            return res.json({ status: 'active', paused: false });
        }
        const record = JSON.parse(raw);
        const now = Date.now();
        if (now >= record.expiresAt) {
            // 已自动过期，清理并恢复
            await redis_1.default.del(pauseKey);
            return res.json({ status: 'active', paused: false, autoExpired: true });
        }
        const remainingMs = record.expiresAt - now;
        const remainingHours = Math.ceil(remainingMs / (60 * 60 * 1000));
        res.json({
            status: 'paused',
            paused: true,
            pausedAt: record.pausedAt,
            expiresAt: record.expiresAt,
            remainingHours,
        });
    }
    catch (err) {
        console.error('Privacy status error:', err);
        res.status(500).json({ error: { code: 'INTERNAL_ERROR', message: '查询失败' } });
    }
});
exports.default = router;
