import 'dart:async';
import 'dart:io';

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../background/android_background_service.dart';
import '../background/ios_background_service.dart';
import 'location_repository.dart';
import 'location_strategy.dart';

/// 位置服务 - P2 统一入口：后台保活 + 策略引擎 + 上报
class LocationService {
  final LocationRepository _repository;
  final Battery _battery = Battery();

  StreamSubscription<BatteryState>? _batterySubscription;

  LocationService({required LocationRepository repository})
      : _repository = repository;

  /// 启动位置服务（P2 统一入口）
  Future<void> start() async {
    // 1. 监听电池状态变化（驱动引擎内部 level 刷新）
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      debugPrint('[LocationService] battery state changed: $state');
      // 引擎内部会自动刷新 level，无需此处手动触发
    });

    // 2. 根据平台初始化后台保活
    if (Platform.isIOS) {
      await IOSBackgroundService.init();
    } else if (Platform.isAndroid) {
      await AndroidBackgroundService.startForegroundService();
      await AndroidBackgroundService.initWorkManager();
    }

    // 3. 启动 LocationStrategyEngine（统一采集入口）
    await LocationStrategyEngine.instance.start(
      onLocationUpdate: _onPositionUpdate,
    );
  }

  /// 处理位置更新（由引擎回调）
  Future<void> _onPositionUpdate(Position position) async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;

      await _repository.reportLocation(
        lat: position.latitude,
        lng: position.longitude,
        accuracy: position.accuracy,
        battery: level,
        charging: state == BatteryState.charging,
      );

      debugPrint(
          '[LocationService] reported: (${position.latitude}, ${position.longitude})');
    } catch (e) {
      debugPrint('[LocationService] report failed: $e');
    }
  }

  /// 停止位置服务
  Future<void> stop() async {
    await _batterySubscription?.cancel();
    await LocationStrategyEngine.instance.stop();
  }

  /// dispose（提供给 Provider 使用）
  Future<void> dispose() async {
    await stop();
  }
}

/// Provider: 提供 LocationService 单例
final locationServiceProvider = FutureProvider<LocationService>((ref) async {
  final repository = ref.read(locationRepositoryProvider);

  final service = LocationService(repository: repository);
  await service.start();

  ref.onDispose(() async {
    await service.stop();
  });

  return service;
});
