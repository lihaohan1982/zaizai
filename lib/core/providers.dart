// lib/core/providers.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import 'auth/auth_state.dart';
import 'auth/secure_token_storage.dart';
import 'auth/token_storage.dart';
import 'config/app_config.dart';
import 'geofence/geofence_state_machine.dart';
import 'network/dio_client.dart';
import 'location/map_markers_notifier.dart';
import 'messaging/offline_message_store_impl.dart';
import 'messaging/quick_message_service.dart';
import 'network/websocket_service.dart';
import 'network/ws_client.dart';
import 'privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'repositories/geofence_repository.dart';
import 'repositories/privacy_state_repository.dart';
import 'security/geo_encryption_service.dart';

// -------------------------------------------------------------------------
// Hive Box Providers
// -------------------------------------------------------------------------

/// Geofence 配置 Box（版本化，支持升级）
final geofenceBoxProvider = FutureProvider<Box<dynamic>>((ref) async {
  if (!Hive.isBoxOpen('geofence_configs')) {
    // [Phase0] Hive 版本化：通过 box.put('schema_version', 2) 手动管理
    await Hive.openBox<dynamic>('geofence_configs');
  }
  final box = Hive.box<dynamic>('geofence_configs');
  // 检查并升级 schema 版本
  final currentVersion = box.get('schema_version', defaultValue: 1) as int;
  if (currentVersion < 2) {
    // V1 → V2：新增加密字段，旧数据兼容读取
    debugPrint('[Hive] geofence_configs: $currentVersion → 2');
    // 标记需要迁移的数据
    for (final key in box.keys.whereType<String>()) {
      final data = box.get(key);
      if (data is Map && !data.containsKey('centerLatEnc')) {
        await box.put(key, {...data, 'needsMigration': true});
      }
    }
    await box.put('schema_version', 2);
  }
  return box;
});

/// 隐私状态 Box（版本化，支持升级）
final privacyBoxProvider = FutureProvider<Box<dynamic>>((ref) async {
  if (!Hive.isBoxOpen('privacy_state')) {
    await Hive.openBox<dynamic>('privacy_state');
  }
  final box = Hive.box<dynamic>('privacy_state');
  final currentVersion = box.get('schema_version', defaultValue: 1) as int;
  if (currentVersion < 1) {
    debugPrint('[Hive] privacy_state: $currentVersion → 1');
    await box.put('schema_version', 1);
  }
  return box;
});

// -------------------------------------------------------------------------
// Auth
// -------------------------------------------------------------------------

/// AuthState 单例
final authStateProvider = Provider<AuthState>((ref) {
  return AuthState();
});

/// Token 存储（生产环境使用 FlutterSecureStorage）
final tokenStorageProvider = Provider<TokenStorage>((ref) {
  return const SecureTokenStorage();
});

/// Dio 客户端（依赖注入 TokenStorage + 环境变量 baseUrl）
///
/// [onAuthFailure]：Token 刷新失败时回调（通常导航到登录页）
final dioClientProvider = Provider<DioClient>((ref) {
  return DioClient(
    baseUrl: AppConfig.apiBaseUrl,
    tokenStorage: ref.read(tokenStorageProvider),
    onAuthFailure: () {
      // Token 失效 → 强制登出，导航到登录页
      final auth = ref.read(authStateProvider);
      auth.logout();
      // TODO(phase0): 使用 GoRouter 或 Navigator 导航到登录页
      debugPrint('[Auth] Token 失效，需要重新登录');
    },
  );
});

// -------------------------------------------------------------------------
// Encryption
// -------------------------------------------------------------------------

final geoEncryptionServiceProvider = Provider<GeoEncryptionService>((ref) {
  return ProdGeoEncryptionService();
});

// -------------------------------------------------------------------------
// Repositories
// -------------------------------------------------------------------------

final geofenceRepositoryProvider = FutureProvider<GeofenceRepository>((ref) async {
  final box = await ref.watch(geofenceBoxProvider.future);
  final encryption = ref.watch(geoEncryptionServiceProvider);
  return LocalGeofenceRepository(box, encryption);
});

