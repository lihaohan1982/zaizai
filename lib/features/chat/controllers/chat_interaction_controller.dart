// lib/features/chat/controllers/chat_interaction_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:location_chat_app/core/utils/geo_utils.dart';
import 'package:location_chat_app/core/auth/auth_state.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/messaging/quick_message_service.dart';
import 'package:location_chat_app/core/network/dio_client.dart';
import 'package:location_chat_app/core/network/ws_client.dart';

/// 好友互动控制器：消息收发、状态订阅、位置卡更新
///
/// 修正点（v2）：
///   - 移除 BuildContext 依赖，改用 GlobalKey[ScaffoldMessengerState] 显示 Toast
///   - 增加 _loadError 状态字段，支持 UI 展示加载失败反馈
///   - 注入 fences 列表，在 _updateFriendLocationData 中直接计算位置描述文本
///   - 注入 AuthState 替代 UserIdProvider，获取 currentUser 更简洁
class ChatInteractionController extends ChangeNotifier {
  final String friendId;
  final QuickMessageService _quickMessageService;
  final WsClient _wsClient;
  final AuthState _authState;
  final DioClient _dioClient;

  /// 注入围栏列表（用于计算位置描述）
  final List<Map<String, dynamic>> fences;

  /// 全局 ScaffoldMessenger Key（解决无 BuildContext 时的 Toast 显示）
  final GlobalKey<ScaffoldMessengerState> messengerKey;

  List<MessagePayload> _messages = [];
  List<MessagePayload> get messages => List.unmodifiable(_messages);

  bool _loadError = false;
  bool get loadError => _loadError;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  Map<String, dynamic>? _friendLocationData;
  Map<String, dynamic>? get friendLocationData => _friendLocationData;

  final ValueNotifier<bool> _isFriendPaused = ValueNotifier(false);
  bool get isFriendPaused => _isFriendPaused.value;

  /// WebSocket 断线状态（P3 初始状态时序修复）
  bool _isWsDisconnected = false;
  bool get isWsDisconnected => _isWsDisconnected;

  StreamSubscription<void>? _wsConnectedSub;
  StreamSubscription<void>? _wsDisconnectedSub;

  bool _isPokeLocked = false;
  bool _isDisposed = false;
  StreamSubscription<Map<String, dynamic>>? _msgSub;
  StreamSubscription<Map<String, dynamic>>? _privacySub;

  String get currentUserId => _authState.currentUserId ?? '';

  ChatInteractionController({
    required this.messengerKey,
    required this.friendId,
    required this.fences,
    required QuickMessageService quickMessageService,
    required WsClient wsClient,
    required AuthState authState,
    required DioClient dioClient,
  })  : _quickMessageService = quickMessageService,
        _wsClient = wsClient,
        _authState = authState,
        _dioClient = dioClient {
    _init();
  }

