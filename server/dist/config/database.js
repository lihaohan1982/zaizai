"use strict";
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.checkJWTSecret = exports.connectDB = void 0;
const promise_1 = __importDefault(require("mysql2/promise"));
const dotenv_1 = __importDefault(require("dotenv"));
// Ensure env loaded before creating pool
dotenv_1.default.config();
const pool = promise_1.default.createPool({
    host: process.env.DB_HOST || '127.0.0.1',
    port: parseInt(process.env.DB_PORT || '3307'),
    user: process.env.DB_USER || 'root',
    password: process.env.DB_PASSWORD || process.env.DB_PASS || '',
    database: process.env.DB_NAME || 'location_chat',
    waitForConnections: true,
    connectionLimit: 10,
    queueLimit: 0,
});
const connectDB = async () => {
    try {
        const conn = await pool.getConnection();
        await conn.query('SELECT NOW()');
        conn.release();
        console.log('✅ Database connected successfully');
    }
    catch (err) {
        console.error('❌ Database connection failed:', err);
        process.exit(-1);
    }
};
exports.connectDB = connectDB;
const checkJWTSecret = () => {
    const secret = process.env.JWT_SECRET;
    if (!secret || secret.length < 32) {
        console.error('❌ FATAL: JWT_SECRET must be at least 32 characters long');
        process.exit(-1);
    }
    console.log('✅ JWT_SECRET validation passed');
};
exports.checkJWTSecret = checkJWTSecret;
exports.default = pool;
