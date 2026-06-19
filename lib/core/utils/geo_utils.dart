// lib/core/utils/geo_utils.dart
//
// 地理计算公共工具（消除 _haversine 重复实现）

import 'dart:math';

/// Haversine 公式计算两点间距离（米）
double haversineDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  const double R = 6371000; // 地球半径（米）
  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);
  final double a = _toRadians(lat1);
  final double b = _toRadians(lat2);
  final double sinDLat2 = sin(dLat / 2);
  final double sinDLon2 = sin(dLon / 2);
  final double value =
      sinDLat2 * sinDLat2 + cos(a) * cos(b) * sinDLon2 * sinDLon2;
  return R * 2 * atan2(sqrt(value), sqrt(1 - value));
}

double _toRadians(double degree) => degree * pi / 180.0;
