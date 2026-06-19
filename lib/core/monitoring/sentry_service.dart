import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env_config.dart';

/// Sentry 崩溃监控与性能追踪抽象层
///
/// 职责：
///   - 屏蔽 Sentry SDK 的具体调用细节
///   - 支持 dev/staging 环境禁用（DSN 为空）
///   - 提供可测试接口（测试可注入 [NoopSentryService]）
///   - 自动附加 PII 脱敏上下文
///
/// 使用方式：
///   await SentryService.initialize();
///   SentryService.captureException(e, stackTrace);
///   SentryService.startTransaction('login', 'auth');
abstract class SentryService {
  /// 初始化 Sentry（必须在 runApp 之前调用）
  static Future<void> initialize() async {
    if (!EnvConfig.isSentryEnabled) {
      debugPrint('[SentryService] Sentry 未启用（SENTRY_DSN 为空）');
      return;
    }

    await SentryFlutter.init(
      (options) {
        options.dsn = EnvConfig.sentryDsn;
        options.environment = EnvConfig.appEnv;
        options.debug = EnvConfig.isDevelopment;
        options.tracesSampleRate = 1.0;
        options.profilesSampleRate = 0.3;
        options.attachStacktrace = true;
        // v8.x 自动生命周期 breadcrumb 由默认集成处理，无需显式开启

        // PII 脱敏：禁止发送 IP 地址
        options.sendDefaultPii = false;
      },
    );
  }

  /// 捕获异常并上报
  static Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? hint,
    Map<String, dynamic>? extra,
  }) async {
    if (!EnvConfig.isSentryEnabled) {
      debugPrint('[SentryService] 异常未上报（Sentry 未启用）: $exception');
      return;
    }

    await Sentry.captureException(
      exception,
      stackTrace: stackTrace,
      withScope: (scope) {
        if (extra != null) {
          scope.setContexts('app_logger', extra);
        }
      },
    );
  }

  /// 捕获消息（非异常）
  static Future<void> captureMessage(
    String message, {
    SentryLevel level = SentryLevel.info,
  }) async {
    if (!EnvConfig.isSentryEnabled) return;
    await Sentry.captureMessage(message, level: level);
  }

  /// 添加 Breadcrumb（用户路径/操作追踪）
  static Future<void> addBreadcrumb({
    required String message,
    String? category,
    String? type,
    Map<String, dynamic>? data,
  }) async {
    if (!EnvConfig.isSentryEnabled) return;

    await Sentry.addBreadcrumb(
      Breadcrumb(
        message: message,
        category: category,
        type: type,
        data: data,
        level: SentryLevel.info,
      ),
    );
  }

  /// 启动性能事务（Transaction）
  static ISentrySpan? startTransaction(
    String name,
    String operation, {
    bool bindToScope = false,
  }) {
    if (!EnvConfig.isSentryEnabled) return null;
    return Sentry.startTransaction(name, operation, bindToScope: bindToScope);
  }

  /// 设置用户信息（全部脱敏）
  static Future<void> setUser({
    String? id,
    String? email,
    String? phone,
    String? name,
  }) async {
    if (!EnvConfig.isSentryEnabled) return;

    await Sentry.configureScope((scope) {
      scope.setUser(
        SentryUser(
          id: id,
          email: _maskEmail(email),
          // Sentry 原生 SentryUser 没有 phone 字段，放入 data
          data: {
            if (phone != null) 'phone': _maskPhone(phone),
            if (name != null) 'name': _maskName(name),
          },
        ),
      );
    });
  }

  /// 清除用户信息（登出时调用）
  static Future<void> clearUser() async {
    if (!EnvConfig.isSentryEnabled) return;
    await Sentry.configureScope((scope) => scope.setUser(null));
  }

  static String? _maskEmail(String? value) {
    if (value == null || !value.contains('@')) return null;
    final parts = value.split('@');
    return '${parts[0][0]}***@${parts[1]}';
  }

  static String _maskPhone(String value) {
    if (value.length < 7) return '***';
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }

  static String _maskName(String value) {
    if (value.length <= 2) return '${value[0]}*';
    return '${value[0]}${'*' * (value.length - 2)}${value[value.length - 1]}';
  }
}

/// 测试用 Noop 实现（避免测试触发平台通道）
class NoopSentryService {
  static Future<void> captureException(
    Object exception, {
    StackTrace? stackTrace,
    String? hint,
    Map<String, dynamic>? extra,
  }) async {}
  static Future<void> captureMessage(String message) async {}
  static Future<void> addBreadcrumb({
    required String message,
    String? category,
    String? type,
    Map<String, dynamic>? data,
  }) async {}
  static ISentrySpan? startTransaction(String name, String operation) => null;
  static Future<void> setUser({String? id, String? email, String? phone, String? name}) async {}
  static Future<void> clearUser() async {}
}
