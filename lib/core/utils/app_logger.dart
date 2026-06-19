import 'package:flutter/foundation.dart';

import '../monitoring/sentry_service.dart';

/// 全局 Logger —— 日志脱敏 + 分级 + 生产环境自动屏蔽
///
/// 使用方式：
///   AppLogger.debug('调试信息');   // 仅开发环境输出
///   AppLogger.info('业务事件');    // 开发 + 生产都输出（关键路径）
///   AppLogger.warn('警告信息');    // 开发 + 生产都输出
///   AppLogger.error('错误信息', e, stack); // 开发 + 生产都输出，生产环境可上报
///
/// 敏感数据脱敏：
///   AppLogger.info('用户登录: ${LoggerMask.email(userEmail)}');
///   AppLogger.info('Token: ${LoggerMask.token(authToken)}');
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// 日志工具类
class AppLogger {
  /// 当前日志级别（生产环境自动调整为 info）
  static LogLevel _minLevel = kReleaseMode ? LogLevel.info : LogLevel.debug;

  /// 设置日志级别（测试时可临时调低）
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// DEBUG：仅开发环境输出
  static void debug(String message) {
    if (_minLevel.index <= LogLevel.debug.index) {
      debugPrint('[DEBUG] $message');
    }
  }

  /// INFO：开发 + 生产都输出（关键业务事件）
  static void info(String message) {
    if (_minLevel.index <= LogLevel.info.index) {
      debugPrint('[INFO] $message');
    }
  }

  /// WARN：开发 + 生产都输出
  static void warn(String message) {
    if (_minLevel.index <= LogLevel.warn.index) {
      debugPrint('[WARN] $message');
    }
  }

  /// ERROR：开发 + 生产都输出，生产环境自动上报 Sentry
  static void error(
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (_minLevel.index <= LogLevel.error.index) {
      debugPrint('[ERROR] $message');
      if (error != null) debugPrint('  Error: $error');
      if (stack != null) debugPrint('  Stack: $stack');
    }

    // [Phase 1] 生产环境上报 Sentry（保留 PII 脱敏）
    if (kReleaseMode) {
      SentryService.captureException(
        error ?? Exception(message),
        stackTrace: stack,
        hint: 'app_logger_error',
        extra: {'message': message},
      );
    }
  }
}

/// 敏感数据脱敏工具
class LoggerMask {
  /// 邮箱脱敏：example@gmail.com → e******@gmail.com
  static String email(String? value) {
    if (value == null || !value.contains('@')) return '***';
    final parts = value.split('@');
    if (parts[0].length <= 2) return '${parts[0][0]}***@${parts[1]}';
    return '${parts[0][0]}***@${parts[1]}';
  }

  /// 手机号脱敏：13812345678 → 138****5678
  static String phone(String? value) {
    if (value == null || value.length < 7) return '***';
    return '${value.substring(0, 3)}****${value.substring(value.length - 4)}';
  }

  /// Token 脱敏：长字符串 → Bearer eyJ***xyz（保留前6后3）
  static String token(String? value) {
    if (value == null || value.length < 12) return '***';
    return '${value.substring(0, 6)}***${value.substring(value.length - 3)}';
  }

  /// 姓名脱敏：张三 → 张*，李四五 → 李**
  static String name(String? value) {
    if (value == null || value.isEmpty) return '***';
    if (value.length == 1) return value;
    if (value.length == 2) return '${value[0]}*';
    return '${value[0]}${'*' * (value.length - 2)}${value[value.length - 1]}';
  }

  /// 通用脱敏：保留前后各 1 字符，中间用 *** 替代
  static String generic(String? value, {int visible = 1}) {
    if (value == null || value.length <= visible * 2) return '***';
    return '${value.substring(0, visible)}***${value.substring(value.length - visible)}';
  }
}