  void _init() {
    // P3 修正：先同步检查当前连接状态，防止初始断线状态丢失
    _isWsDisconnected = !_wsClient.isConnected;

    // 监听 WebSocket 连接状态变化
    _wsConnectedSub = _wsClient.onConnected.listen((_) {
      if (_isWsDisconnected) {
        _isWsDisconnected = false;
        notifyListeners();
      }
    });
    _wsDisconnectedSub = _wsClient.onDisconnected.listen((_) {
      if (!_isWsDisconnected) {
        _isWsDisconnected = true;
        notifyListeners();
      }
    });

    _loadHistory();

    // 订阅实时消息流
    _msgSub = _wsClient.onQuickMessage.listen((payload) {
      try {
        final msg = MessagePayload.fromJson(payload);
        if (msg.senderId == friendId) {
          _addMessage(msg);

          // 附带位置数据 + 位置描述计算
          if (msg.lat != null && msg.lng != null) {
            _updateFriendLocationData({
              'lat': msg.lat,
              'lng': msg.lng,
              'battery': msg.customText,
              'timestamp': msg.timestamp,
            });
          }

          // 拍一拍通知
          if (msg.source == MessageSource.poke) {
            _showToast('对方拍了拍你', 2);
          }
        }
      } catch (e) {
        debugPrint('[ChatInteraction] 解析消息失败: $e');
      }
    });

    // 订阅好友隐私变更流
    _privacySub = _wsClient.onFriendPrivacyChange.listen((event) {
      if (event['user_id'] == friendId) {
        final status = event['status'] as String? ?? '';
        _isFriendPaused.value = status == 'paused';
        notifyListeners();

        final systemMsg = MessagePayload(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          type: MessageType.system,
          senderId: 'system',
          receiverId: friendId,
          contentKey: status == 'paused' ? 'sharing_paused' : 'sharing_resumed',
          source: MessageSource.privacy,
          timestamp: DateTime.now(),
        );
        _addMessage(systemMsg);
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      _isLoading = true;
      _loadError = false;
      notifyListeners();

      final response = await _dioClient.dio.get(
        '/messages/history',
        queryParameters: {'friend_id': friendId},
      );
      final List<dynamic> data = response.data['data'] ?? [];
      _messages = data
          .map((e) => MessagePayload.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _loadError = true;
      debugPrint('[ChatInteraction] 加载历史消息失败: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 重试加载历史消息
  Future<void> retryLoadHistory() async {
    await _loadHistory();
  }

  /// 发送快捷消息
  Future<void> sendQuickMessage(MessagePayload message) async {
    final tempMessage = message.copyWith(status: MessageStatus.sending);
    _addMessage(tempMessage);

    try {
      if (message.source == MessageSource.poke) {
        if (_isPokeLocked) return;
        _isPokeLocked = true;
        HapticFeedback.lightImpact();
        await _quickMessageService.sendPoke(friendId, senderId: currentUserId);
        Future.delayed(const Duration(seconds: 3), () {
          if (!_isDisposed) _isPokeLocked = false;
        });
      } else {
        await _quickMessageService.sendManualQuickMessage(
          receiverId: friendId,
          contentKey: message.contentKey,
          customText: message.customText,
          senderId: currentUserId,
        );
      }

      _updateMessageStatus(message.id, MessageStatus.success);
    } catch (e) {
      _updateMessageStatus(message.id, MessageStatus.failed);
      _showToast('好像没发出去，再试试？', 3);
    }
  }

  /// 重试发送失败消息
  Future<void> retrySendMessage(MessagePayload message) async {
    _messages.removeWhere((m) => m.id == message.id);
    notifyListeners();
    await sendQuickMessage(message);
  }

  /// 安全地显示 Toast（通过 GlobalKey 获取 context）
  void _showToast(String text, int seconds) {
    final context = messengerKey.currentContext;
    if (context != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          duration: Duration(seconds: seconds),
        ),
      );
    }
  }

  /// 更新位置数据，同步计算位置描述文本
  void _updateFriendLocationData(Map<String, dynamic> data) {
    final double? lat = double.tryParse(data['lat']?.toString() ?? '');
    final double? lng = double.tryParse(data['lng']?.toString() ?? '');

    String locationDesc = '📍 附近';
    if (lat != null && lng != null) {
      for (var fence in fences) {
        final double fLat = (fence['lat'] as num).toDouble();
        final double fLng = (fence['lng'] as num).toDouble();
        final double radius = (fence['radius'] as num?)?.toDouble() ?? 200;
        final double dist = haversineDistance(lat, lng, fLat, fLng);
        if (dist <= radius) {
          locationDesc = '📍 大概${fence['name']}';
          break;
        }
      }
    }

    _friendLocationData = {...data, 'locationDesc': locationDesc};
    notifyListeners();
  }

  void _addMessage(MessagePayload msg) {
    // 幂等：避免重复添加同一 id
    if (!_messages.any((m) => m.id == msg.id)) {
      _messages.add(msg);
      notifyListeners();
    }
  }

  void _updateMessageStatus(String id, MessageStatus status) {
    final index = _messages.indexWhere((m) => m.id == id);
    if (index != -1) {
      _messages[index] = _messages[index].copyWith(status: status);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _msgSub?.cancel();
    _privacySub?.cancel();
    _wsConnectedSub?.cancel();
    _wsDisconnectedSub?.cancel();
    _isFriendPaused.dispose();
    super.dispose();
  }
}
