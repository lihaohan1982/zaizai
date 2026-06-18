// lib/features/map/presentation/widgets/location_map.dart
// 高德地图 Polygon 围栏渲染 + 闪烁动画 + 隐私暂停遮罩

import 'dart:math' as math;
import 'dart:ui'; // ImageFilter

import 'package:flutter/material.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';

/// 使用高德地图 Polygon 渲染围栏，支持触发闪烁动画
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
    widget.privacyController.fuseStatusNotifier.removeListener(_statusListener);
    super.dispose();
  }

  /// 使用多边形近似绘制圆形围栏
  List<LatLng> _generateCirclePoints(
    LatLng center,
    double radius, [
    int points = 32,
  ]) {
    const double earthRadius = 6378137.0;
    return List.generate(points, (i) {
      final angle = 2 * math.pi * i / points;
      final dx = radius * math.cos(angle);
      final dy = radius * math.sin(angle);
      final dLat = (dy / earthRadius) * (180 / math.pi);
      final dLng = (dx / earthRadius) *
          (180 / math.pi) /
          math.cos(center.latitude * math.pi / 180);
      return LatLng(center.latitude + dLat, center.longitude + dLng);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 构建围栏多边形集合
    final polygonsSet = <Polygon>{};
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

      final opacity =
          isTriggered ? _blinkController.value * 0.5 : 0.2;

      polygonsSet.add(Polygon(
        points: points,
        strokeColor: isTriggered ? Colors.orange : Colors.blue,
        fillColor: isTriggered
            ? Colors.orange.withValues(alpha: opacity)
            : Colors.blue.withValues(alpha: opacity),
        strokeWidth: 2,
      ));
    }

    return Stack(
      children: [
        // 高德地图 + 围栏 Polygon
        AMapWidget(
          polygons: polygonsSet,
          initialCameraPosition: const CameraPosition(
            target: LatLng(39.909187, 116.397451), // 北京天安门
            zoom: 13,
          ),
        ),

        // 好友 Marker（暂停时隐藏）
        if (!_isPaused)
          const Positioned(
            top: 100,
            right: 100,
            child:
                Icon(Icons.account_circle, size: 40, color: Colors.red),
          ),

        // 自身位置 Marker（始终显示）
        const Positioned(
          bottom: 100,
          left: 100,
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
