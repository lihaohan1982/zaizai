/// 测试辅助工具 — Fake 实现 & Provider overrides
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/auth/auth_state.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/messaging/quick_message_service.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/models/privacy_state.dart';
import 'package:location_chat_app/core/network/websocket_service.dart';
import 'package:location_chat_app/core/providers.dart';
import 'package:location_chat_app/core/repositories/geofence_repository.dart';
import 'package:location_chat_app/core/repositories/privacy_state_repository.dart';

// ─── TimeProvider fake ─────────────────────────────────────────────

class FakeTimeProvider implements TimeProvider {
  @override
  DateTime now() => DateTime(2026, 1, 15, 10, 30, 0);
}

// ─── UuidProvider fake ─────────────────────────────────────────────

class FakeUuidProvider implements UuidProvider {
  int _counter = 0;
  @override
  String v4() => 'fake-uuid-${_counter++}';
}

// ─── WebSocketService fake ─────────────────────────────────────────

class FakeWebSocketService implements WebSocketService {
  final _messageController = StreamController<Map<String, dynamic>>.broadcast();
  bool _connected = false;

  @override
  bool get isConnected => _connected;

  @override
  Stream<Map<String, dynamic>> get onMessage => _messageController.stream;

  @override
  Future<void> connect(String token) async {
    _connected = true;
  }

  @override
  void disconnect() {
    _connected = false;
  }

  @override
  Future<void> send(String event, Map<String, dynamic> payload) async {}

  void simulateIncoming(Map<String, dynamic> msg) {
    _messageController.add(msg);
  }

  void dispose() {
    _messageController.close();
  }
}

// ─── GeofenceRepository fake ───────────────────────────────────────

class FakeGeofenceRepository implements GeofenceRepository {
  GeofenceConfigData? configToReturn;
  bool shouldThrow = false;

  @override
  Future<GeofenceConfigData?> loadConfig(String fenceId) async {
    if (shouldThrow) throw Exception('Test error');
    return configToReturn;
  }

  @override
  Future<void> saveConfig(GeofenceConfigData config) async {}

  @override
  Future<void> deleteConfig(String fenceId) async {}
}

// ─── PrivacyStateRepository fake ────────────────────────────────────

class FakePrivacyStateRepository implements PrivacyStateRepository {
  PrivacyState storedState = const PrivacyState();

  @override
  Future<PrivacyState> loadState() async => storedState;

  @override
  Future<void> saveState(PrivacyState state) async {
    storedState = state;
  }
}

// ─── QuickMessageService factory ───────────────────────────────────

QuickMessageService buildQuickMessageService({
  required String friendId,
  required FakeWebSocketService wsService,
}) {
  // QuickMessageService needs WsClient (concrete class), so we skip
  // direct construction and return a stub for path tests that don't
  // exercise message sending.
  // For path A (login sidebar), we only need providers, not QMS directly.
  // For path E (ws reconnect), we construct it via the controller.
  throw UnimplementedError(
    'Use ChatInteractionController or provider overrides instead',
  );
}

// ─── Provider overrides for integration tests ─────────────────────

/// Override authStateProvider with a test instance that skips secure storage
final testAuthStateProvider = Provider<AuthState>((ref) {
  return _TestAuthState();
});

class _TestAuthState extends AuthState {
  @override
  String? get token => 'test-token';
  @override
  String? get currentUserId => 'user-1';
  @override
  String? get nickname => '测试用户';
  @override
  bool get isLoggedIn => true;
}

/// Override friendListProvider with static test data
final testFriendListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return [
    {'id': 'friend-1', 'nickname': '好友A', 'locationDesc': '北京市朝阳区', 'battery': 85},
    {'id': 'friend-2', 'nickname': '好友B', 'locationDesc': '', 'battery': null},
  ];
});

/// Override fenceEventsProvider
final testFenceEventsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, fenceId) async {
  return [
    {'event_type': 'enter', 'timestamp': '2026-01-15T10:00:00'},
    {'event_type': 'exit', 'timestamp': '2026-01-15T12:00:00'},
  ];
});
