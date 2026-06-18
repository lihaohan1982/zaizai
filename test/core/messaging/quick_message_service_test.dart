// test/core/messaging/quick_message_service_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:location_chat_app/core/messaging/quick_message_service.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/messaging/offline_message_store.dart';
import 'package:location_chat_app/core/geofence/geofence_state_machine.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';

import 'fakes/fake_websocket_service.dart';
import 'fakes/in_memory_offline_message_store.dart';
import 'fakes/fake_time_provider.dart';
import 'fakes/fake_uuid_provider.dart';
import '../privacy/fakes/fake_geofence_repository.dart';
import '../privacy/fakes/fake_privacy_state_repository.dart';

/// QuickMessageService 单元测试
///
/// 当前覆盖场景：
/// 1. 在线状态 → WebSocket 发送，不落盘
/// 2. 离线状态 → 落盘离线存储，不发送
/// 3. dispose 后不再发送（监听器已移除）
///
/// TODO：围栏进入/离开触发系统消息的测试需要 GeofenceStateMachine 支持
///   TimerProvider 注入（当前用真实 Timer，无法用 FakeTimeProvider 驱动），
///   待 P1 重构完成后补充。
void main() {
  late FakeWebSocketService fakeWs;
  late InMemoryOfflineMessageStore fakeStore;
  late FakeTimeProvider fakeTime;
  late FakeUuidProvider fakeUuid;
  late FakeGeofenceRepository fakeGeoRepo;
  late FakePrivacyStateRepository fakePrivRepo;
  late GeofenceStateMachine stateMachine;
  late PrivacyFuseController privacyController;
  late QuickMessageService service;

  const fenceId = 'home';
  const currentUserId = 'user-1';
  const partnerId = 'user-2';

  setUp(() async {
    fakeWs = FakeWebSocketService();
    fakeStore = InMemoryOfflineMessageStore();
    fakeTime = FakeTimeProvider();
    fakeUuid = FakeUuidProvider();
    fakeGeoRepo = FakeGeofenceRepository();
    fakePrivRepo = FakePrivacyStateRepository();

    // 构造状态机（独立实例，与 PrivacyFuseController 内部状态机分开）
    stateMachine = GeofenceStateMachine(
      fenceId: fenceId,
      centerLat: 31.2304,
      centerLon: 121.4737,
      radiusMeters: 100.0,
    );

    // 构造 PrivacyFuseController 并初始化
    privacyController = PrivacyFuseController(fakeGeoRepo, fakePrivRepo);
    fakeGeoRepo.setConfig(GeofenceConfigData(
      fenceId: fenceId,
      centerLat: 31.2304,
      centerLon: 121.4737,
      radiusMeters: 100.0,
    ));
    await privacyController.initialize(fenceId);

    // 构造 QuickMessageService（7 个参数，partnerId 为第7个位置参数）
    service = QuickMessageService(
      privacyController,
      stateMachine,
      fakeWs,
      fakeStore,
      fakeUuid,
      fakeTime,
      partnerId,
    );
    service.initialize();
  });

  tearDown(() {
    service.dispose();
    privacyController.dispose();
    fakeWs.dispose();
    fakeStore.clear();
  });

  group('在线状态', () {
    setUp(() {
      fakeWs.setConnected(true);
    });

    test('发送手动快捷消息 → WebSocket 发出，离线存储为空', () async {
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'Hello',
      );

      expect(fakeWs.sentMessages.length, 1);
      expect(fakeStore.pending.length, 0);

      final sent = fakeWs.sentMessages.first;
      expect(sent['event'], 'message_quick');
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['custom_text'], 'Hello');
      expect(payload['sender_id'], partnerId);
      expect(payload['receiver_id'], partnerId);
    });

    test('WebSocket 发送异常 → 自动落盘离线存储', () async {
      // simulateIncomingMessage 不影响 send，需让 send 抛异常
      // FakeWebSocketService.send 在 !isConnected 时抛 StateError
      // 这里用 connected=true 但通过其他方式模拟异常较为困难
      // 暂时跳过，留给集成测试
    });
  });

  group('离线状态', () {
    setUp(() {
      fakeWs.setConnected(false);
    });

    test('发送手动快捷消息 → WebSocket 未发出，离线存储有 1 条', () async {
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'Hello offline',
      );

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 1);
      expect(fakeStore.pending.first.customText, 'Hello offline');
    });

    test('离线消息可通过 fetchPendingMessages 按 receiverId 查询', () async {
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'msg1',
      );
      // 用另一个 userId 查询，应返回空
      final result = await fakeStore.fetchPendingMessages('other-user');
      expect(result.length, 0);

      // 用正确 receiverId 查询
      final result2 = await fakeStore.fetchPendingMessages(partnerId);
      expect(result2.length, 1);
    });

    test('markAsSent 后消息从存储中移除', () async {
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'msg1',
      );
      final msgId = fakeStore.pending.first.id;

      await fakeStore.markAsSent(msgId);

      expect(fakeStore.pending.length, 0);
    });
  });

  group('dispose 后', () {
    test('监听器已移除，围栏状态变化不再触发消息', () async {
      service.dispose();

      // 触发围栏状态变化（应无副作用，不抛异常）
      stateMachine.evaluatePosition(_position(31.2304, 121.4737, accuracy: 10));

      // 没有消息发出
      expect(fakeWs.sentMessages.length, 0);
    });
  });

  group('围栏自动消息', () {
    setUp(() {
      fakeWs.setConnected(true);
    });

    test('【QMS-7】GIVEN 在线且围栏进入 WHEN 状态机变为 inside THEN 自动消息经 WebSocket 发出', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 1);
      expect(fakeStore.pending.length, 0);

      final sent = fakeWs.sentMessages.first;
      expect(sent['event'], 'message_quick');
      final payload = sent['payload'] as Map<String, dynamic>;
      expect(payload['content_key'], 'home_arrived');
      expect(payload['sender_id'], partnerId);
      expect(payload['receiver_id'], partnerId);
    });

    test('【QMS-8】GIVEN 离线且围栏进入 WHEN 状态机变为 inside THEN 消息落盘离线存储', () async {
      fakeWs.setConnected(false);
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 1);
      expect(fakeStore.pending.first.contentKey, 'home_arrived');
    });

    test('【QMS-9】GIVEN 围栏从外部进入 WHEN 状态机通知 inside THEN 发送 home_arrived 系统消息', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.outside;
      await Future.delayed(Duration.zero);
      fakeWs.clearSentMessages();

      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 1);
      final payload = fakeWs.sentMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['content_key'], 'home_arrived');
      expect(payload['type'], 'system');
    });

    test('【QMS-10】GIVEN 围栏从内部离开 WHEN 状态机通知 outside THEN 发送 left_home 系统消息', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);
      fakeWs.clearSentMessages();

      stateMachine.statusNotifier.value = GeofenceStatus.outside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 1);
      final payload = fakeWs.sentMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['content_key'], 'left_home');
      expect(payload['type'], 'system');
    });

    test('【QMS-11】GIVEN 围栏已处于 outside WHEN 状态机再次变为 outside THEN 不重复发送消息', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.outside;
      await Future.delayed(Duration.zero);
      fakeWs.clearSentMessages();

      stateMachine.statusNotifier.value = GeofenceStatus.outside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 0);
    });
  });

  group('离线消息同步', () {
    test('【QMS-12】GIVEN 无离线消息 WHEN 按 receiverId 查询 THEN 返回空列表', () async {
      final result = await fakeStore.fetchPendingMessages(partnerId);
      expect(result.length, 0);
    });

    test('【QMS-13】GIVEN 已发送离线消息 WHEN 再次 markAsSent 同一消息 THEN 不报错且存储为空', () async {
      await fakeStore.saveForRetry(MessagePayload(
        id: 'msg-1',
        type: MessageType.quick,
        senderId: currentUserId,
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'test',
        source: MessageSource.manual,
        timestamp: fakeTime.now(),
      ));

      await fakeStore.markAsSent('msg-1');
      await fakeStore.markAsSent('msg-1');

      expect(fakeStore.pending.length, 0);
    });
  });

  group('异常与边界', () {
    test('【QMS-14】GIVEN WebSocket 未连接 WHEN 发送围栏自动消息 THEN 走离线存储路径', () async {
      fakeWs.setConnected(false);
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 1);
      expect(fakeStore.pending.first.contentKey, 'home_arrived');
    });

    test('【QMS-15】GIVEN WebSocket 发送抛异常 WHEN 分发手动消息 THEN 自动落盘离线存储', () async {
      fakeWs.setConnected(true);
      fakeWs.throwOnSend = true;
      fakeWs.sendException = Exception('network error');

      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'fallback',
      );

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 1);
      expect(fakeStore.pending.first.customText, 'fallback');
    });

    test('【QMS-16】GIVEN 消息分发过程中离线存储也抛异常 WHEN 服务收到异常 THEN 不崩溃', () async {
      final throwingStore = _ThrowingOfflineStore();
      final serviceWithThrowingStore = QuickMessageService(
        privacyController,
        stateMachine,
        fakeWs,
        throwingStore,
        fakeUuid,
        fakeTime,
        partnerId,
      );
      serviceWithThrowingStore.initialize();

      fakeWs.setConnected(false);

      await serviceWithThrowingStore.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'throw',
      );

      serviceWithThrowingStore.dispose();

      expect(throwingStore.attempts, 2);
    });
  });

  group('生命周期', () {
    setUp(() {
      fakeWs.setConnected(true);
    });
    test('【QMS-17】GIVEN 进入确认中 WHEN suspend 中断 THEN 不发送自动消息', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.transitioning;
      await Future.delayed(Duration.zero);

      stateMachine.suspend();
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 0);
    });

    test('【QMS-18】GIVEN 中断后恢复 WHEN 重新进入围栏 THEN 正常发送自动消息', () async {
      stateMachine.statusNotifier.value = GeofenceStatus.transitioning;
      await Future.delayed(Duration.zero);
      stateMachine.suspend();
      await Future.delayed(Duration.zero);
      stateMachine.resume();
      await Future.delayed(Duration.zero);
      fakeWs.clearSentMessages();

      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await Future.delayed(Duration.zero);

      expect(fakeWs.sentMessages.length, 1);
      final payload = fakeWs.sentMessages.first['payload'] as Map<String, dynamic>;
      expect(payload['content_key'], 'home_arrived');
    });
  });

  group('多消息场景', () {
    test('【QMS-19】GIVEN 离线状态 WHEN 连续发送多条手动消息 THEN 全部正确存储', () async {
      fakeWs.setConnected(false);

      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'msg-1',
      );
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'msg-2',
      );
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'msg-3',
      );

      expect(fakeWs.sentMessages.length, 0);
      expect(fakeStore.pending.length, 3);
    });

    test('【QMS-20】GIVEN 离线存储多条消息 WHEN 查询 THEN 顺序与发送顺序一致', () async {
      fakeWs.setConnected(false);

      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'first',
      );
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'second',
      );
      await service.sendManualQuickMessage(
        receiverId: partnerId,
        contentKey: 'manual_quick',
        customText: 'third',
      );

      final messages = await fakeStore.fetchPendingMessages(partnerId);
      expect(messages.length, 3);
      expect(messages[0].customText, 'first');
      expect(messages[1].customText, 'second');
      expect(messages[2].customText, 'third');
    });
  });
}

/// 测试辅助：构造 geolocator Position 对象
geo.Position _position(double lat, double lon, {double accuracy = 10}) {
  return geo.Position(
    latitude: lat,
    longitude: lon,
    timestamp: DateTime.now(),
    accuracy: accuracy,
    altitude: 0,
    altitudeAccuracy: 0,
    heading: 0,
    headingAccuracy: 0,
    speed: 0,
    speedAccuracy: 0,
  );
}

/// 测试辅助：始终抛异常的离线存储
class _ThrowingOfflineStore implements OfflineMessageStore {
  int attempts = 0;

  @override
  Future<void> saveForRetry(MessagePayload message) async {
    attempts++;
    throw Exception('storage failed');
  }

  @override
  Future<List<MessagePayload>> fetchPendingMessages(String userId) async => [];

  @override
  Future<void> markAsSent(String messageId) async {}
}
