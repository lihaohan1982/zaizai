import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:geolocator/geolocator.dart';
// TODO(workmanager): workmanager 包已从 pubspec.yaml 移除（Kotlin 嵌入 API 不兼容）
// 后续需升级到 workmanager 0.6+ 或迁移到 FlutterWorkManager
// import 'package:workmanager/workmanager.dart';

import 'package:location_chat_app/core/location/location_strategy.dart';

/// Android 后台服务：前台通知栏 + 位置采集
///
/// 双保险架构：
///   1. flutter_foreground_task → App 存活时保活前台服务（系统托盘通知）
///   2. workmanager → App 被杀后仍可周期性恢复位置采集
///
/// Android 12+ 要求：必须使用前台服务（前台通知）才能持续获取后台位置
class AndroidBackgroundService {
  AndroidBackgroundService._();

  /// 前台通知渠道 ID
  static const _channelId = 'location_chat_foreground';
  static const _channelName = '位置共享服务';
  static const _channelDesc = '保持位置分享在后台持续运行';

  /// WorkManager 任务名称
  static const _wmTaskName = 'LocationChatBackgroundTask';

  // ── 初始化 ───────────────────────────────────────────

  /// 全局初始化（在 main.dart 中调用一次）
  static Future<void> init() async {
    if (!Platform.isAndroid) return;

    // 1. 初始化 flutter_foreground_task（设置通知和任务选项）
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _channelId,
        channelName: _channelName,
        channelDescription: _channelDesc,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000), // 30s 重复事件
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );

    // 2. 初始化 WorkManager（App 被杀后的兜底）
    // TODO(workmanager): 待重新集成 workmanager 0.6+
    // await Workmanager().initialize(
    //   _wmCallbackDispatcher,
    //   isInDebugMode: kDebugMode,
    // );

    debugPrint(
        '[AndroidBackgroundService] Initialized (flutter_foreground_task + workmanager)');
  }

  /// 初始化 WorkManager（由 LocationService 调用）
  /// TODO(workmanager): 待重新集成 workmanager 0.6+
  static Future<void> initWorkManager() async {
    debugPrint('[AndroidBackgroundService] initWorkManager: workmanager 未集成，跳过');
  }

  // ── 前台服务控制 ─────────────────────────────────────

  /// 启动前台服务（进入后台时调用）
  static Future<void> startForegroundService() async {
    if (!Platform.isAndroid) return;

    // 如果已有任务在运行，先停止
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }

    // 先设置任务处理器（必须在 startService 之前）
    FlutterForegroundTask.setTaskHandler(LocationChatTaskHandler());

    // 启动前台服务
    final result = await FlutterForegroundTask.startService(
      notificationTitle: '位置共享运行中',
      notificationText: '点击查看详情',
      notificationIcon: const NotificationIcon(
        metaDataName: 'flutter_foreground_task_icon',
      ),
    );

    if (result is ServiceRequestSuccess) {
      debugPrint(
          '[AndroidBackgroundService] Foreground service started successfully');
    } else {
      debugPrint(
          '[AndroidBackgroundService] Foreground service failed: $result');
    }
  }

  /// 停止前台服务（回到前台时调用）
  static Future<void> stopForegroundService() async {
    if (!Platform.isAndroid) return;
    await FlutterForegroundTask.stopService();
    debugPrint('[AndroidBackgroundService] Foreground service stopped');
  }

  /// 注册应用生命周期监听，自动启停前台服务
  ///
  /// 内部使用 [WidgetsBindingObserver] 模式，不依赖 flutter_foreground_task 的 API。
  static void registerAppLifecycleListener({
    required void Function() onBackgroundEnter,
    required void Function() onForegroundEnter,
  }) {
    _AppLifecycleManager.instance
      ..onBackgroundEnter = onBackgroundEnter
      ..onForegroundEnter = onForegroundEnter;
  }

  // ── WorkManager 兜底任务 ─────────────────────────────

  /// 注册 WorkManager 周期性任务（App 被 kill 后自动恢复）
  /// TODO(workmanager): 待重新集成 workmanager 0.6+
  static Future<void> registerPeriodicTask() async {
    if (!Platform.isAndroid) return;
    debugPrint('[AndroidBackgroundService] registerPeriodicTask: workmanager 未集成，跳过');
  }

  /// 取消 WorkManager 周期性任务
  /// TODO(workmanager): 待重新集成 workmanager 0.6+
  static Future<void> cancelPeriodicTask() async {
    if (!Platform.isAndroid) return;
    debugPrint('[AndroidBackgroundService] cancelPeriodicTask: workmanager 未集成，跳过');
  }

  // ── 内部回调 ─────────────────────────────────────────

  /// WorkManager 回调分发器（在独立 isolate 中执行）
  /// TODO(workmanager): 待重新集成 workmanager 0.6+
  @pragma('vm:entry-point')
  static void _wmCallbackDispatcher() {
    debugPrint('[AndroidBackgroundService] _wmCallbackDispatcher: workmanager 未集成，空实现');
    // Workmanager().executeTask((task, inputData) async {
    //   ...原逻辑保留待恢复...
    //   return true;
    // });
  }
}

/// 应用生命周期管理器（使用 [WidgetsBindingObserver] 模式）
///
/// 独立于 flutter_foreground_task，与 v8.17.0 API 兼容。
class _AppLifecycleManager with WidgetsBindingObserver {
  _AppLifecycleManager._() {
    WidgetsBinding.instance.addObserver(this);
  }

  static final _AppLifecycleManager instance = _AppLifecycleManager._();

  void Function()? onBackgroundEnter;
  void Function()? onForegroundEnter;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.inactive:
        onBackgroundEnter?.call();
        break;
      case AppLifecycleState.resumed:
        onForegroundEnter?.call();
        break;
      case AppLifecycleState.hidden:
        break;
    }
  }
}

/// Foreground Task Handler：处理前台服务生命周期事件
class LocationChatTaskHandler extends TaskHandler {
  StreamSubscription<Position>? _positionSub;
  Timer? _periodicTimer;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // 仅在开发者主动启动时初始化位置流（系统启动不重复拉起）
    if (starter == TaskStarter.developer) {
      debugPrint(
          '[LocationChatTaskHandler] Service started (starter=$starter)');
      _startPeriodicLocation();
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // 每 30s 触发一次（由 ForegroundTaskOptions repeat interval 控制）
    debugPrint('[LocationChatTaskHandler] Repeat event at $timestamp');
    await _requestLocation();
  }

  @override
  Future<void> onDestroy(DateTime timestamp) async {
    debugPrint('[LocationChatTaskHandler] Service destroyed');
    await _positionSub?.cancel();
    _periodicTimer?.cancel();
  }

  void _startPeriodicLocation() {
    _periodicTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      _requestLocation();
    });
  }

  Future<void> _requestLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 30),
      );

      debugPrint(
          '[LocationChatTaskHandler] Location: ${position.latitude}, ${position.longitude} accuracy=${position.accuracy}m');

      // 将位置传递给 LocationStrategyEngine（如果主引擎在运行）
      final engine = LocationStrategyEngine.instance;
      if (engine.isRunning) {
        engine.injectLocation(position);
      }
    } catch (e) {
      debugPrint('[LocationChatTaskHandler] Location error: $e');
    }
  }
}
