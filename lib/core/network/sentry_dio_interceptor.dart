import 'package:dio/dio.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../config/env_config.dart';
import '../monitoring/sentry_service.dart';

/// Dio 拦截器 —— 自动将 HTTP 请求作为 Sentry 性能 Span 上报
///
/// 命名规范：
///   - Transaction: 请求路径（如 /api/friends）
///   - Operation:   http.client
///   - Span status: 根据 response status code 自动设置
class SentryDioInterceptor extends Interceptor {
  final Map<RequestOptions, ISentrySpan> _spans = {};

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (!EnvConfig.isSentryEnabled) {
      handler.next(options);
      return;
    }

    final span = SentryService.startTransaction(
      '${options.method.toUpperCase()} ${options.path}',
      'http.client',
      bindToScope: false,
    );
    if (span != null) {
      span.setData('url', options.uri.toString());
      span.setData('method', options.method);
      _spans[options] = span;
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final span = _spans.remove(response.requestOptions);
    if (span != null) {
      span.status = _toSpanStatus(response.statusCode);
      span.setData('status_code', response.statusCode ?? -1);
      span.finish();
    }
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final span = _spans.remove(err.requestOptions);
    if (span != null) {
      span.setData('status_code', err.response?.statusCode ?? -1);
      span.setData('error_type', err.type.toString());
      span.setData('error_message', err.message ?? '');
      span.status = const SpanStatus.unknownError();
      span.finish();
    }
    handler.next(err);
  }

  static SpanStatus _toSpanStatus(int? statusCode) {
    if (statusCode == null) return const SpanStatus.unknownError();
    if (statusCode >= 200 && statusCode < 300) return const SpanStatus.ok();
    if (statusCode == 400) return const SpanStatus.invalidArgument();
    if (statusCode == 401) return const SpanStatus.unauthenticated();
    if (statusCode == 403) return const SpanStatus.permissionDenied();
    if (statusCode == 404) return const SpanStatus.notFound();
    if (statusCode >= 400 && statusCode < 500) return const SpanStatus.invalidArgument();
    if (statusCode >= 500) return const SpanStatus.internalError();
    return const SpanStatus.unknownError();
  }
}
