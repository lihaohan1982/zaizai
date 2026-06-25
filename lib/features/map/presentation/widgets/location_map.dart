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
  final double currentLat;
  final double currentLng;

  const LocationMap({
    super.key,
    required this.fences,
    this.triggeredFenceId,
    required this.privacyController,
    required this.currentLat,
    required this.currentLng,
  });

  @override
  State<LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<LocationMap>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;
  late VoidCallback _statusListener;
  final MapController _mapController = MapController();
  // 追踪上一帧的中心坐标，避免每帧重复 move()
  double? _lastCenterLat;
  double? _lastCenterLng;

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
  void didUpdateWidget(LocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // GPS 坐标变化时移动地图中心（只移一次，避免卡顿）
    if (oldWidget.currentLat != widget.currentLat ||
        oldWidget.currentLng != widget.currentLng) {
      if (_lastCenterLat != widget.currentLat ||
          _lastCenterLng != widget.currentLng) {
        _lastCenterLat = widget.currentLat;
        _lastCenterLng = widget.currentLng;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final gcj = GcjConverter.wgs84ToGcj02(
                widget.currentLat, widget.currentLng);
            _mapController.move(gcj, _mapController.camera.zoom);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    _blinkController.dispose();
    _mapController.dispose();
    widget.privacyController.fuseStatusNotifier.removeListener(_statusListener);
    super.dispose();
  }

  List<LatLng> _generateCirclePoints(
    LatLng centerWgs84,
    double radius, [
    int points = 32,
  ]) {
    final center = GcjConverter.wgs84ToGcj02(
        centerWgs84.latitude, centerWgs84.longitude);
    const latDegPerMeter = 1.0 / 111320.0;
    final cosLat = math.cos(center.latitude * math.pi / 180.0);
    final lonDegPerMeter =
        latDegPerMeter / (cosLat.abs() < 1e-10 ? 1e-10 : cosLat);
    return List.generate(points, (i) {
      final angle = 2 * math.pi * i / points;
      final dx = radius * math.cos(angle);
      final dy = radius * math.sin(angle);
      return LatLng(
        center.latitude + dy * latDegPerMeter,
        center.longitude + dx * lonDegPerMeter,
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

    // GPS 当前位置（WGS-84 → GCJ-02）
    final currentPos = GcjConverter.wgs84ToGcj02(
        widget.currentLat, widget.currentLng);

    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: currentPos,
            initialZoom: 15,
          ),
          children: [
            MapLayerFactory.createAmapLayer(),
            PolygonLayer(polygons: polygons.toList()),
          ],
        ),
        if (!_isPaused)
          const Positioned(
            top: 100,
            right: 16,
            child: Icon(Icons.account_circle, size: 40, color: Colors.red),
          ),
        const Positioned(
          bottom: 100,
          left: 16,
          child: Icon(Icons.person_pin_circle, size: 50, color: Colors.blue),
        ),
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