final privacyStateRepositoryProvider = FutureProvider<PrivacyStateRepository>((ref) async {
  final box = await ref.watch(privacyBoxProvider.future);
  return LocalPrivacyStateRepository(box);
});

// -------------------------------------------------------------------------
// Privacy & Geofence
// -------------------------------------------------------------------------

final privacyFuseControllerProvider = FutureProvider<PrivacyFuseController>((ref) async {
  final geofenceRepo = await ref.watch(geofenceRepositoryProvider.future);
  final privacyRepo = await ref.watch(privacyStateRepositoryProvider.future);
  final controller = PrivacyFuseController(geofenceRepo, privacyRepo);
  // 自动调用 initialize，否则 initStatusNotifier 永远停留在 loading
  await controller.initialize('home');
  return controller;
});

/// 围栏列表 Provider（供 BuddyStatusCard / ChatInteractionController 使用）
final fencesProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final jsonString = await rootBundle.loadString('assets/mock_fences.json');
  final List<dynamic> json = jsonDecode(jsonString);
  return json.cast<Map<String, dynamic>>();
});

// -------------------------------------------------------------------------
// 围栏事件历史 Provider（供 FenceEventHistoryPage 使用）
// -------------------------------------------------------------------------

/// 获取指定围栏的事件历史列表
///
/// 后端接口：GET /api/fences/:fenceId/events
/// 返回字段：[{"event_type": "enter"|"exit", "timestamp": "ISO8601", ...}]
final fenceEventsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, fenceId) async {
    // TODO: 替换为真实后端 API 调用
    // final dio = DioClient().dio;
    // final response = await dio.get('/api/fences/$fenceId/events');
    // return List<Map<String, dynamic>>.from(response.data);
    return [];
  },
);

// -------------------------------------------------------------------------
// ScaffoldMessenger Key（供 ChatInteractionController Toast 显示）
// -------------------------------------------------------------------------

final scaffoldMessengerKeyProvider = Provider<GlobalKey<ScaffoldMessengerState>>((ref) {
  return GlobalKey<ScaffoldMessengerState>();
});

// -------------------------------------------------------------------------
// Friend List
// -------------------------------------------------------------------------

/// 好友列表 Provider（P0-1：从 FastAPI /api/friends 真实 API 读取）
///
/// 字段归一化：API 返回 nickname → 转换为 name，供 SideDrawerFriendList 使用。
/// 定位服务字段（locationDesc / battery）后端暂无，填充为空占位。
final friendListProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final auth = ref.watch(authStateProvider);
  if (!auth.isLoggedIn) return [];

  final dioClient = ref.watch(dioClientProvider);

  try {
    final response = await dioClient.dio.get('/api/friends');
    final wrapper = response.data as Map<String, dynamic>;
    final code = wrapper['code'] as int?;
    if (code != 0) {
      debugPrint('[FriendList] API 返回错误 code=$code: ${wrapper['message']}');
      return [];
    }

    final List<dynamic> rawFriends = wrapper['data'] as List<dynamic>? ?? [];
    // 字段归一化：API → Widget 期望
    return rawFriends.map((f) {
      final Map<String, dynamic> friend = Map<String, dynamic>.from(f as Map);
      friend['name'] = friend['nickname'] ?? friend['phone'] ?? '未知';
      // 后端暂无实时位置数据，Widget 需要这些字段
      friend['locationDesc'] = friend['locationDesc'] ?? '';
      friend['battery'] = friend['battery'];
      return friend;
    }).toList();
  } catch (e, st) {
    debugPrint('[FriendList] 加载好友列表失败: $e\n$st');
    return [];
  }
});

// -------------------------------------------------------------------------
// WebSocket
// -------------------------------------------------------------------------

