// lib/core/map/map_config.dart
// GCJ-02 坐标转换 + 工业级高德瓦片图层工厂
// 原则：底图与点位同源（高德瓦片 GCJ-02 → 所有坐标必须转换）

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ============================================================================
// 1. GCJ-02 坐标转换工具（WGS-84 ↔ GCJ-02）
// ============================================================================

/// 火星坐标系（GCJ-02）转换工具，用于高德/腾讯地图底图。
/// 所有静态方法均为纯函数，线程安全。
class GcjConverter {
  GcjConverter._(); // 禁止实例化

  // 常量使用 static const 确保编译期内联
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _pi = 3.1415926535897932384626;

  /// 将 WGS-84 经纬度（GPS 原始坐标）转换为 GCJ-02（火星坐标）。
  /// 若坐标位于中国境外，则原样返回（不做偏移）。
  static LatLng wgs84ToGcj02(double lat, double lon) {
    if (_outOfChina(lat, lon)) return LatLng(lat, lon);

    final dLat = _transformLat(lon - 105.0, lat - 35.0);
    final dLon = _transformLon(lon - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * _pi;
    final magic = 1 - _ee * math.sin(radLat) * math.sin(radLat);
    final sqrtMagic = math.sqrt(magic);

    final deltaLat = (dLat * 180.0) /
        ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi);
    final deltaLon = (dLon * 180.0) /
        (_a / sqrtMagic * math.cos(radLat) * _pi);

    return LatLng(lat + deltaLat, lon + deltaLon);
  }

  /// 将 GCJ-02 转回 WGS-84（迭代逼近，精度 ~0.01m）
  static LatLng gcj02ToWgs84(double lat, double lon) {
    if (_outOfChina(lat, lon)) return LatLng(lat, lon);
    const int iterations = 10;
    double wgsLat = lat, wgsLon = lon;
    for (int i = 0; i < iterations; i++) {
      final gcj = wgs84ToGcj02(wgsLat, wgsLon);
      wgsLat -= gcj.latitude - lat;
      wgsLon -= gcj.longitude - lon;
    }
    return LatLng(wgsLat, wgsLon);
  }

  // ---------- 内部辅助 ----------
  static bool _outOfChina(double lat, double lon) {
    return lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 +
        2.0 * x +
        3.0 * y +
        0.2 * y * y +
        0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(20.0 * x * _pi) +
            20.0 * math.sin(40.0 * x * _pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * _pi) +
            40.0 * math.sin(y / 3.0 * _pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * _pi) +
            320 * math.sin(y * _pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLon(double x, double y) {
    var ret = 300.0 +
        x +
        2.0 * y +
        0.1 * x * x +
        0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(20.0 * x * _pi) +
            20.0 * math.sin(40.0 * x * _pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * _pi) +
            40.0 * math.sin(x / 3.0 * _pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * _pi) +
            300.0 * math.sin(x / 30.0 * _pi)) *
        2.0 /
        3.0;
    return ret;
  }
}

/// LatLng 扩展，提供更自然的转换调用
extension GcjExtension on LatLng {
  /// 将当前 WGS-84 坐标转为 GCJ-02
  LatLng toGcj02() => GcjConverter.wgs84ToGcj02(latitude, longitude);

  /// 将当前 GCJ-02 坐标转回 WGS-84
  LatLng toWgs84() => GcjConverter.gcj02ToWgs84(latitude, longitude);
}

// ============================================================================
// 2. 工业级地图图层工厂（含透明占位图、错误兜底、性能调优）
// ============================================================================

/// 地图图层构建工厂，封装高德瓦片生产配置。
class MapLayerFactory {
  MapLayerFactory._(); // 禁止实例化

  // 内嵌 1x1 透明 PNG 像素数据（避免外部资源依赖）
  static final Uint8List _kTransparentPng = Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
    0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
    0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
    0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
    0x42, 0x60, 0x82,
  ]);

  /// 创建高德矢量瓦片图层（GCJ-02 坐标系，国内秒开）
  static TileLayer createAmapLayer({
    String urlTemplate =
        'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
    String userAgentPackageName = 'com.locationchat.location_chat_app',
  }) {
    return TileLayer(
      urlTemplate: urlTemplate,
      userAgentPackageName: userAgentPackageName,
      tileProvider: NetworkTileProvider(),
      // ✅ 透明占位图，彻底规避红屏（无需 assets 声明）
      errorImage: MemoryImage(_kTransparentPng),
      // ✅ 错误回调：生产环境静默，开发时打印详细日志
      errorTileCallback: (tile, error, stackTrace) {
        if (kDebugMode) {
          debugPrint('⚠️ 地图瓦片加载失败: ${tile.coordinates} — $error');
        }
      },
    );
  }
}
