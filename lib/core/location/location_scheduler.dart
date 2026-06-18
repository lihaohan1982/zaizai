import 'package:battery_plus/battery_plus.dart';

/// 定位上报级别（P2 电量降级策略）
enum LocationReportLevel {
  /// 正常上报：按 LocationStrategyEngine 的动态策略执行
  full,

  /// 低功耗模式：降低频率（静止 10min，移动 5min），忽略位移触发
  lowPower,

  /// 挂起：仅依赖系统 Significant-Change，停止主动上报
  suspend,
}

/// 根据电量和充电状态动态计算上报级别
class LocationScheduler {
  const LocationScheduler._();

  /// 获取当前应使用的上报级别
  static Future<LocationReportLevel> getReportLevel() async {
    try {
      final battery = Battery();
      final level = await battery.batteryLevel; // int, 0–100
      final state = await battery.batteryState;

      // 电量 < 10% 且未充电 → SUSPEND
      if (level < 10 && state == BatteryState.discharging) {
        return LocationReportLevel.suspend;
      }

      // 电量 < 20% 且未充电 → LOW_POWER
      if (level < 20 && state == BatteryState.discharging) {
        return LocationReportLevel.lowPower;
      }

      // 充电中或电量充足 → FULL
      return LocationReportLevel.full;
    } catch (_) {
      // 获取电量失败，保守返回 full
      return LocationReportLevel.full;
    }
  }
}
