// lib/core/config/app_config.dart
/// 应用全局配置
class AppConfig {
  AppConfig._();

  // -------------------------------------------------------------------------
  // 服务端
  // -------------------------------------------------------------------------
  static const String apiBaseUrl = 'http://localhost:3001/api';
  static const String wsBaseUrl = 'ws://localhost:3001';

  // -------------------------------------------------------------------------
  // 高德地图（AMap）
  // -------------------------------------------------------------------------
  /// ⚠️ 需替换为真实 Key（Android 真机调试必须）
  static const String amapApiKey = String.fromEnvironment(
    'AMAP_API_KEY',
    defaultValue: 'YOUR_AMAP_API_KEY_HERE',
  );

  // -------------------------------------------------------------------------
  // 隐私与安全
  // -------------------------------------------------------------------------
  /// 隐私暂停最大时长（小时）
  static const int maxPauseDurationHours = 24;

  /// 位置上报最小间隔（秒）
  static const int locationReportIntervalSeconds = 30;
}
