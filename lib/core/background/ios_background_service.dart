import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart'; // AppLifecycleState
import 'package:location_chat_app/core/location/location_strategy.dart';

/// iOS 后台保活
/// 严格依赖 CoreLocation Significant-Change，
/// 不引入 BackgroundFetch，完全通过生命周期事件驱动 LocationStrategyEngine。
class IOSBackgroundService {
  IOSBackgroundService._();

  static bool _initialized = false;

  /// 初始化生命周期监听（仅 iOS 调用一次）
  static Future<void> init() async {
    if (_initialized || !Platform.isIOS) return;
    _initialized = true;

    SystemChannels.lifecycle.setMessageHandler((msg) {
      if (msg == AppLifecycleState.paused.toString()) {
        LocationStrategyEngine.instance.onAppBackground();
      } else if (msg == AppLifecycleState.resumed.toString()) {
        LocationStrategyEngine.instance.onAppForeground();
      }
      return Future.value(null);
    });

    debugPrint('[IOSBackgroundService] lifecycle listener registered');
  }
}
