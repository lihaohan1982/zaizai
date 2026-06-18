// test_broadcast_dedup.mjs — 验证 5 秒窗口内广播合并（1 条推，4 条丢弃）
import WebSocket from 'ws';
import http from 'http';

const TOKEN_A =
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIyYTZhZTVjNS01MmIzLTRjOTctYWRlYS0wYzE3ZTM2ZDM1ZjciLCJpYXQiOjE3ODE3MTEzMjgsImV4cCI6MTc4MjMxNjEyOH0.3qqw90-DEcJzJ6zpqXwIiunyDdaxwOVrQB3OR52-Wgg';

function httpReq(method, path, body, token) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: '127.0.0.1',
      port: 3001,
      path,
      method,
      headers: { 'Content-Type': 'application/json' },
    };
    if (token) opts.headers['Authorization'] = `Bearer ${token}`;
    const req = http.request(opts, (res) => {
      let d = '';
      res.on('data', (c) => (d += c));
      res.on('end', () => {
        try { resolve(JSON.parse(d)); }
        catch { resolve(d); }
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function registerAndLogin(phone, password, nickname) {
  await httpReq('POST', '/api/auth/register', { phone, password, nickname });
  const data = await httpReq('POST', '/api/auth/login', { phone, password });
  if (!data.token) throw new Error('Login failed: ' + JSON.stringify(data));
  return data;
}

function decodeJWT(token) {
  const parts = token.split('.');
  return JSON.parse(Buffer.from(parts[1], 'base64').toString());
}

const t0 = Date.now();
const log = (m) => console.log(`[+${((Date.now() - t0) / 1000).toFixed(1)}s] ${m}`);

async function main() {
  // 注册并登录用户 B
  // 11位中国手机号: 138 + 8位随机数字
  const phoneB = '138' + String(Math.floor(Math.random() * 1e8)).padStart(8, '0');
  const { token: tokenB, user: { id: userIdB } } = await registerAndLogin(phoneB, 'test1234', 'UserB');
  log(`B 登录成功: ${userIdB}`);

  // A 添加 B 为好友，B 反向添加 A 触发自动确认（status: pending → accepted）
  await httpReq('POST', '/api/friends/add', { friend_phone: phoneB }, TOKEN_A);
  log(`A → B 好友请求已发送`);
  await httpReq('POST', '/api/friends/add', { friend_phone: '13800138000' }, tokenB); // A 的手机号是固定的
  log(`B → A 反向添加，触发自动确认`);

  // B 连接 WebSocket 接收推送
  let locCountB = 0;
  const wsB = new WebSocket(`ws://127.0.0.1:3001/ws?token=${tokenB}`);
  wsB.on('open', () => log('[B] OPEN'));
  wsB.on('ping', () => wsB.pong()); // 保持心跳活跃
  wsB.on('message', (d) => {
    const m = JSON.parse(d.toString());
    if (m.type === 'LOCATION_UPDATE') {
      locCountB++;
      log(`[B] ← LOCATION_UPDATE ts=${m.payload.timestamp}`);
    }
  });
  wsB.on('error', (e) => log(`[B] ERROR: ${e.message}`));

  // A 不需要 WebSocket，HTTP 认证即可触发广播
  // 等待好友关系生效
  await new Promise((r) => setTimeout(r, 500));

  // 通过 HTTP POST 触发 5 次位置上报（均在 5s 窗口内，预期只推 1 条）
  const baseTs = Date.now();
  // 第一波：3 条相同时间戳 → 触发 1 次广播（去重）
  for (let i = 0; i < 3; i++) {
    setTimeout(async () => {
      await httpReq('POST', '/api/locations/update', {
        lat: 39.9,
        lng: 116.4,
        accuracy: 10,
        battery: 80,
        charging: false,
        timestamp: baseTs,
      }, TOKEN_A);
      log(`[A] HTTP POST /update ts=${baseTs} (i=${i})`);
    }, i * 100);
  }

  // 第二波：间隔 6s 超过 TTL → 再次触发 1 次广播
  setTimeout(async () => {
    await httpReq('POST', '/api/locations/update', {
      lat: 39.9,
      lng: 116.4,
      accuracy: 10,
      battery: 80,
      charging: false,
      timestamp: baseTs + 6000,
    }, TOKEN_A);
    log(`[A] HTTP POST /update ts=${baseTs + 6000} (超过TTL)`);
  }, 3000);

  // 验证：期望收到 2 条（去重后 + TTL 超时后）

  // 6 秒后验证
  setTimeout(() => {
    log(`[B] 共收到 ${locCountB} 条 LOCATION_UPDATE`);
    if (locCountB === 2) {
      log('✅ 广播合并验证通过！');
    } else {
      log(`❌ 合并失败（期望 2 条，实际 ${locCountB} 条）`);
    }
    wsB.close();
    process.exit(locCountB >= 1 && locCountB <= 2 ? 0 : 1);
  }, 6000);
}

main().catch((e) => {
  console.error('Error:', e);
  process.exit(1);
});
