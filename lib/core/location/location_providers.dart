import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// 定位权限被拒绝的异常（用于 UI 区分错误类型）
class LocationPermissionDeniedException implements Exception {
  final bool permanently;
  const LocationPermissionDeniedException({this.permanently = false});

  @override
  String toString() => permanently
      ? '定位权限被永久拒绝，请在系统设置中开启'
      : '定位权限被拒绝';
}

/// 持续位置流
///
/// [修复 Android 15 小米死锁] 不在 StreamProvider 内部同步 await Geolocator 平台通道，
/// 改为直接订阅 GPS 流，权限/服务检查移到 LocationDemoPage 内部（带超时保护）。
///
/// 修复前：positionStreamProvider 内部 await locationServiceEnabledProvider.future
///         → Geolocator.isLocationServiceEnabled() 同步阻塞
///         → StreamProvider 生成器挂起 → LocationDemoPage.build() 卡死 → 白屏
///
/// 修复后：StreamProvider 直接 yield* Geolocator.getPositionStream()（无等待）
///         → 立即返回 AsyncLoading → build() 不阻塞 → 橙色地图页立即显示
final positionStreamProvider = StreamProvider<Position>((ref) async* {
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10,
    ),
  );
});

/// 定位 Demo 页面状态文案（综合服务、权限、位置流状态）
final locationDemoStatusProvider = Provider<String>((ref) {
  final positionAsync = ref.watch(positionStreamProvider);

  if (positionAsync.hasError) {
    final e = positionAsync.error;
    if (e is LocationPermissionDeniedException) {
      return e.permanently
          ? '❌ 定位权限被永久拒绝，请在系统设置中开启'
          : '❌ 定位权限被拒绝';
    }
    return '❌ 获取位置失败: $e';
  }

  if (positionAsync.hasValue) {
    return '✅ 位置持续更新中...';
  }

  return '✅ 权限已获取，正在获取位置...';
});
