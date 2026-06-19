import 'dart:async';
import 'dart:math';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import 'location_scheduler.dart';

/// 定位策略引擎单例
/// 负责：速度→频率映射、位移阈值过滤、精度过滤、生命周期模式切换
class LocationStrategyEngine {
  LocationStrategyEngine._();

  static final instance = LocationStrategyEngine._();

  // ── 策略常量 ──────────────────────────────────────────
  static const double _stationaryThreshold = 0.5; // m/s
  static const double _walkingMax = 2.0; // m/s
  static const double _drivingMin = 12.0; // m/s

  static const double _minDisplacement = 50.0; // 米
  static const double _maxAccuracy = 100.0; // 米

  static const Map<String, Duration> _intervalMap = {
    'stationary': Duration(minutes: 5),
    'walking': Duration(minutes: 1),
    'driving': Duration(seconds: 20),
    'default': Duration(minutes: 2),
  };

  // ── 低功耗模式间隔（忽略位移触发）────────────────────
  static const Duration _lowPowerStationary = Duration(minutes: 10);
  static const Duration _lowPowerMoving = Duration(minutes: 5);

  // ── 状态 ──────────────────────────────────────────────
  bool _isRunning = false;
  bool _isBackground = false;
  LocationReportLevel _level = LocationReportLevel.full;

  StreamSubscription<Position>? _positionSub;
  Position? _lastPosition;
  DateTime? _lastReportTime;

  /// 持久化的位置更新回调，确保前后台切换时不丢失
  void Function(Position)? _onLocationUpdate;

  /// 当前上报级别（可供外部读取）
  LocationReportLevel get level => _level;

  // ── 公开方法 ──────────────────────────────────────────

  /// 启动引擎
  /// [onLocationUpdate] 采集到有效位置时的回调
  Future<void> start({
    required void Function(Position position) onLocationUpdate,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _onLocationUpdate = onLocationUpdate; // [M-4] 持久化回调

    // 首次获取当前上报级别
    _level = await LocationScheduler.getReportLevel();

    // 监听位置
    final settings = _getLocationSettings();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((pos) => _handlePosition(pos, _onLocationUpdate!));

    // 监听电量变化（仅 iOS/Android）
    if (!kIsWeb) {
      Battery().onBatteryStateChanged.listen((_) => _refreshLevel());
    }

    debugPrint('[LocationStrategyEngine] started, level=$_level');
  }

  /// App 切入后台
  void onAppBackground() {
    _isBackground = true;
    _restartIfNeeded();
    debugPrint('[LocationStrategyEngine] → background mode');
  }

  /// App 恢复前台
  void onAppForeground() {
    _isBackground = false;
    _restartIfNeeded();
    debugPrint('[LocationStrategyEngine] → foreground mode');
  }

  /// 停止引擎
  Future<void> stop() async {
    _isRunning = false;
    _onLocationUpdate = null; // [M-4] 清理回调引用
    await _positionSub?.cancel();
    _positionSub = null;
    debugPrint('[LocationStrategyEngine] stopped');
  }

  // ── 公开工具方法（兼容测试与外部调用）────────────────

  /// 判断当前位置是否需要上报（完整策略，兼容旧 API）
  Duration? shouldReport({
    required Position current,
    Position? last,
    DateTime? lastReportTime,
  }) {
    if (current.accuracy > _maxAccuracy) return null;
    final now = DateTime.now();
    if (last != null) {
      final distance = _haversineDistance(
        last.latitude, last.longitude, current.latitude, current.longitude);
      if (distance >= _minDisplacement) {
        return _getInterval(current.speed);
      }
    }
    if (lastReportTime == null) return _getInterval(current.speed);
    final elapsed = now.difference(lastReportTime);
    final required = _getInterval(current.speed);
    return elapsed >= required ? required : null;
  }

  /// 判断速度是否应唤醒定位（兼容旧 API）
  bool shouldWakeUp(double speed) {
    return speed > _stationaryThreshold;
  }

  // ── 内部逻辑 ──────────────────────────────────────────

  void _handlePosition(
    Position pos,
    void Function(Position) onUpdate,
  ) {
    if (pos.accuracy > _maxAccuracy) return;

    final now = DateTime.now();
    Duration? interval;

    if (_level == LocationReportLevel.suspend) {
      // SUSPEND：仅记录，不主动上报
      _lastPosition = pos;
      _lastReportTime = now;
      return;
    }

    if (_level == LocationReportLevel.lowPower) {
      // LOW_POWER：忽略位移触发，按固定间隔
      interval = _getLowPowerInterval(pos.speed);
    } else {
      // FULL：使用完整策略
      interval = _shouldReportFull(pos);
    }

    if (interval != null) {
      _lastPosition = pos;
      _lastReportTime = now;
      onUpdate(pos);
    }
  }

  Duration? _shouldReportFull(Position current) {
    if (_lastPosition != null) {
      final distance = _haversineDistance(
        _lastPosition!.latitude,
        _lastPosition!.longitude,
        current.latitude,
        current.longitude,
      );
      if (distance >= _minDisplacement) {
        return _getInterval(current.speed);
      }
    }
    if (_lastReportTime == null) return _getInterval(current.speed);
    final elapsed = DateTime.now().difference(_lastReportTime!);
    final required = _getInterval(current.speed);
    return elapsed >= required ? required : null;
  }

  Duration _getLowPowerInterval(double speed) {
    if (speed < _stationaryThreshold) return _lowPowerStationary;
    return _lowPowerMoving;
  }

  Duration _getInterval(double speed) {
    if (speed < _stationaryThreshold) return _intervalMap['stationary']!;
    if (speed <= _walkingMax) return _intervalMap['walking']!;
    if (speed >= _drivingMin) return _intervalMap['driving']!;
    return _intervalMap['default']!;
  }

  void _restartIfNeeded() async {
    if (!_isRunning || _onLocationUpdate == null) return;
    await _positionSub?.cancel();
    final settings = _getLocationSettings();
    _positionSub = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen((pos) => _handlePosition(pos, _onLocationUpdate!));
  }

  LocationSettings _getLocationSettings() {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return AppleSettings(
        accuracy: _level == LocationReportLevel.lowPower
            ? LocationAccuracy.low
            : LocationAccuracy.best,
        activityType: _isBackground
            ? ActivityType.automotiveNavigation
            : ActivityType.fitness,
        pauseLocationUpdatesAutomatically: _isBackground,
        showBackgroundLocationIndicator: true,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: _level == LocationReportLevel.lowPower ? 100 : 50,
        forceLocationManager: false,
        intervalDuration: _level == LocationReportLevel.lowPower
            ? const Duration(minutes: 5)
            : const Duration(minutes: 1),
      );
    }
    return const LocationSettings(accuracy: LocationAccuracy.best);
  }

  Future<void> _refreshLevel() async {
    _level = await LocationScheduler.getReportLevel();
    debugPrint('[LocationStrategyEngine] level refreshed: $_level');
    if (_isRunning) _restartIfNeeded();
  }

  // ── 工具 ──────────────────────────────────────────────
  double _haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double R = 6371000;
    final double dLat = _toRadians(lat2 - lat1);
    final double dLon = _toRadians(lon2 - lon1);
    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRadians(lat1)) *
            cos(_toRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRadians(double degree) => degree * pi / 180.0;
}
