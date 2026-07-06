// lib/core/map/map_config.dart
// GCJ-02 坐标转换 + 高德瓦片工厂

import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

// ============================================================================
// 1. GCJ-02 坐标转换
// ============================================================================

class GcjConverter {
  GcjConverter._();
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;
  static const double _pi = 3.1415926535897932384626;

  static LatLng wgs84ToGcj02(double lat, double lon) {
    if (_outOfChina(lat, lon)) return LatLng(lat, lon);
    final dLat = _transformLat(lon - 105.0, lat - 35.0);
    final dLon = _transformLon(lon - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * _pi;
    final magic = 1 - _ee * math.sin(radLat) * math.sin(radLat);
    final sqrtMagic = math.sqrt(magic);
    return LatLng(
      lat + (dLat * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * _pi),
      lon + (dLon * 180.0) / (_a / sqrtMagic * math.cos(radLat) * _pi),
    );
  }

  static LatLng gcj02ToWgs84(double lat, double lon) {
    if (_outOfChina(lat, lon)) return LatLng(lat, lon);
    double wgsLat = lat, wgsLon = lon;
    for (int i = 0; i < 10; i++) {
      final gcj = wgs84ToGcj02(wgsLat, wgsLon);
      wgsLat -= gcj.latitude - lat;
      wgsLon -= gcj.longitude - lon;
    }
    return LatLng(wgsLat, wgsLon);
  }

  static bool _outOfChina(double lat, double lon) =>
      lon < 72.004 || lon > 137.8347 || lat < 0.8293 || lat > 55.8271;

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(20.0 * x * _pi) + 20.0 * math.sin(40.0 * x * _pi)) * 2.0 / 3.0;
    ret += (20.0 * math.sin(y * _pi) + 40.0 * math.sin(y / 3.0 * _pi)) * 2.0 / 3.0;
    ret += (160.0 * math.sin(y / 12.0 * _pi) + 320 * math.sin(y * _pi / 30.0)) * 2.0 / 3.0;
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

extension GcjExtension on LatLng {
  LatLng toGcj02() => GcjConverter.wgs84ToGcj02(latitude, longitude);
  LatLng toWgs84() => GcjConverter.gcj02ToWgs84(latitude, longitude);
}

// ============================================================================
// 2. 瓦片图层工厂
// ============================================================================

class MapLayerFactory {
  MapLayerFactory._();

  static const String _kAmapTileUrl =
      'https://webrd01.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}&key={key}';
  static const String _kFallbackAmapKey = '13bffa45068fd901bea739f49a414ed7';

  /// 256×256 浅灰色 PNG（Python 生成，564 字节）
  /// 从 hex 字符串运行时解析，无 base64Decode 崩溃风险。
  static final Uint8List _kGrayTileBytes = _parseHex(
    '89504e470d0a1a0a0000000d4948445200000100000001000802000000d3103f31000001fb4944415478daedd3310d00000cc3b0f2475658bd876136844849e1b1488001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c00060000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c8001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c000600030000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c000600038001c0006000300018000c00d700ad5d2329a09ca2610000000049454e44ae426082');

  /// 解析小写 hex 字符串为 Uint8List。
  static Uint8List _parseHex(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      result.add(int.parse(hex.substring(i, i + 2), radix: 16));
    }
    return Uint8List.fromList(result);
  }

  /// 构建高德瓦片图层。[amapApiKey] 优先使用提供的 Key，否则用内置 fallback。
  static TileLayer createAmapLayer({String? amapApiKey}) {
    final key = amapApiKey ?? _kFallbackAmapKey;
    final url = _kAmapTileUrl.replaceAll('{key}', key);
    return TileLayer(
      urlTemplate: url,
      userAgentPackageName: 'com.example.location_chat_app',
      // 瓦片失败时显示灰色 PNG 占位图（内嵌，无网络请求）
      errorImage: MemoryImage(_kGrayTileBytes),
      // 默认保留错误瓦片，防止透明区域露出橙色背景
    );
  }
}
