"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.authenticate = void 0;
const jsonwebtoken_1 = __importDefault(require("jsonwebtoken"));
const authenticate = async (req, res, next) => {
    try {
        const authHeader = req.headers.authorization;
        if (!authHeader || !authHeader.startsWith('Bearer ')) {
            res.status(401).json({
                error: {
                    code: 'AUTH_FAILED',
                    message: '未提供认证令牌'
                }
            });
            return;
        }
        const token = authHeader.split(' ')[1];
        const secret = process.env.JWT_SECRET;
        const decoded = jsonwebtoken_1.default.verify(token, secret);
        req.user = { userId: decoded.userId };
        next();
    }
    catch (err) {
        res.status(401).json({
            error: {
                code: 'AUTH_FAILED',
                message: '认证令牌无效或已过期'
            }
        });
    }
};
exports.authenticate = authenticate;
