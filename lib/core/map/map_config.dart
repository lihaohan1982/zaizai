// lib/core/map/map_config.dart
// GCJ-02 坐标转换 + 工业级高德瓦片图层工厂
// 原则：底图与点位同源（高德瓦片 GCJ-02 → 所有坐标必须转换）

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

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

  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _pi = 3.1415926535897932384626;

  /// 将 WGS-84 经纬度（GPS 原始坐标）转换为 GCJ-02（火星坐标）。
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
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(20.0 * x * _pi) + 20.0 * math.sin(40.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(x * _pi) + 40.0 * math.sin(x / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (150.0 * math.sin(x / 12.0 * _pi) + 300.0 * math.sin(x / 30.0 * _pi)) * 2.0 / 3.0;
    return ret;
  }
}

/// LatLng 扩展，提供更自然的转换调用
extension GcjExtension on LatLng {
  LatLng toGcj02() => GcjConverter.wgs84ToGcj02(latitude, longitude);
  LatLng toWgs84() => GcjConverter.gcj02ToWgs84(latitude, longitude);
}

// ============================================================================
// 2. 工业级地图图层工厂（含错误兜底瓦片）
// ============================================================================

/// 地图图层构建工厂，封装高德瓦片生产配置。
class MapLayerFactory {
  MapLayerFactory._();

  /// 高德瓦片 URL 模板（{key} 占位符由实际 API Key 替换）
  static const String _kAmapTileUrl =
      'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}&key={key}';

  /// 默认高德 API Key（仅用于紧急调试，生产环境请通过 EnvConfig.amapApiKey 配置）
  static const String _kFallbackAmapKey = '13bffa45068fd901bea739f49a414ed7';

  /// 256×256 浅灰色 PNG（base64 解码，正确的 PNG 数据）
  /// 瓦片加载失败时用 MemoryImage 显示灰色占位，不走网络加载。
  static final Uint8List _kGrayTileBytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAQAAAAEACAYAAABccqhmAAACX0lEQVR42u3UMQEAAAjDsPnXOC9gAAfk'
    'iIEeTdsBfooIYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAG'
    'ABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAQAGABgAYACAAQAGABgAYACAAQAG'
    'ABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACA'
    'AQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgA'
    'YACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAG'
    'ABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAA'
    'QAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgA'
    'YACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAYACAAQAGABgAcFmW9jWeBztrdAAAAABJR'
    'U5ErkJggg==',
  );

  /// 创建高德矢量瓦片图层（GCJ-02 坐标系，国内秒开）
  ///
  /// [amapApiKey] 高德 Web API Key，从 Amap 控制台获取。
  /// 若未传入，使用内置默认值（仅用于紧急调试）。
  static TileLayer createAmapLayer({
    String? amapApiKey,
    String urlTemplate = _kAmapTileUrl,
    void Function(TileImage tile, Object error, StackTrace? stackTrace)?
        onTileError,
  }) {
    final key = amapApiKey ?? _kFallbackAmapKey;
    final url = urlTemplate.replaceAll('{key}', key);
    void Function(TileImage, Object, StackTrace?) logger =
        onTileError ??
            (tile, err, st) {
              debugPrint(
                  '[MapLayer] ⚠️ 瓦片加载失败 tile=${tile.coordinates} error=$err');
            };

    return TileLayer(
      urlTemplate: url,
      // 瓦片层背景色（tiles 未加载完时显示灰色，避免透出父级背景）
      // 瓦片失败时显示灰色占位图（MemoryImage 不走网络，解码失败则静默跳过）
      errorImage: MemoryImage(_kGrayTileBytes),
      tileProvider: NetworkTileProvider(),
      errorTileCallback: logger,
      // none = 永远不移除失败 tiles（保留灰色占位，不透出橙色背景）
      evictErrorTileStrategy: EvictErrorTileStrategy.none,
    );
  }
}
