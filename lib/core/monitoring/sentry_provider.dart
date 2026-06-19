import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'sentry_service.dart';

/// Sentry 事务追踪器 Provider（全局单例）
///
/// 使用方式：
///   final tracer = ref.read(sentryTracerProvider);
///   final span = tracer.start('login', 'auth');
///   await login();
///   span?.finish();
final sentryTracerProvider = Provider<SentryTransactionTracer>((ref) {
  return SentryTransactionTracer();
});

/// Sentry 性能事务追踪器
///
/// 封装 Transaction 生命周期，自动处理 null（Sentry 未启用时）
class SentryTransactionTracer {
  /// 启动一个性能事务
  ///
  /// [name] 事务名称，如 'app-start'
  /// [operation] 操作类型，如 'ui.load' / 'http.client' / 'db.sql'
  ISentrySpan? start(String name, String operation) {
    return SentryService.startTransaction(name, operation, bindToScope: true);
  }

  /// 启动一个子 Span
  ISentrySpan? startChild(ISentrySpan? parent, String operation, String description) {
    if (parent == null) return null;
    return parent.startChild(operation, description: description);
  }

  /// 安全结束 Span
  void finish(ISentrySpan? span, {int? status}) {
    if (span == null) return;
    span.finish();
  }
}
