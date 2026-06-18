// test/core/messaging/fakes/fake_websocket_service.dart

import 'dart:async';
import 'package:location_chat_app/core/network/websocket_service.dart';

class FakeWebSocketService implements WebSocketService {
  bool _isConnected = false;
  final List<Map<String, dynamic>> _sentMessages = [];
  final List<void Function(Map<String, dynamic>)> _messageHandlers = [];
  final StreamController<Map<String, dynamic>> _onMessageController =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  bool get isConnected => _isConnected;
  List<Map<String, dynamic>> get sentMessages => List.unmodifiable(_sentMessages);
  void clearSentMessages() => _sentMessages.clear();

  /// 测试辅助：直接设置连接状态
  void setConnected(bool connected) {
    _isConnected = connected;
  }

  @override
  Stream<Map<String, dynamic>> get onMessage => _onMessageController.stream;

  @override
  Future<void> connect(String token) async {
    _isConnected = true;
  }

  @override
  Future<void> disconnect() async {
    _isConnected = false;
  }

  bool throwOnSend = false;
  Exception? sendException;

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {
    if (throwOnSend) {
      throw sendException ?? Exception('forced send error');
    }
    if (!_isConnected) {
      throw StateError('WebSocket not connected');
    }
    _sentMessages.add({'event': event, 'payload': payload});
  }

  void simulateIncomingMessage(Map<String, dynamic> data) {
    _onMessageController.add(data);
  }

  void reset() {
    _sentMessages.clear();
    _messageHandlers.clear();
    _isConnected = false;
  }

  void dispose() {
    _onMessageController.close();
  }
}
