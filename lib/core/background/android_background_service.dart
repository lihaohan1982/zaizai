import 'dart:io';
import 'package:flutter/foundation.dart';

/// Android 后台保活（架构占位）
/// - 前台服务需引入 flutter_foreground_task 依赖后取消注释
/// - WorkManager 需引入 workmanager 依赖后取消注释
class AndroidBackgroundService {
  /// 启动前台服务（Android 12+ 必须）
  static Future<void> startForegroundService() async {
    if (!Platform.isAndroid) return;
    // TODO: 引入 flutter_foreground_task 后取消注释
    debugPrint('[AndroidBackgroundService] foreground service started (stub)');
  }

  /// 初始化 WorkManager 周期任务（兜底）
  static Future<void> initWorkManager() async {
    if (!Platform.isAndroid) return;
    // TODO: 引入 workmanager 后取消注释
    debugPrint('[AndroidBackgroundService] WorkManager initialized (stub)');
  }

  /// WorkManager 回调入口（独立 Isolate）
  @pragma('vm:entry-point')
  static void callbackDispatcher() {
    debugPrint('[AndroidBackgroundService] WorkManager callback (stub)');
  }
}
