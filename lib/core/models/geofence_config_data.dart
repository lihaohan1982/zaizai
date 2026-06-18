/// 纯围栏配置（静态数据，相对不常变动）
class GeofenceConfigData {
  final String fenceId;
  final double centerLat;
  final double centerLon;
  final double radiusMeters;

  final Duration enterConfirmationWindow;
  final Duration exitConfirmationWindow;
  final double fenceAccuracyThreshold;
  final double snapAccuracyThreshold;

  const GeofenceConfigData({
    required this.fenceId,
    required this.centerLat,
    required this.centerLon,
    required this.radiusMeters,
    this.enterConfirmationWindow = const Duration(seconds: 120),
    this.exitConfirmationWindow = const Duration(seconds: 30),
    this.fenceAccuracyThreshold = 50.0,
    this.snapAccuracyThreshold = 50.0,
  });

  Map<String, dynamic> toHiveMap() => {
        'fenceId': fenceId,
        'centerLat': centerLat,
        'centerLon': centerLon,
        'radiusMeters': radiusMeters,
        'enterWindowSec': enterConfirmationWindow.inSeconds,
        'exitWindowSec': exitConfirmationWindow.inSeconds,
        'fenceAccuracy': fenceAccuracyThreshold,
        'snapAccuracy': snapAccuracyThreshold,
      };

  factory GeofenceConfigData.fromHiveMap(Map<dynamic, dynamic> map) {
    return GeofenceConfigData(
      fenceId: map['fenceId'],
      centerLat: map['centerLat'],
      centerLon: map['centerLon'],
      radiusMeters: map['radiusMeters'],
      enterConfirmationWindow: Duration(seconds: map['enterWindowSec']),
      exitConfirmationWindow: Duration(seconds: map['exitWindowSec']),
      fenceAccuracyThreshold: map['fenceAccuracy'],
      snapAccuracyThreshold: map['snapAccuracy'],
    );
  }
}
