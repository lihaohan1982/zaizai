import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/status.dart' as status;

/// WebSocket 客户端
///
/// 功能：连接管理、心跳检测、指数退避重连、事件分发
class WsClient {
  final String baseUrl;
  final String token;
  final Duration heartbeatInterval;
  final Duration pongTimeout;
  final int maxReconnectAttempts;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _heartbeatTimer;
  Timer? _pongTimer;
  int _reconnectAttempts = 0;
  bool _intentionalClose = false;

  // 事件分发（用 StreamController 替代 EventEmitter）
  final _onConnected = StreamController<void>.broadcast();
  final _onDisconnected = StreamController<void>.broadcast();
  final _onLocationUpdate = StreamController<Map<String, dynamic>>.broadcast();
  final _onFriendPrivacyChange = StreamController<Map<String, dynamic>>.broadcast();
  final _onInitialSync = StreamController<Map<String, dynamic>>.broadcast();
  final _onSystem = StreamController<Map<String, dynamic>>.broadcast();
  final _onQuickMessage = StreamController<Map<String, dynamic>>.broadcast();
  final _onError = StreamController<Object>.broadcast();

  Stream<void> get onConnected => _onConnected.stream;
  Stream<Map<String, dynamic>> get onLocationUpdate => _onLocationUpdate.stream;
  Stream<Map<String, dynamic>> get onFriendPrivacyChange => _onFriendPrivacyChange.stream;
  Stream<Map<String, dynamic>> get onInitialSync => _onInitialSync.stream;
  Stream<Map<String, dynamic>> get onSystem => _onSystem.stream;
  Stream<Map<String, dynamic>> get onQuickMessage => _onQuickMessage.stream;
  Stream<void> get onDisconnected => _onDisconnected.stream;
  Stream<Object> get onError => _onError.stream;

  bool get isConnected => _channel != null;

  WsClient({
    required this.baseUrl,
    required this.token,
    this.heartbeatInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 10),
    this.maxReconnectAttempts = 10,
  });

  /// 建立连接，并在连接成功后发送首帧鉴权消息
  ///
  /// 阶段三安全整改：除 URL 查询参数 token 外，连接建立后立即发送
  /// `{type: 'auth', token: ...}` 首帧，供后端优先采用首帧鉴权。
  void connect() {
    _intentionalClose = false;
    _doConnect();
  }

  void _doConnect() {
    try {
      final wsUrl = Uri.parse('$baseUrl/ws?token=$token');
      _channel = WebSocketChannel.connect(wsUrl);

      _subscription = _channel!.stream.listen(
        (data) => _handleMessage(data),
        onError: (err) {
          _onError.add(err);
          _scheduleReconnect();
        },
        onDone: () {
          _cleanupTimers();
          _onDisconnected.add(null);
          if (!_intentionalClose) _scheduleReconnect();
        },
      );

      _startHeartbeat();
      _reconnectAttempts = 0;
      _onConnected.add(null);

      // 首帧鉴权：连接建立后立即发送 token
      if (token.isNotEmpty) {
        _sendAuthFrame();
      }
    } catch (e) {
      _onError.add(e);
      _scheduleReconnect();
    }
  }

  void _sendAuthFrame() {
    try {
      final authFrame = json.encode({'type': 'auth', 'token': token});
      _channel?.sink.add(authFrame);
    } catch (e) {
      _onError.add(e);
    }
  }

  /// 处理收到的消息
  void _handleMessage(dynamic data) {
    try {
      final Map<String, dynamic> msg = jsonDecode(data as String);
      final type = msg['type'] as String?;

      switch (type) {
        case 'SYSTEM':
          _onSystem.add(msg['payload'] as Map<String, dynamic>);
          break;
        case 'LOCATION_UPDATE':
          _onLocationUpdate.add(msg['payload'] as Map<String, dynamic>);
          break;
        case 'friend_privacy_change':
          _onFriendPrivacyChange.add(msg['payload'] as Map<String, dynamic>);
          break;
        case 'initial_sync':
          _onInitialSync.add(msg['payload'] as Map<String, dynamic>);
          break;
        case 'message_quick':
          _onQuickMessage.add(msg['payload'] as Map<String, dynamic>);
          break;
        default:
          // 未知类型，忽略
          break;
      }
    } catch (e) {
      _onError.add(e);
    }
  }

  /// 启动心跳
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) {
      _channel?.sink.add('ping');
      // 启动 pong 超时定时器
      _pongTimer?.cancel();
      _pongTimer = Timer(pongTimeout, () {
        // 心跳超时，主动断开并重连
        disconnect();
        _scheduleReconnect();
      });
    });
  }

  /// 取消心跳定时器
  void _cleanupTimers() {
    _heartbeatTimer?.cancel();
    _pongTimer?.cancel();
    _heartbeatTimer = null;
    _pongTimer = null;
  }

  /// 指数退避重连
  void _scheduleReconnect() {
    if (_intentionalClose) return;
    if (_reconnectAttempts >= maxReconnectAttempts) return;

    _reconnectAttempts++;
    // 指数退避：2^attempts 秒，上限 60 秒
    final delay = Duration(
      seconds: (1 << _reconnectAttempts).clamp(2, 60),
    );
    Timer(delay, _doConnect);
  }

  /// 主动断开连接
  void disconnect() {
    _intentionalClose = true;
    _cleanupTimers();
    _subscription?.cancel();
    _channel?.sink.close(status.normalClosure);
    _channel = null;
  }

  /// 发送消息
  void send(Map<String, dynamic> message) {
    if (_channel == null) {
      _onError.add(StateError('WebSocket not connected'));
      return;
    }
    _channel!.sink.add(jsonEncode(message));
  }

  /// 释放资源
  void dispose() {
    disconnect();
    _onConnected.close();
    _onDisconnected.close();
    _onLocationUpdate.close();
    _onFriendPrivacyChange.close();
    _onInitialSync.close();
    _onSystem.close();
    _onQuickMessage.close();
    _onError.close();
  }
}
