import 'dart:async';
import 'package:location_chat_app/core/message/quick_message_service.dart';

class MockWsClient implements WsClient {
  final List<_Call> _history = [];
  final _statusController = StreamController<_WsStatus>.broadcast();
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();

  _WsStatus _currentStatus = _WsStatus.disconnected;
  Stream<_WsStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get messageStream => _messageController.stream;

  void connect() {
    _currentStatus = _WsStatus.connected;
    _statusController.add(_currentStatus);
  }

  void disconnect() {
    _currentStatus = _WsStatus.disconnected;
    _statusController.add(_currentStatus);
  }

  void simulateServerPush(Map<String, dynamic> data) {
    _messageController.add(data);
  }

  @override
  void emit(String event, dynamic data) {
    _history.add(_Call(event: event, data: data));
  }

  void clearHistory() => _history.clear();
  bool didEmit(String event) => _history.any((c) => c.event == event);
  int emitCount(String event) => _history.where((c) => c.event == event).length;
  Map<String, dynamic>? lastEmitData(String event) {
    for (int i = _history.length - 1; i >= 0; i--) {
      if (_history[i].event == event) {
        return Map<String, dynamic>.from(_history[i].data as Map);
      }
    }
    return null;
  }

  void dispose() {
    _statusController.close();
    _messageController.close();
  }
}

class _Call {
  final String event;
  final dynamic data;
  _Call({required this.event, required this.data});
}

enum _WsStatus { disconnected, connecting, connected, reconnecting }
