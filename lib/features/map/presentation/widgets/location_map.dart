// lib/features/map/presentation/widgets/location_map.dart
// 高德地图瓦片 + 围栏渲染 + 闪烁动画 + 隐私暂停遮罩
// 底图 GCJ-02 → 所有坐标统一转换

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location_chat_app/core/map/map_config.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';

/// 使用高德地图渲染围栏，支持触发闪烁动画
class LocationMap extends StatefulWidget {
  final List<Map<String, dynamic>> fences;
  final String? triggeredFenceId;
  final PrivacyFuseController privacyController;

  const LocationMap({
    super.key,
    required this.fences,
    this.triggeredFenceId,
    required this.privacyController,
  });

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late VoidCallback _statusListener;
  final MapController _mapController = MapController();

  bool get _isPaused =>
      widget.privacyController.fuseStatusNotifier.value ==
      PrivacyFuseStatus.paused;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    );
    if (widget.triggeredFenceId != null) {
      _blinkController.repeat(reverse: true);
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _blinkController.stop();
      });
    }
    _statusListener = () {
      if (mounted) setState(() {});
    };
    widget.privacyController.fuseStatusNotifier.addListener(_statusListener);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _mapController.dispose();
    widget.privacyController.fuseStatusNotifier.removeListener(_statusListener);
    super.dispose();
  }

  /// 将围栏坐标从 WGS-84 转换为 GCJ-02（底图同源）
  List<LatLng> _generateCirclePoints(
    LatLng centerWgs84,
    double radius, [
    int points = 32,
  ]) {
    // 底图是 GCJ-02，先将圆心从 WGS-84 转换到 GCJ-02
    final center = GcjConverter.wgs84ToGcj02(
        centerWgs84.latitude, centerWgs84.longitude);

    const latDegPerMeter = 1.0 / 111320.0;
    final cosLat = math.cos(center.latitude * math.pi / 180.0);
    final lonDegPerMeter = latDegPerMeter /
        (cosLat.abs() < 1e-10 ? 1e-10 : cosLat);

    return List.generate(points, (i) {
      final angle = 2 * math.pi * i / points;
      final dx = radius * math.cos(angle);
      final dy = radius * math.sin(angle);
      final dLatDeg = dy * latDegPerMeter;
      final dLonDeg = dx * lonDegPerMeter;
      return LatLng(
        center.latitude + dLatDeg,
        center.longitude + dLonDeg,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final polygons = <Polygon>{};
    for (final fence in widget.fences) {
      final isTriggered =
          widget.triggeredFenceId == fence['id'].toString();
      final points = _generateCirclePoints(
        LatLng(
          (fence['lat'] as num).toDouble(),
          (fence['lng'] as num).toDouble(),
        ),
        (fence['radius'] as num).toDouble(),
      );

      final opacity = isTriggered ? _blinkController.value * 0.5 : 0.2;

      polygons.add(Polygon(
        points: points,
        color: isTriggered
            ? Colors.orange.withValues(alpha: opacity)
            : Colors.blue.withValues(alpha: opacity),
        borderColor: isTriggered ? Colors.orange : Colors.blue,
        borderStrokeWidth: 2,
      ));
    }

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            // 底图 GCJ-02，初始中心点也需转换
            initialCenter:
                GcjConverter.wgs84ToGcj02(39.909187, 116.397451),
            initialZoom: 13,
          ),
          children: [
            // 工业级高德瓦片（含透明占位 + 错误兜底）
            MapLayerFactory.createAmapLayer(),

            // 围栏多边形（坐标已转换为 GCJ-02）
            PolygonLayer(polygons: polygons.toList()),
          ],
        ),

        // 好友 Marker（暂停时隐藏）
        if (!_isPaused)
          const Positioned(
            top: 100,
            right: 16,
            child: Icon(Icons.account_circle, size: 40, color: Colors.red),
          ),

        // 自身位置 Marker（始终显示，坐标需转换为 GCJ-02）
        // 注意：此 Widget 的坐标由上层调用方转换后传入
        const Positioned(
          bottom: 100,
          left: 16,
          child: Icon(Icons.person_pin_circle,
              size: 50, color: Colors.blue),
        ),

        // 暂停状态下叠加高斯模糊遮罩
        if (_isPaused)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                color: Colors.black.withValues(alpha: 0.1),
              ),
            ),
          ),
      ],
    );
  }
}
