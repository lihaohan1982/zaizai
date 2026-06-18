import 'env_config.dart';

/// 应用全局配置
///
/// 阶段三安全整改：
///   - 服务端地址全部下沉到 .env，由 [EnvConfig] 统一加载与校验
///   - 本类保留运行时无关的静态常量，避免直接硬编码 URL
class AppConfig {
  AppConfig._();

  // -------------------------------------------------------------------------
  // 服务端（从环境变量读取）
  // -------------------------------------------------------------------------
  static String get apiBaseUrl => EnvConfig.apiBaseUrl;
  static String get wsBaseUrl => EnvConfig.wsBaseUrl;

  // -------------------------------------------------------------------------
  // 高德地图（AMap）
  // -------------------------------------------------------------------------
  /// ⚠️ 需替换为真实 Key（Android 真机调试必须）
  static String get amapApiKey => EnvConfig.amapApiKey;

  // -------------------------------------------------------------------------
  // 隐私与安全
  // -------------------------------------------------------------------------
  /// 隐私暂停最大时长（小时）
  static const int maxPauseDurationHours = 24;

  /// 位置上报最小间隔（秒）
  static const int locationReportIntervalSeconds = 30;
}
