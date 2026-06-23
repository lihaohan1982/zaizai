
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

/// 系统定位服务是否启用
final locationServiceEnabledProvider = FutureProvider<bool>((ref) async {
  return Geolocator.isLocationServiceEnabled();
});

/// 当前定位权限状态（自动请求一次权限）
final locationPermissionProvider = FutureProvider<LocationPermission>((ref) async {
  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
  }
  return permission;
});

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
/// 使用 async* 正确等待依赖 Future 完成后再订阅 GPS 流，
/// 避免返回 Stream.empty() 导致 Provider 状态异常。
final positionStreamProvider = StreamProvider<Position>((ref) async* {
  // 正确方式：await 两个依赖 Future，确保它们完成后才进入 GPS 流
  final enabled = await ref.watch(locationServiceEnabledProvider.future);
  if (!enabled) {
    throw const LocationPermissionDeniedException();
  }

  final permission = await ref.watch(locationPermissionProvider.future);
  if (permission == LocationPermission.denied) {
    throw const LocationPermissionDeniedException();
  }
  if (permission == LocationPermission.deniedForever) {
    throw const LocationPermissionDeniedException(permanently: true);
  }

  // 权限和服务都已就绪，开始监听 GPS 位置流
  yield* Geolocator.getPositionStream(
    locationSettings: const LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 10, // 移动 10 米才更新，省电
    ),
  );
});

/// 定位 Demo 页面状态文案（综合服务、权限、位置流状态）
final locationDemoStatusProvider = Provider<String>((ref) {
  final enabledAsync = ref.watch(locationServiceEnabledProvider);
  final permissionAsync = ref.watch(locationPermissionProvider);
  final positionAsync = ref.watch(positionStreamProvider);

  if (enabledAsync.isLoading || permissionAsync.isLoading) {
    return '正在请求定位权限...';
  }

  if (enabledAsync.hasError) {
    return '❌ 无法检测定位服务状态: ${enabledAsync.error}';
  }

  final enabled = enabledAsync.valueOrNull ?? false;
  if (!enabled) {
    return '❌ 定位服务未启用，请在设置中开启';
  }

  if (permissionAsync.hasError) {
    return '❌ 权限检测失败: ${permissionAsync.error}';
  }

  final permission = permissionAsync.valueOrNull;
  if (permission == LocationPermission.denied) {
    return '❌ 定位权限被拒绝';
  }
  if (permission == LocationPermission.deniedForever) {
    return '❌ 定位权限被永久拒绝，请在系统设置中开启';
  }

  if (positionAsync.hasError) {
    return '❌ 获取位置失败: ${positionAsync.error}';
  }

  if (positionAsync.hasValue) {
    return '✅ 位置持续更新中...';
  }

  return '✅ 权限已获取，正在获取位置...';
});
