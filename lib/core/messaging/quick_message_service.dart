// lib/core/messaging/quick_message_service.dart
import 'package:flutter/foundation.dart';
import 'package:location_chat_app/core/geofence/geofence_state_machine.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/core/network/websocket_service.dart';
import 'package:location_chat_app/core/messaging/offline_message_store.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import '../location/map_markers_notifier.dart';
import '../utils/input_validator.dart';

abstract class UuidProvider {
  String v4();
}

class RealUuidProvider implements UuidProvider {
  @override
  String v4() => DateTime.now().microsecondsSinceEpoch.toString();
}

abstract class TimeProvider {
  DateTime now();
}

class RealTimeProvider implements TimeProvider {
  @override
  DateTime now() => DateTime.now();
}

/// 供外部注入的 userId provider（避免直接依赖 AuthState）
typedef UserIdProvider = String Function();

class QuickMessageService {
  final PrivacyFuseController _privacyController;
  final GeofenceStateMachine _stateMachine;
  final WebSocketService _wsService;
  final OfflineMessageStore _offlineStore;
  final UuidProvider _uuidProvider;
  final TimeProvider _timeProvider;
  final String _partnerId;
  final MapMarkersNotifier? _markersNotifier;

  /// 单围栏状态跃迁防抖
  GeofenceStatus? _lastGeofenceStatus;
  /// 隐私状态重复推送防护
  PrivacyFuseStatus? _lastPrivacyStatus;

  final Map<String, VoidCallback> _listeners = {};

  /// 初始化
  QuickMessageService(
    this._privacyController,
    this._stateMachine,
    this._wsService,
    this._offlineStore,
    this._uuidProvider,
    this._timeProvider,
    this._partnerId, {
    MapMarkersNotifier? markersNotifier,
  }) : _markersNotifier = markersNotifier;

  void initialize() {
    _registerListener('privacy_status', _privacyController.fuseStatusNotifier, _onPrivacyStatusChanged);
    _registerListener('geofence_status', _stateMachine.statusNotifier, _onGeofenceStatusChanged);
  }

  void _registerListener(String key, ValueNotifier notifier, VoidCallback callback) {
    notifier.addListener(callback);
    _listeners[key] = callback;
  }

  /// 隐私状态变更：仅 paused -> normal 发送一次恢复通知
  void _onPrivacyStatusChanged() {
    final newStatus = _privacyController.fuseStatusNotifier.value;
    if (newStatus == _lastPrivacyStatus) return;

    String? contentKey;
    if (newStatus == PrivacyFuseStatus.paused) {
      contentKey = 'sharing_paused';
    } else if (newStatus == PrivacyFuseStatus.normal &&
        (_lastPrivacyStatus == PrivacyFuseStatus.paused || _lastPrivacyStatus == PrivacyFuseStatus.resuming)) {
      contentKey = 'sharing_resumed';
    }

    _lastPrivacyStatus = newStatus;
    if (contentKey == null) return;

    final payload = MessagePayload(
      id: _uuidProvider.v4(),
      type: MessageType.system,
      senderId: _partnerId, // 系统消息，senderId 为对方
      receiverId: _partnerId,
      contentKey: contentKey,
      source: MessageSource.privacy,
      timestamp: _timeProvider.now(),
    );
    _dispatchMessage(payload);
  }

  /// 围栏状态跃迁：基于单围栏实例的精准触发
  void _onGeofenceStatusChanged() {
    final newStatus = _stateMachine.statusNotifier.value;
    if (newStatus == _lastGeofenceStatus) return;

    final fenceId = _stateMachine.fenceId;
    _handleFenceTransition(fenceId, _lastGeofenceStatus, newStatus);
    _lastGeofenceStatus = newStatus;
  }

  void _handleFenceTransition(String fenceId, GeofenceStatus? oldStatus, GeofenceStatus newStatus) {
    String? contentKey;
    if (newStatus == GeofenceStatus.inside && oldStatus != GeofenceStatus.inside) {
      contentKey = _mapFenceToArrivalKey(fenceId);
    } else if (newStatus == GeofenceStatus.outside && oldStatus == GeofenceStatus.inside) {
      contentKey = _mapFenceToDepartureKey(fenceId);
    }

    if (contentKey == null) return;

    final payload = MessagePayload(
      id: _uuidProvider.v4(),
      type: MessageType.system,
      senderId: _partnerId,
      receiverId: _partnerId,
      fenceId: fenceId,
      contentKey: contentKey,
      source: MessageSource.geofence,
      timestamp: _timeProvider.now(),
    );
    _dispatchMessage(payload);
  }

