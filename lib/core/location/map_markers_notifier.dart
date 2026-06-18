import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../network/ws_client.dart';
import 'models/marker_data.dart';

/// 计算位置时效性（复用 WsClient 中的逻辑）
LocationFreshness calculateFreshness(int timestamp) {
  final age = DateTime.now().millisecondsSinceEpoch - timestamp;
  if (age <= 2 * 60 * 1000) return LocationFreshness.fresh;
  if (age <= 10 * 60 * 1000) return LocationFreshness.stale;
  return LocationFreshness.expired;
}

/// 计算位置年龄（分钟）
int calculateAgeMinutes(int timestamp) {
  final age = DateTime.now().millisecondsSinceEpoch - timestamp;
  return (age / 60000).floor();
}

/// 地图标记状态管理
class MapMarkersNotifier extends StateNotifier<Map<String, MarkerData>> {
  final WsClient _wsClient;
  StreamSubscription? _locationSub;
  StreamSubscription? _privacySub;
  StreamSubscription? _syncSub;
  StreamSubscription? _quickMsgSub;

  /// 当前被触发的围栏 ID（用于 UI 闪烁动画）
  String? triggeredFenceId;

  MapMarkersNotifier(this._wsClient) : super({}) {
    _init();
  }

  void _init() {
    // 订阅位置更新
    _locationSub = _wsClient.onLocationUpdate.listen(_handleLocationUpdate);
    
    // 订阅隐私状态变更
    _privacySub = _wsClient.onFriendPrivacyChange.listen(_handlePrivacyChange);
    
    // 订阅初始同步
    _syncSub = _wsClient.onInitialSync.listen(_handleInitialSync);

    // 订阅 quick message（含围栏事件推送）
    _quickMsgSub = _wsClient.onQuickMessage.listen(_handleQuickMessage);
  }

  /// 处理位置更新
  void _handleLocationUpdate(Map<String, dynamic> payload) {
    final userId = payload['userId'] as String?;
    if (userId == null) return;

    final timestamp = payload['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
    final freshness = calculateFreshness(timestamp);
    final ageMinutes = calculateAgeMinutes(timestamp);

    state = {
      ...state,
      userId: MarkerData(
        lat: (payload['lat'] as num?)?.toDouble() ?? 0,
        lng: (payload['lng'] as num?)?.toDouble() ?? 0,
        freshness: freshness,
        battery: (payload['battery'] as num?)?.toInt(),
        charging: payload['charging'] as bool?,
        ageMinutes: ageMinutes,
      ),
    };
  }

  /// 处理隐私状态变更
  void _handlePrivacyChange(Map<String, dynamic> payload) {
    final userId = payload['userId'] as String?;
    if (userId == null) return;

    final isPaused = payload['status'] == 'paused';
    final existing = state[userId];
    
    state = {
      ...state,
      userId: MarkerData(
        lat: existing?.lat ?? 0,
        lng: existing?.lng ?? 0,
        freshness: isPaused ? LocationFreshness.paused : (existing?.freshness ?? LocationFreshness.expired),
        battery: existing?.battery,
        charging: existing?.charging,
        ageMinutes: existing?.ageMinutes,
        isPaused: isPaused,
        pauseMessage: isPaused ? (payload['message'] as String? ?? '对方暂时关闭了位置共享') : null,
      ),
    };
  }

  /// 处理初始同步
  void _handleInitialSync(Map<String, dynamic> payload) {
    final Map<String, MarkerData> markers = {};
    
    // 1. 好友位置全量同步
    final friends = payload['friends'] as List? ?? [];
    for (final f in friends) {
      final friend = f as Map<String, dynamic>;
      final userId = friend['userId'] as String?;
      if (userId == null) continue;

      final timestamp = friend['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
      final freshness = calculateFreshness(timestamp);
      final ageMinutes = calculateAgeMinutes(timestamp);

      markers[userId] = MarkerData(
        lat: (friend['lat'] as num?)?.toDouble() ?? 0,
        lng: (friend['lng'] as num?)?.toDouble() ?? 0,
        freshness: freshness,
        battery: (friend['battery'] as num?)?.toInt(),
        charging: friend['charging'] as bool?,
        ageMinutes: ageMinutes,
      );
    }
    
    state = markers;
    
    // 2. 离线消息分发（通过 Stream 广播，由 QuickMessageService 处理）
    final pendingMessages = payload['pendingMessages'] as List? ?? [];
    for (final msg in pendingMessages) {
      final message = msg as Map<String, dynamic>;
      // 广播到 onQuickMessage stream（如果 WsClient 有的话）
      // 否则直接处理
      _handleQuickMessage(message);
    }
  }

  /// 处理 quick message（围栏事件、手动消息等）
  void _handleQuickMessage(Map<String, dynamic> payload) {
    final source = payload['source'] as String?;
    final fenceId = payload['fenceId']?.toString();

    if (source == 'geofence' && fenceId != null) {
      triggerFenceAnimation(fenceId);
    }
  }

  /// 触发围栏闪烁动画
  void triggerFenceAnimation(String fenceId) {
    triggeredFenceId = fenceId;
    // 通知 UI 重新构建
    state = Map<String, MarkerData>.from(state);
    // 3 秒后自动清除标记
    Future.delayed(const Duration(seconds: 3), () {
      if (triggeredFenceId == fenceId) {
        triggeredFenceId = null;
        state = Map<String, MarkerData>.from(state);
      }
    });
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _privacySub?.cancel();
    _syncSub?.cancel();
    _quickMsgSub?.cancel();
    super.dispose();
  }
}

