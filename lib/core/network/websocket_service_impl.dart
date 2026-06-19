// WebSocketService 实现：将 WsClient 的多路 Stream 适配为统一的 onMessage流
//
// WsClient 的事件分发设计（type 路由）：
//   SYSTEM             → onSystem
//   LOCATION_UPDATE    → onLocationUpdate
//   friend_privacy_change → onFriendPrivacyChange
//   initial_sync        → onInitialSync
//   message_quick       → onQuickMessage
//
// WebSocketService.onMessage 只路由 message_quick，其他类型由各自专有 Stream 处理。
import 'dart:async';
import 'package:location_chat_app/core/network/ws_client.dart';
import 'package:location_chat_app/core/network/websocket_service.dart';

class WebSocketServiceImpl implements WebSocketService {
  final WsClient _wsClient;
  final _onMessageController = StreamController<Map<String, dynamic>>.broadcast();

  WebSocketServiceImpl(this._wsClient) {
    // 将 WsClient 的 onQuickMessage（已包含 payload）透传到 onMessage
    _wsClient.onQuickMessage.listen((payload) {
      _onMessageController.add(payload);
    });
  }

  @override
  bool get isConnected => _wsClient.isConnected;

  @override
  Stream<Map<String, dynamic>> get onMessage => _onMessageController.stream;

  @override
  Future<void> connect(String token) async {
    _wsClient.connect();
  }

  @override
  void disconnect() {
    _wsClient.disconnect();
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {
    _wsClient.send({'type': event, ...payload});
  }

  void dispose() {
    _onMessageController.close();
  }
}
