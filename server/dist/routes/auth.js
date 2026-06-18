"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
const express_1 = __importDefault(require("express"));
const bcryptjs_1 = __importDefault(require("bcryptjs"));
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const uuid_1 = require("uuid");
const database_1 = __importDefault(require("../config/database"));
const router = express_1.default.Router();
// 注册接口
router.post('/register', async (req, res) => {
    const { phone, password, nickname } = req.body;
    if (!/^1[3-9]\d{9}$/.test(phone)) {
        return res.status(400).json({
            error: { code: 'INVALID_PHONE', message: '手机号格式错误' }
        });
    }
    if (password.length < 6) {
        return res.status(400).json({
            error: { code: 'INVALID_PASSWORD', message: '密码至少6位' }
        });
    }
    try {
        const [existing] = await database_1.default.query('SELECT id FROM users WHERE phone = ?', [phone]);
        if (existing.length > 0) {
            return res.status(409).json({
                error: { code: 'USER_EXISTS', message: '用户已存在' }
            });
        }
        const userId = (0, uuid_1.v4)();
        const passwordHash = await bcryptjs_1.default.hash(password, 12);
        await database_1.default.query('INSERT INTO users (id, phone, password_hash, nickname) VALUES (?, ?, ?, ?)', [userId, phone, passwordHash, nickname || null]);
        const token = jsonwebtoken_1.default.sign({ userId }, process.env.JWT_SECRET, { expiresIn: '7d' });
        res.status(201).json({
            user: { id: userId, phone, nickname: nickname || null },
            token
        });
    }
    catch (err) {
        console.error('Register error:', err);
        res.status(500).json({
            error: { code: 'INTERNAL_ERROR', message: '注册失败' }
        });
    }
});
// 登录接口
router.post('/login', async (req, res) => {
    const { phone, password } = req.body;
    try {
        const [rows] = await database_1.default.query('SELECT * FROM users WHERE phone = ?', [phone]);
        const users = rows;
        if (users.length === 0) {
            return res.status(401).json({
                error: { code: 'AUTH_FAILED', message: '手机号或密码错误' }
            });
        }
        const user = users[0];
        const match = await bcryptjs_1.default.compare(password, user.password_hash);
        if (!match) {
            return res.status(401).json({
                error: { code: 'AUTH_FAILED', message: '手机号或密码错误' }
            });
        }
        const token = jsonwebtoken_1.default.sign({ userId: user.id }, process.env.JWT_SECRET, { expiresIn: '7d' });
        res.json({
            user: {
                id: user.id,
                phone: user.phone,
                nickname: user.nickname,
                avatar_url: user.avatar_url,
                privacy_settings: user.privacy_settings
            },
            token
        });
    }
    catch (err) {
        console.error('Login error:', err);
        res.status(500).json({
            error: { code: 'INTERNAL_ERROR', message: '登录失败' }
        });
    }
});
// 获取当前用户信息
router.get('/me', async (req, res) => {
    const authHeader = req.headers.authorization;
    if (!authHeader || !authHeader.startsWith('Bearer ')) {
        return res.status(401).json({
            error: { code: 'AUTH_FAILED', message: '未提供认证令牌' }
        });
    }
    try {
        const token = authHeader.split(' ')[1];
        const decoded = jsonwebtoken_1.default.verify(token, process.env.JWT_SECRET);
        const [rows] = await database_1.default.query('SELECT id, phone, nickname, avatar_url, privacy_settings FROM users WHERE id = ?', [decoded.userId]);
        const users = rows;
        if (users.length === 0) {
            return res.status(404).json({
                error: { code: 'USER_NOT_FOUND', message: '用户不存在' }
            });
        }
        res.json({ user: users[0] });
    }
    catch (err) {
        res.status(401).json({
            error: { code: 'AUTH_FAILED', message: '认证令牌无效或已过期' }
        });
    }
});
exports.default = router;
