import 'dart:async';
import 'package:location_chat_app/core/utils/geo_utils.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

enum GeofenceStatus { outside, inside, transitioning }

class GeofenceConfig {
  final Duration enterConfirmationWindow;
  final Duration exitConfirmationWindow;
  final double fenceAccuracyThreshold;
  final double snapAccuracyThreshold;

  const GeofenceConfig({
    this.enterConfirmationWindow = const Duration(seconds: 120),
    this.exitConfirmationWindow = const Duration(seconds: 30),
    this.fenceAccuracyThreshold = 50.0,
    this.snapAccuracyThreshold = 50.0,
  });

  static const highway = GeofenceConfig(
    enterConfirmationWindow: Duration(seconds: 30),
    exitConfirmationWindow: Duration(seconds: 10),
    fenceAccuracyThreshold: 100.0,
    snapAccuracyThreshold: 100.0,
  );
}

abstract class TimeProvider {
  DateTime now();
  Timer createTimer(Duration duration, void Function() callback);
}

class SystemTimeProvider implements TimeProvider {
  @override
  DateTime now() => DateTime.now();

  @override
  Timer createTimer(Duration duration, void Function() callback) =>
      Timer(duration, callback);
}

class GeofenceStateMachine {
  final String fenceId;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;
  final TimeProvider _timeProvider;

  GeofenceConfig _config;
  GeofenceConfig get config => _config;

  GeofenceStatus _currentStatus = GeofenceStatus.outside;

  /// [V5.3.2 核心] 冷启动代数计数器
  /// [规划官修正③] 语义校准：仅在 resume() 重连时递增，首次冷启动不递增
  final ValueNotifier<int> coldStartGeneration = ValueNotifier(0);

  Timer? _enterTimer;
  // TODO(L-2): _exitTimer 从未启动，退出确认逻辑缺失（当前直接切换状态）
  Timer? _exitTimer;

  bool _isSuspended = false;
  bool _isColdStart = true;
  final List<bool> _coldStartSamples = [];
  DateTime? _coldStartFirstSampleTime;
  DateTime? _coldStartLastSampleTime;
  int _coldStartResetCount = 0;

  static const int _coldStartSampleSize = 3;
  static const Duration _coldStartTotalWindow = Duration(seconds: 60);
  static const Duration _coldStartMaxInterval = Duration(seconds: 30);
  static const int _maxColdStartResets = 3;

  final ValueNotifier<GeofenceStatus> statusNotifier =
      ValueNotifier(GeofenceStatus.outside);

  void Function(String fenceId, GeofenceStatus status)? onStatusChanged;

  GeofenceStateMachine({
    required this.fenceId,
    required this.centerLat,
    required this.centerLon,
    required this.radiusMeters,
    GeofenceConfig? config,
    TimeProvider? timeProvider,
    this.onStatusChanged,
  })  : _config = config ?? const GeofenceConfig(),
        _timeProvider = timeProvider ?? SystemTimeProvider();

  bool validatePositionAccuracy(Position position) {
    return position.accuracy <= _config.fenceAccuracyThreshold;
  }

  /// 精度校验并返回新 Position（用于 snap 场景）
  Position validateAndSnapPosition(Position current) {
    if (current.accuracy <= _config.snapAccuracyThreshold) {
      return Position(
        latitude: current.latitude,
        longitude: current.longitude,
        timestamp: current.timestamp,
        accuracy: current.accuracy,
        altitude: current.altitude,
        altitudeAccuracy: current.altitudeAccuracy,
        heading: current.heading,
        headingAccuracy: current.headingAccuracy,
        speed: current.speed,
        speedAccuracy: current.speedAccuracy,
        isMocked: current.isMocked,
      );
    }
    return current;
  }

  /// [规划官修正①] 热更新直接确认，即时响应
  void updateConfig(GeofenceConfig newConfig) {
    if (_currentStatus == GeofenceStatus.transitioning && _enterTimer != null) {
      _enterTimer!.cancel();
      _enterTimer = null;
      _currentStatus = GeofenceStatus.inside;
      statusNotifier.value = _currentStatus;
      onStatusChanged?.call(fenceId, _currentStatus);

      // 热更新强制确认进入，触发代数递增
      coldStartGeneration.value++;

      _cancelExitConfirmation();
    } else {
      _cancelEnterConfirmation();
      _cancelExitConfirmation();
    }
    _config = newConfig;
  }

  void suspend() {
    _isSuspended = true;
    _cancelEnterConfirmation();
    _cancelExitConfirmation();
    _resetColdStart();
    _coldStartResetCount = 0;
    _currentStatus = GeofenceStatus.outside;
    statusNotifier.value = _currentStatus;
    onStatusChanged?.call(fenceId, _currentStatus);
  }

