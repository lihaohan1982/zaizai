// lib/features/map/presentation/widgets/location_map.dart
// OpenStreetMap 围栏渲染 + 闪烁动画 + 隐私暂停遮罩
// 使用 flutter_map（无需 API Key）

import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';

/// 使用 OpenStreetMap 渲染围栏，支持触发闪烁动画
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

  // 地图控制器（用于后续动态更新）
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

  /// 使用多边形近似绘制圆形围栏
  ///
  /// 坐标转换：米 → 度
  ///   1°纬度 ≈ 111320m，1°经度 ≈ 111320m × cos(lat)
  ///   多边形顶点数 points 越多，圆越平滑（默认32点）
  List<LatLng> _generateCirclePoints(
    LatLng center,
    double radius, [
    int points = 32,
  ]) {
    final latDegPerMeter = 1.0 / 111320.0;
    final cosLat = math.cos(center.latitudeInRad);
    final lonDegPerMeter = latDegPerMeter / (cosLat == 0 ? 1e-10 : cosLat);

    return List.generate(points, (i) {
      final angle = 2 * math.pi * i / points;
      final dx = radius * math.cos(angle); // 米（东西方向）
      final dy = radius * math.sin(angle); // 米（南北方向）
      final dLatDeg = dy * latDegPerMeter;
      final dLonDeg = dx * lonDegPerMeter;
      return LatLng(
        center.latitudeInRad + dLatDeg,
        center.longitudeInRad + dLonDeg,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    // 构建围栏多边形集合
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
        // OpenStreetMap + 围栏 Polygon
        FlutterMap(
          mapController: _mapController,
          options: const MapOptions(
            initialCenter: LatLng(39.909187, 116.397451), // 北京天安门
            initialZoom: 13,
          ),
          children: [
            // OSM 德国镜像 + 显式 User-Agent Header
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.locationchat.location_chat_app',
              tileProvider: NetworkTileProvider(
                headers: {
                  'User-Agent':
                      'location_chat_app/1.0 (com.locationchat.location_chat_app)',
                },
              ),
            ),
            // 围栏多边形
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

        // 自身位置 Marker（始终显示）
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
