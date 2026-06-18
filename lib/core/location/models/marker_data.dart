/// 位置时效性枚举
enum LocationFreshness {
  fresh,   // ≤ 2 分钟
  stale,   // 2-10 分钟
  expired, // > 10 分钟（数据过期）
  paused,  // 用户主动暂停共享
}

/// 地图标记数据模型
class MarkerData {
  final double lat;
  final double lng;
  final LocationFreshness freshness;
  final int? battery;
  final bool? charging;
  final int? ageMinutes;
  final bool isPaused;
  final String? pauseMessage;

  const MarkerData({
    required this.lat,
    required this.lng,
    required this.freshness,
    this.battery,
    this.charging,
    this.ageMinutes,
    this.isPaused = false,
    this.pauseMessage,
  });

  MarkerData copyWith({
    double? lat,
    double? lng,
    LocationFreshness? freshness,
    int? battery,
    bool? charging,
    int? ageMinutes,
    bool? isPaused,
    String? pauseMessage,
  }) {
    return MarkerData(
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      freshness: freshness ?? this.freshness,
      battery: battery ?? this.battery,
      charging: charging ?? this.charging,
      ageMinutes: ageMinutes ?? this.ageMinutes,
      isPaused: isPaused ?? this.isPaused,
      pauseMessage: pauseMessage ?? this.pauseMessage,
    );
  }
}
