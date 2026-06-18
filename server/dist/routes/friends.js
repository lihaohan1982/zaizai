"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const uuid_1 = require("uuid");
const database_1 = __importDefault(require("../config/database"));
const auth_1 = require("../middleware/auth");
const friend_cache_1 = require("../utils/friend_cache");
const router = express_1.default.Router();
// POST /api/friends/add
router.post('/add', auth_1.authenticate, async (req, res) => {
    const { friend_phone } = req.body;
    const currentUserId = req.user.userId;
    if (!friend_phone) {
        return res.status(400).json({
            error: { code: 'MISSING_FIELD', message: 'friend_phone 必填' }
        });
    }
    try {
        // 1. 查找目标用户
        const [friendRows] = await database_1.default.query('SELECT id FROM users WHERE phone = ?', [friend_phone]);
        if (friendRows.length === 0) {
            return res.status(404).json({
                error: { code: 'USER_NOT_FOUND', message: '用户不存在' }
            });
        }
        const friendId = friendRows[0].id;
        if (friendId === currentUserId) {
            return res.status(400).json({
                error: { code: 'CANNOT_ADD_SELF', message: '不能添加自己' }
            });
        }
        // 2. 排序 ID 保证唯一键
        const [id1, id2] = [currentUserId, friendId].sort();
        // 3. ON DUPLICATE KEY UPDATE 原子操作
        await database_1.default.query(`INSERT INTO friendships (id, user_id_1, user_id_2, status, initiator_id)
       VALUES (?, ?, ?, ?, ?)
       ON DUPLICATE KEY UPDATE
         status = CASE
           WHEN status = 'pending' AND initiator_id != VALUES(initiator_id) THEN 'accepted'
           ELSE status
         END`, [(0, uuid_1.v4)(), id1, id2, 'pending', currentUserId]);
        // 4. 二次查询获取结果
        const [resultRows] = await database_1.default.query('SELECT status, initiator_id FROM friendships WHERE user_id_1 = ? AND user_id_2 = ?', [id1, id2]);
        const row = resultRows[0];
        // 4. 好友关系变更时，使双方缓存失效【P1-4】
        await Promise.all([
            (0, friend_cache_1.invalidateFriendCache)(currentUserId),
            (0, friend_cache_1.invalidateFriendCache)(friendId),
        ]);
        if (row.status === 'accepted' && row.initiator_id !== currentUserId) {
            return res.json({ success: true, message: '好友请求已自动通过', autoAccepted: true });
        }
        if (row.status === 'pending' && row.initiator_id === currentUserId) {
            return res.json({ success: true, message: '好友请求已发送' });
        }
        if (row.status === 'accepted') {
            return res.status(409).json({
                error: { code: 'ALREADY_FRIENDS', message: '你们已经是好友' }
            });
        }
        res.json({ success: true, message: '好友请求已发送' });
    }
    catch (err) {
        console.error('Add friend error:', err);
        res.status(500).json({
            error: { code: 'INTERNAL_ERROR', message: '添加好友失败' }
        });
    }
});
// GET /api/friends/list
router.get('/list', auth_1.authenticate, async (req, res) => {
    const currentUserId = req.user.userId;
    try {
        const [rows] = await database_1.default.query(`SELECT u.id, u.phone, u.nickname, u.avatar_url, f.status, f.created_at
       FROM friendships f
       JOIN users u ON (u.id = CASE WHEN f.user_id_1 = ? THEN f.user_id_2 ELSE f.user_id_1 END)
       WHERE (f.user_id_1 = ? OR f.user_id_2 = ?)
         AND f.status = 'accepted'
       ORDER BY f.created_at DESC`, [currentUserId, currentUserId, currentUserId]);
        res.json({ friends: rows });
    }
    catch (err) {
        console.error('List friends error:', err);
        res.status(500).json({
            error: { code: 'INTERNAL_ERROR', message: '获取好友列表失败' }
        });
    }
});
exports.default = router;
