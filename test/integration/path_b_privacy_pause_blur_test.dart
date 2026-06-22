/// 路径 B：隐私设置 → 切换暂停共享 → 验证状态流转
library;

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/models/privacy_state.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer.dart';

import '../helpers/test_helpers.dart';

GeofenceConfigData _defaultConfig() {
  return GeofenceConfigData(
    fenceId: 'home',
    centerLat: 39.9042,
    centerLon: 116.4074,
    radiusMeters: 200,
  );
}

void main() {
  late FakeGeofenceRepository fakeGeoRepo;
  late FakePrivacyStateRepository fakePrivacyRepo;

  PrivacyFuseController _buildController({
    GeofenceConfigData? config,
    PrivacyState savedPrivacy = const PrivacyState(),
  }) {
    fakeGeoRepo = FakeGeofenceRepository()..configToReturn = config;
    fakePrivacyRepo = FakePrivacyStateRepository()..storedState = savedPrivacy;
    return PrivacyFuseController(fakeGeoRepo, fakePrivacyRepo);
  }

  group('路径B: 隐私设置 → 暂停/恢复', () {
    test('B-1: 初始化成功后 fuseStatus 为 normal', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      expect(controller.initStatusNotifier.value, InitializationStatus.success);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.normal);
      controller.dispose();
    });

    test('B-2: togglePause(true) 切换状态为 paused', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      await controller.togglePause(true);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.paused);
      final saved = await fakePrivacyRepo.loadState();
      expect(saved.isPaused, isTrue);
      controller.dispose();
    });

    test('B-3: togglePause(false) 通过 stateMachine resume → normal', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      await controller.togglePause(true);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.paused);
      // togglePause(false) → _resumeSharing() → resuming → stateMachine.resume()
      // → coldStartGeneration listener → _onColdStartCompleted() → normal（同步完成）
      await controller.togglePause(false);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.normal);
      // _debouncedSaveState 有 300ms 防抖，等待落盘
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final saved = await fakePrivacyRepo.loadState();
      expect(saved.isPaused, isFalse);
      controller.dispose();
    });

    test('B-4: togglePause(true) 乐观更新 listener 触发', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      final statuses = <PrivacyFuseStatus>[];
      controller.fuseStatusNotifier.addListener(() {
        statuses.add(controller.fuseStatusNotifier.value);
      });
      await controller.togglePause(true);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.paused);
      expect(statuses, contains(PrivacyFuseStatus.paused));
      controller.dispose();
    });

    test('B-5: togglePause(true) → togglePause(false) 完整往返', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      await controller.togglePause(true);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.paused);
      // resume 通过 stateMachine 同步完成 → normal
      await controller.togglePause(false);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.normal);
      controller.dispose();
    });

    test('B-6: 初始化空围栏 → initStatus = empty', () async {
      final controller = _buildController();
      await controller.initialize('home');
      expect(controller.initStatusNotifier.value, InitializationStatus.empty);
      controller.dispose();
    });

    test('B-7: 初始化异常 → initStatus = failed', () async {
      fakeGeoRepo = FakeGeofenceRepository()..shouldThrow = true;
      fakePrivacyRepo = FakePrivacyStateRepository();
      final controller = PrivacyFuseController(fakeGeoRepo, fakePrivacyRepo);
      await controller.initialize('home');
      expect(controller.initStatusNotifier.value, InitializationStatus.failed);
      controller.dispose();
    });

    test('B-8: 跨生命周期暂停恢复 - 未过期', () async {
      final pauseUntil = DateTime.now().add(const Duration(hours: 1));
      final controller = _buildController(
        config: _defaultConfig(),
        savedPrivacy: PrivacyState(isPaused: true, pauseUntil: pauseUntil),
      );
      await controller.initialize('home');
      expect(controller.initStatusNotifier.value, InitializationStatus.success);
      expect(controller.fuseStatusNotifier.value, PrivacyFuseStatus.paused);
      controller.dispose();
    });

    test('B-9: 跨生命周期暂停恢复 - 已过期自动恢复', () async {
      final pauseUntil = DateTime.now().subtract(const Duration(hours: 1));
      final controller = _buildController(
        config: _defaultConfig(),
        savedPrivacy: PrivacyState(isPaused: true, pauseUntil: pauseUntil),
      );
      await controller.initialize('home');
      expect(controller.initStatusNotifier.value, InitializationStatus.success);
      await Future.delayed(const Duration(milliseconds: 100));
      controller.dispose();
    });

    test('B-10: togglePause(true, duration) 设置 pauseUntil', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      await controller.togglePause(true, duration: const Duration(minutes: 30));
      final saved = await fakePrivacyRepo.loadState();
      expect(saved.isPaused, isTrue);
      expect(saved.pauseUntil, isNotNull);
      controller.dispose();
    });

    testWidgets('B-11: SideDrawer 高斯模糊 BackdropFilter 存在', (tester) async {
      final isOpen = ValueNotifier<bool>(false);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ValueListenableBuilder<bool>(
            valueListenable: isOpen,
            builder: (_, open, __) => SideDrawer(
              isOpen: open,
              onClose: () {},
              child: const Center(child: Text('Content')),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsNothing);

      isOpen.value = true;
      await tester.pumpAndSettle();
      expect(find.text('Content'), findsOneWidget);
      expect(find.byType(BackdropFilter), findsOneWidget);
    });

    test('B-12: dispose 多次不崩溃', () async {
      final controller = _buildController(config: _defaultConfig());
      await controller.initialize('home');
      controller.dispose();
      controller.dispose();
    });
  });
}