  String _mapFenceToArrivalKey(String fenceId) {
    return fenceId == 'home' ? 'home_arrived' : 'office_arrived';
  }

  String _mapFenceToDepartureKey(String fenceId) {
    return fenceId == 'home' ? 'left_home' : 'left_office';
  }

  /// 处理收到的 quick message（围栏事件推送等）
  void handleQuickMessage(Map<String, dynamic> payload) {
    final source = payload['source'] as String?;
    final fenceId = payload['fence_id']?.toString() ?? payload['fenceId']?.toString();

    // 拦截 geofence 类型消息，触发地图闪烁动画
    if (source == 'geofence' && fenceId != null) {
      _markersNotifier?.triggerFenceAnimation(fenceId);
      debugPrint('[QuickMessageService] fence animation triggered: $fenceId');
    }
  }

  /// [新版] 发送手动快捷消息（可指定 receiverId / contentKey / customText）
  /// 发送快捷消息（直接透传完整 payload，不重建senderId）
  ///
  /// [修复] senderId 由调用方从 MessagePayload 中提取，不再用 _partnerId 替代。
  Future<void> sendQuickMessage(MessagePayload payload) async {
    await _dispatchMessage(payload);
  }

  /// 发送手动快捷消息
  Future<void> sendManualQuickMessage({
    required String receiverId,
    required String contentKey,
    String? customText,
    String? senderId,
  }) async {
    // [Phase0] 输入校验：customText 过滤 XSS + 长度限制
    String? validatedText = customText;
    if (customText != null && customText.isNotEmpty) {
      validatedText = InputValidator.validateMessage(customText);
      if (validatedText == null) {
        debugPrint('[QuickMessageService] customText 校验失败，消息未发送');
        return;
      }
    }

    final payload = MessagePayload(
      id: _uuidProvider.v4(),
      type: MessageType.quick,
      senderId: senderId ?? _partnerId,
      receiverId: receiverId,
      contentKey: contentKey,
      customText: validatedText,
      source: MessageSource.manual,
      timestamp: _timeProvider.now(),
    );
    await _dispatchMessage(payload);
  }

  /// 发送手动快捷消息（仅文本，receiverId 固定为 _partnerId）
  /// [DEPRECATED] 请直接使用 sendManualQuickMessage
  @Deprecated('Use sendManualQuickMessage instead')
  Future<void> sendManualQuickMessageOnly(String text) async {
    await sendManualQuickMessage(
      receiverId: _partnerId,
      contentKey: 'manual_quick',
      customText: text,
    );
  }

  /// 拍一拍节流器（防止高频点击）
  final _pokeThrottle = Throttle(duration: Duration(seconds: 3));

  /// 发送拍一拍（瞬时消息，不落盘）
  Future<void> sendPoke(String receiverId, {String? senderId}) async {
    // [Phase0] 节流：3 秒内重复点击忽略
    _pokeThrottle.call(() async {
      final payload = MessagePayload(
        id: _uuidProvider.v4(),
        type: MessageType.quick,
        senderId: senderId ?? _partnerId,
        receiverId: receiverId,
        contentKey: 'poke',
        source: MessageSource.poke,
        timestamp: _timeProvider.now(),
        transient: true,
      );
      // 拍一拍不落盘，直接发送
      if (_wsService.isConnected) {
        await _wsService.send('message_quick', payload.toJson());
      }
    });
  }

  /// 核心分发：在线推送 / 离线落盘 / 异常兜底
  Future<void> _dispatchMessage(MessagePayload payload) async {
    if (payload.transient) {
      // 瞬时消息不落盘
      if (_wsService.isConnected) {
        await _wsService.send('message_quick', payload.toJson());
      }
      return;
    }

    try {
      if (_wsService.isConnected) {
        await _wsService.send('message_quick', payload.toJson());
      } else {
        await _offlineStore.saveForRetry(payload);
      }
    } catch (e) {
      debugPrint('Dispatch failed, saving for retry: $e');
      try {
        await _offlineStore.saveForRetry(payload);
      } catch (storageError) {
        debugPrint('CRITICAL: Failed to save offline message: $storageError');
      }
    }
  }

  void dispose() {
    final privacyCallback = _listeners['privacy_status'];
    if (privacyCallback != null) _privacyController.fuseStatusNotifier.removeListener(privacyCallback);

    final geofenceCallback = _listeners['geofence_status'];
    if (geofenceCallback != null) _stateMachine.statusNotifier.removeListener(geofenceCallback);

    _listeners.clear();
    _lastGeofenceStatus = null;
    _lastPrivacyStatus = null;
  }
}
