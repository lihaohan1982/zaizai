import mysql from 'mysql2/promise';
import dotenv from 'dotenv';

// Ensure env loaded before creating pool
dotenv.config();

const pool = mysql.createPool({
  host: process.env.DB_HOST || '127.0.0.1',
  port: parseInt(process.env.DB_PORT || '3307'),
  user: process.env.DB_USER || 'root',
  password: process.env.DB_PASSWORD || process.env.DB_PASS || '',
  database: process.env.DB_NAME || 'location_chat',
  waitForConnections: true,
  connectionLimit: 10,
  queueLimit: 0,
});

export const connectDB = async (): Promise<void> => {
  try {
    const conn = await pool.getConnection();
    await conn.query('SELECT NOW()');
    conn.release();
    console.log('✅ Database connected successfully');
  } catch (err) {
    console.error('❌ Database connection failed:', err);
    process.exit(-1);
  }
};

export const checkJWTSecret = (): void => {
  const secret = process.env.JWT_SECRET;
  if (!secret || secret.length < 32) {
    console.error('❌ FATAL: JWT_SECRET must be at least 32 characters long');
    process.exit(-1);
  }
  console.log('✅ JWT_SECRET validation passed');
};

export default pool;