  void resume() {
    _isSuspended = false;
    _isColdStart = true;
    _coldStartResetCount = 0;
    _resetColdStart();

    // [规划官修正③] 仅在重连时递增，代表一次新的"重连尝试"
    coldStartGeneration.value++;
  }

  void evaluatePosition(Position position) {
    if (_isSuspended) return;
    if (!validatePositionAccuracy(position)) return;

    final distance = haversineDistance(
      position.latitude, position.longitude, centerLat, centerLon,
    );
    final bool isCurrentlyInside = distance <= radiusMeters;

    if (_isColdStart) {
      final now = _timeProvider.now();
      _coldStartFirstSampleTime ??= now;

      final totalElapsed = now.difference(_coldStartFirstSampleTime!);
      final intervalElapsed = _coldStartLastSampleTime != null
          ? now.difference(_coldStartLastSampleTime!)
          : Duration.zero;

      if (totalElapsed > _coldStartTotalWindow || intervalElapsed > _coldStartMaxInterval) {
        _coldStartResetCount++;
        if (_coldStartResetCount >= _maxColdStartResets) {
          _isColdStart = false;
          _currentStatus = GeofenceStatus.outside;
          statusNotifier.value = _currentStatus;
          onStatusChanged?.call(fenceId, _currentStatus);
          // 仅清理样本，保留 _coldStartResetCount 基准；
          // 不调用 _resetColdStart()（会重置计数器）
          _coldStartSamples.clear();
          _coldStartFirstSampleTime = null;
          _coldStartLastSampleTime = null;
          return;
        }
        _resetColdStart();
      }

      _coldStartSamples.add(isCurrentlyInside);
      _coldStartLastSampleTime = now;

      if (_coldStartSamples.length >= _coldStartSampleSize) {
        _isColdStart = false;
        final insideVotes = _coldStartSamples.where((v) => v).length;
        _currentStatus = insideVotes > _coldStartSamples.length / 2
            ? GeofenceStatus.inside
            : GeofenceStatus.outside;
        statusNotifier.value = _currentStatus;
        onStatusChanged?.call(fenceId, _currentStatus);
        _coldStartResetCount = 0; // 冷启动正常结束，重置计数器
        _resetColdStart();
      }
      return;
    }

    // 正常状态跃迁
    if (isCurrentlyInside && _currentStatus == GeofenceStatus.outside) {
      _cancelExitConfirmation();
      _startEnterConfirmation();
    } else if (!isCurrentlyInside && _currentStatus == GeofenceStatus.inside) {
      _cancelEnterConfirmation();
      _currentStatus = GeofenceStatus.outside;
      statusNotifier.value = _currentStatus;
      onStatusChanged?.call(fenceId, _currentStatus);
    } else if (!isCurrentlyInside && _currentStatus == GeofenceStatus.transitioning) {
      // 进入过程中退出：立即生效（消除防抖），无需 30s 确认
      _cancelEnterConfirmation();
      _currentStatus = GeofenceStatus.outside;
      statusNotifier.value = _currentStatus;
      onStatusChanged?.call(fenceId, _currentStatus);
    } else if (isCurrentlyInside && _exitTimer != null) {
      _cancelExitConfirmation();
    }
  }

  void _resetColdStart() {
    _coldStartSamples.clear();
    _coldStartFirstSampleTime = null;
    _coldStartLastSampleTime = null;
    // 不重置 _coldStartResetCount：保留熔断基准
  }

  void _startEnterConfirmation() {
    if (_currentStatus == GeofenceStatus.transitioning && _enterTimer != null) return;
    _currentStatus = GeofenceStatus.transitioning;
    statusNotifier.value = _currentStatus;
    onStatusChanged?.call(fenceId, _currentStatus);
    _enterTimer?.cancel();
    _enterTimer = _timeProvider.createTimer(
      _config.enterConfirmationWindow,
      () => _triggerStatusChange(true),
    );
  }

  void _cancelEnterConfirmation() {
    _enterTimer?.cancel();
    _enterTimer = null;
    if (_currentStatus == GeofenceStatus.transitioning) {
      _currentStatus = GeofenceStatus.outside;
      statusNotifier.value = _currentStatus;
      onStatusChanged?.call(fenceId, _currentStatus);
    }
  }


  void _cancelExitConfirmation() {
    _exitTimer?.cancel();
    _exitTimer = null;
  }

  void _triggerStatusChange(bool isEntering) {
    _currentStatus = isEntering ? GeofenceStatus.inside : GeofenceStatus.outside;
    statusNotifier.value = _currentStatus;
    onStatusChanged?.call(fenceId, _currentStatus);
    _cancelEnterConfirmation();
    _cancelExitConfirmation();
  }

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _enterTimer?.cancel();
    _exitTimer?.cancel();
    statusNotifier.dispose();
    coldStartGeneration.dispose();
  }
}
