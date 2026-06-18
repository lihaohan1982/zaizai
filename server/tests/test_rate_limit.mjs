// P0-2 速率限制验证脚本
// 同一个连接内，5s 窗口内发两条消息，预期第二条被 close(4003)
import WebSocket from 'ws';

const TOKEN = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VySWQiOiIyYTZhZTVjNS01MmIzLTRjOTctYWRlYS0wYzE3ZTM2ZDM1ZjciLCJpYXQiOjE3ODE3MTEzMjgsImV4cCI6MTc4MjMxNjEyOH0.3qqw90-DEcJzJ6zpqXwIiunyDdaxwOVrQB3OR52-Wgg';
const ws = new WebSocket(`ws://localhost:3001/ws?token=${TOKEN}`);
const t0 = Date.now();
let passed = false;

function log(msg) {
  console.log(`[+${((Date.now()-t0)/1000).toFixed(1)}s] ${msg}`);
}

ws.on('open', () => {
  log('连接建立');

  // 第一条业务消息（ping 类型）
  ws.send(JSON.stringify({ type: 'location_update', lat: 39.9, lng: 116.4 }));
  log('第 1 条消息已发送 (location_update)');

  // 2 秒后发第二条（在 5s 窗口内，应触发速率限制）
  setTimeout(() => {
    log(`readyState=${ws.readyState}`);
    if (ws.readyState === WebSocket.OPEN) {
      ws.send(JSON.stringify({ type: 'location_update', lat: 39.91, lng: 116.41 }));
      log('第 2 条消息已发送 (location_update)');
    }
  }, 2000);
});

ws.on('message', (data) => {
  const msg = JSON.parse(data.toString());
  if (msg.type === 'SYSTEM' && msg.payload?.event === 'CONNECTED') {
    log(`← CONNECTED (userId=${msg.payload.userId})`);
  } else {
    log(`← ${msg.type}`);
  }
});

ws.on('ping', () => {
  log('← ping，回复 pong');
  ws.pong();
});

ws.on('close', (code, reason) => {
  log(`close: code=${code} reason=${reason.toString()}`);
  if (code === 4003) {
    log('✅ P0-2 速率限制验证通过！');
    passed = true;
  } else if (code === 4002) {
    log('❌ 心跳超时，速率限制未生效');
  } else {
    log(`❌ 非预期 close code: ${code}`);
  }
  process.exit(passed ? 0 : 1);
});

ws.on('error', (err) => {
  log(`error: ${err.message}`);
  process.exit(1);
});

setTimeout(() => {
  log('⏰ 超时 15s — 未收到 close');
  process.exit(1);
}, 15000);
