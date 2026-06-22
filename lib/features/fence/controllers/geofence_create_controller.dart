// lib/features/fence/controllers/geofence_create_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';

/// 围栏创建状态
class GeofenceCreateState {
  final bool isLoading;
  final bool isSuccess;
  final String? error;

  const GeofenceCreateState({
    this.isLoading = false,
    this.isSuccess = false,
    this.error,
  });

  GeofenceCreateState copyWith({
    bool? isLoading,
    bool? isSuccess,
    String? error,
  }) {
    return GeofenceCreateState(
      isLoading: isLoading ?? this.isLoading,
      isSuccess: isSuccess ?? this.isSuccess,
      error: error ?? this.error,
    );
  }
}

/// 围栏创建业务控制器
///
/// 调用后端 GET /api/geofences/create，防抖+状态管理。
/// 创建成功后刷新 fencesProvider 使地图自动更新。
class GeofenceCreateController extends StateNotifier<GeofenceCreateState> {
  final Ref _ref;

  GeofenceCreateController(this._ref) : super(const GeofenceCreateState());

  Future<void> createGeofence({
    required String name,
    required double lat,
    required double lng,
    required double radius,
  }) async {
    if (state.isLoading) return;
    if (name.trim().isEmpty) {
      state = state.copyWith(error: '围栏名称不能为空');
      return;
    }

    state = state.copyWith(isLoading: true, error: null);

    try {
      final dioClient = _ref.read(dioClientProvider);
      final response = await dioClient.dio.get(
        '/api/geofences/create',
        queryParameters: {
          'name': name.trim(),
          'lat': lat,
          'lng': lng,
          'radius': radius,
        },
      );
      final wrapper = response.data as Map<String, dynamic>;
      if (wrapper['code'] == 0) {
        debugPrint('[GeofenceCreate] 围栏 [$name] 创建成功');
        state = state.copyWith(isLoading: false, isSuccess: true);
        // 刷新围栏列表，地图自动重绘
        _ref.invalidate(fencesProvider);
      } else {
        state = state.copyWith(
          isLoading: false,
          error: wrapper['message']?.toString() ?? '创建失败',
        );
      }
    } catch (e) {
      debugPrint('[GeofenceCreate] 创建失败: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void reset() {
    state = const GeofenceCreateState();
  }
}

final geofenceCreateControllerProvider =
    StateNotifierProvider<GeofenceCreateController, GeofenceCreateState>(
  (ref) => GeofenceCreateController(ref),
);
