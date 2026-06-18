import express from 'express';
import dotenv from 'dotenv';
import helmet from 'helmet';
import cors from 'cors';
import rateLimit from 'express-rate-limit';
import authRoutes from './routes/auth';
import friendRoutes from './routes/friends';
import locationRoutes from './routes/locations';
import privacyRoutes from './routes/privacy';
import { connectDB, checkJWTSecret } from './config/database';
import pool from './config/database';
import { connectRedis } from './config/redis';
import { initWebSocketGateway } from './ws/ws-gateway';

// Global error handlers to prevent silent crashes
process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection:', reason);
});
process.on('uncaughtException', (err) => {
  console.error('Uncaught Exception:', err);
});

// Load environment variables
dotenv.config();

// P0-1 修复: JWT_SECRET 启动校验（必须在所有服务启动前执行）
if (!process.env.JWT_SECRET || process.env.JWT_SECRET.length < 32) {
  console.error('FATAL: JWT_SECRET 未设置或长度不足 32 位。服务器拒绝启动。');
  process.exit(1);
}

// Check JWT_SECRET at startup
checkJWTSecret();

const app = express();
const PORT = process.env.PORT || 3000;

// Security middleware
app.use(helmet());

// CORS 配置
// - 生产：仅允许指定域名
// - 开发：允许所有 localhost（端口不限）+ Vite/Flutter Web 默认端口
const corsOrigins = process.env.NODE_ENV === 'production'
  ? ['https://yourdomain.com', 'https://www.yourdomain.com']
  : [
      'http://localhost',
      'http://127.0.0.1',
      'http://10.0.2.2', // Android 模拟器访问宿主机
      /http:\/\/localhost:\d+/, // 任意随机端口
    ];

app.use(cors({
  origin: corsOrigins,
  credentials: true,
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Content-Type', 'Authorization'],
}));

// Rate limiting
const limiter = rateLimit({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 100, // limit each IP to 100 requests per windowMs
  message: {
    error: {
      code: 'RATE_LIMIT_EXCEEDED',
      message: '请求过于频繁，请稍后再试'
    }
  }
});
app.use('/api/', limiter);

// Body parser
app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true, limit: '10mb' }));

// Health check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'ok',
    timestamp: new Date().toISOString(),
    uptime: process.uptime()
  });
});

// API routes
app.use('/api/auth', authRoutes);
app.use('/api/friends', friendRoutes);
app.use('/api/locations', locationRoutes);
app.use('/api/privacy', privacyRoutes);

// 404 handler
app.use((req, res) => {
  res.status(404).json({
    error: {
      code: 'NOT_FOUND',
      message: '请求的资源不存在'
    }
  });
});

// Error handler
app.use((err: Error, req: express.Request, res: express.Response, next: express.NextFunction) => {
  console.error('Unhandled error:', err);
  res.status(500).json({
    error: {
      code: 'INTERNAL_ERROR',
      message: '服务器内部错误'
    }
  });
});

// Start server
const startServer = async (): Promise<void> => {
  try {
    // Connect to database
    await connectDB();
    
    // Connect to Redis
    await connectRedis();
    
    // Start listening
    const server = app.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
      console.log(`📍 Health check: http://localhost:${PORT}/health`);
      console.log(`🔐 Auth API: http://localhost:${PORT}/api/auth`);
    });

    // Initialize WebSocket gateway
    initWebSocketGateway(server, pool);
  } catch (err) {
    console.error('Failed to start server:', err);
    process.exit(-1);
  }
};

startServer();
