"""
WebSocket 路由 - 需要实现首帧鉴权
前端已实现首帧鉴权：连接建立后立即发送 {type: 'auth', token: '<token>'}
后端需要：
1. 接收首帧消息
2. 验证token
3. 如果验证成功，使用这个token（而不是URL参数）
4. 如果首帧验证失败，关闭连接

当前前端实现（ws_client.dart）：
- 连接URL: '$baseUrl/ws?token=$token' (向后兼容)
- 首帧消息: {type: 'auth', token: token} (优先使用)
"""

from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from typing import Optional
import json

router = APIRouter()

@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """WebSocket端点，支持首帧鉴权"""
    # 1. 接受连接（先从URL参数获取token作为后备）
    token_from_query = websocket.query_params.get("token")
    
    await websocket.accept()
    
    # 2. 等待首帧鉴权消息（最多等待5秒）
    try:
        # 设置超时
        data = await asyncio.wait_for(websocket.receive_json(), timeout=5.0)
        
        if data.get("type") == "auth":
            token = data.get("token")
            # TODO: 验证token（调用AuthService）
            # if not AuthService.verify_token(token):
            #     await websocket.close(code=4001, reason="鉴权失败")
            #     return
            
            # 鉴权成功，继续处理
            await handle_authenticated_client(websocket, token)
        else:
            # 首帧不是auth，使用URL参数token
            if not token_from_query:
                await websocket.close(code=4001, reason="需要鉴权")
                return
            await handle_authenticated_client(websocket, token_from_query)
            
    except asyncio.TimeoutError:
        # 超时未收到首帧，使用URL参数token
        if not token_from_query:
            await websocket.close(code=4001, reason="鉴权超时")
            return
        await handle_authenticated_client(websocket, token_from_query)
    except Exception as e:
        await websocket.close(code=4000, reason=f"鉴权错误: {str(e)}")
        return

async def handle_authenticated_client(websocket: WebSocket, token: str):
    """处理已鉴权的客户端连接"""
    try:
        while True:
            data = await websocket.receive_json()
            # 处理消息...
            await websocket.send_json({"type": "SYSTEM", "payload": {"message": "收到消息"}})
    except WebSocketDisconnect:
        print(f"客户端断开连接")

# 需要导入asyncio
import asyncio
