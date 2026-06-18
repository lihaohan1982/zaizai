import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/geofence/geofence_state_machine.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/models/privacy_state.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/core/repositories/geofence_repository.dart';
import 'package:location_chat_app/core/repositories/privacy_state_repository.dart';
import 'package:location_chat_app/features/map/presentation/widgets/geofence_status_indicator.dart';

/// Fake GeofenceRepository（内存实现）
class FakeGeofenceRepository implements GeofenceRepository {
  GeofenceConfigData? _config;

  @override
  Future<void> saveConfig(GeofenceConfigData config) async => _config = config;

  @override
  Future<GeofenceConfigData?> loadConfig(String fenceId) async => _config;

  @override
  Future<void> deleteConfig(String fenceId) async => _config = null;
}

/// Fake PrivacyStateRepository（内存实现）
class FakePrivacyStateRepository implements PrivacyStateRepository {
  PrivacyState _state = const PrivacyState();
  final List<PrivacyState> savedStates = [];

  @override
  Future<void> saveState(PrivacyState state) async {
    _state = state;
    savedStates.add(state);
  }

  @override
  Future<PrivacyState> loadState() async => _state;
}

/// GeofenceStatusIndicator 单元测试
///
/// 验证五种状态的 UI 展示和监听器生命周期。
void main() {
  group('GeofenceStatusIndicator', () {
    late FakeGeofenceRepository geoRepo;
    late FakePrivacyStateRepository privRepo;
    late PrivacyFuseController controller;
    late GeofenceStateMachine stateMachine;

    setUp(() async {
      geoRepo = FakeGeofenceRepository();
      privRepo = FakePrivacyStateRepository();
      controller = PrivacyFuseController(geoRepo, privRepo);

      stateMachine = GeofenceStateMachine(
        fenceId: 'test',
        centerLat: 31.2304,
        centerLon: 121.4737,
        radiusMeters: 100,
        config: GeofenceConfig(),
      );
    });

    tearDown(() {
      stateMachine.dispose();
      controller.dispose();
    });

    testWidgets('PENDING-1: paused 状态 → 灰色圆点 + "共享已暂停"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      // 设置 paused 状态
      controller.fuseStatusNotifier.value = PrivacyFuseStatus.paused;
      await tester.pump();

      expect(find.text('共享已暂停'), findsOneWidget);
    });

    testWidgets('PENDING-2: resuming 状态 → 灰色圆点 + "正在恢复..." 脉冲动画',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      // 设置 resuming 状态
      controller.fuseStatusNotifier.value = PrivacyFuseStatus.resuming;
      await tester.pump();

      expect(find.text('正在恢复...'), findsOneWidget);
    });

    testWidgets('PENDING-3: inside 状态 → 绿色圆点 + "安全区域内"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      // 默认状态是 outside，需要触发 inside
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      await tester.pump();

      expect(find.text('安全区域内'), findsOneWidget);
    });

    testWidgets('PENDING-4: transitioning 状态 → 橙色圆点 + "确认中..."',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      stateMachine.statusNotifier.value = GeofenceStatus.transitioning;
      await tester.pump();

      expect(find.text('确认中...'), findsOneWidget);
    });

    testWidgets('PENDING-5: outside 状态 → 红色圆点 + "区域外"',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      // 默认就是 outside
      await tester.pump();

      expect(find.text('区域外'), findsOneWidget);
    });

    testWidgets('PENDING-6: stateMachine 为 null 时不崩溃',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: null,
              controller: controller,
            ),
          ),
        ),
      );

      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('PENDING-7: dispose 时监听器被移除（不崩溃）',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: GeofenceStatusIndicator(
              stateMachine: stateMachine,
              controller: controller,
            ),
          ),
        ),
      );

      // 移除组件（dispose）
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Text('done')),
      ));

      // 修改 notifier（验证监听器已被移除，不抛异常）
      stateMachine.statusNotifier.value = GeofenceStatus.inside;
      controller.fuseStatusNotifier.value = PrivacyFuseStatus.paused;

      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}
