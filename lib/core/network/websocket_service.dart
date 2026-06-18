// lib/core/network/websocket_service.dart

abstract class WebSocketService {
  bool get isConnected;
  Stream<Map<String, dynamic>> get onMessage;
  Future<void> connect(String token);
  void disconnect();
  Future<void> send(String event, Map<String, dynamic> payload);
}