/// WsClient 单例（依赖 AuthState token，[H-2] 惰性读取）
final wsClientProvider = Provider<WsClient>((ref) {
  final auth = ref.watch(authStateProvider);
  final tokenStorage = ref.read(tokenStorageProvider);
  final client = WsClient(
    baseUrl: AppConfig.wsBaseUrl,
    tokenGetter: () => tokenStorage.readToken(), // [H-2] 每次重连动态读取最新 Token
    heartbeatInterval: const Duration(seconds: 30),
    pongTimeout: const Duration(seconds: 40),
  );
  if (auth.isLoggedIn) {
    client.connect();
  }
  return client;
});


// -------------------------------------------------------------------------
// ChatInteractionController（按好友隔离，family provider）
// -------------------------------------------------------------------------

/// 好友互动控制器 Provider（按 friendId 隔离）
///
/// 依赖 QuickMessageService（异步），故使用 FutureProvider.family
final chatInteractionControllerProvider =
    FutureProvider.family<ChatInteractionController, String>(
  (ref, friendId) async {
    final quickMessageService =
        await ref.watch(quickMessageServiceProvider(friendId).future);
    final wsClient = ref.watch(wsClientProvider);
    final authState = ref.watch(authStateProvider);
    final dioClient = ref.watch(dioClientProvider);
    final messengerKey = ref.watch(scaffoldMessengerKeyProvider);
    final fences = await ref.watch(fencesProvider.future);

    return ChatInteractionController(
      messengerKey: messengerKey,
      friendId: friendId,
      fences: fences,
      quickMessageService: quickMessageService,
      wsClient: wsClient,
      authState: authState,
      dioClient: dioClient,
    );
  },
);

// -------------------------------------------------------------------------
// QuickMessageService（按好友隔离，family provider）
// -------------------------------------------------------------------------

final quickMessageServiceProvider = FutureProvider.family<QuickMessageService, String>(
  (ref, friendId) async {
    final privacy = await ref.watch(privacyFuseControllerProvider.future);
    final wsClient = ref.watch(wsClientProvider);
    // encryption 不再传入 _buildPlaceholderStateMachine（已移除该参数）
    // 但保留 watch 以保持加密服务的生命周期
    // ignore: unused_local_variable
    final encryption = ref.watch(geoEncryptionServiceProvider);

    // 构造占位 StateMachine（围栏事件由后端推送触发，前端监听隐私联动）
    final stateMachine = _buildPlaceholderStateMachine(friendId);

    final offlineStore = InMemoryOfflineMessageStore();

    // MapMarkersNotifier 需要 WsClient 构造，延迟到此处创建
    final markers = MapMarkersNotifier(wsClient);

    final service = QuickMessageService(
      privacy,
      stateMachine,
      _WsServiceAdapter(wsClient),
      offlineStore,
      RealUuidProvider(),
      RealTimeProvider(),
      friendId,
      markersNotifier: markers,
    );
    service.initialize();
    return service;
  },
);

/// 构建占位 GeofenceStateMachine（使用默认坐标，围栏事件由后端推送）
GeofenceStateMachine _buildPlaceholderStateMachine(
  String fenceId,
) {
  // 默认围栏中心（北京），真实数据由后端推送更新
  const defaultLat = 39.9042;
  const defaultLon = 116.4074;

  return GeofenceStateMachine(
    fenceId: fenceId,
    centerLat: defaultLat,
    centerLon: defaultLon,
    radiusMeters: 200,
    onStatusChanged: (_, __) {},
  );
}

/// WsClient → WebSocketService 适配器
class _WsServiceAdapter implements WebSocketService {
  final WsClient _client;
  _WsServiceAdapter(this._client);

  @override
  bool get isConnected => _client.isConnected;

  @override
  Stream<Map<String, dynamic>> get onMessage => _client.onQuickMessage;

  // WebSocketService 接口实现（connect/disconnect/send 已在 WsClient 直接可用）
  @override
  Future<void> connect(String token) async => _client.connect();
  @override
  void disconnect() => _client.disconnect();
  @override
  Future<void> send(String event, Map<String, dynamic> payload) async =>
      _client.send({'type': event, ...payload});
}
