import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_storage.dart';
import 'auth_interceptor.dart';
import 'sentry_dio_interceptor.dart';

/// Dio 客户端 — 依赖注入版本
///
/// 阶段三安全整改：
///   - 不再使用 SharedPreferences 明文存储 Token
///   - 构造时注入 [TokenStorage]，每次请求从安全存储动态读取 Token
///   - baseUrl 由调用方提供（来自 EnvConfig / AppConfig）
///
/// Phase 0 生产韧性：
///   - 注入 [AuthInterceptor] 实现 401 自动刷新 Token
class DioClient {
  final Dio dio;
  final TokenStorage _tokenStorage;

  DioClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
    void Function()? onAuthFailure,
    Duration connectTimeout = const Duration(seconds: 10),
    Duration receiveTimeout = const Duration(seconds: 10),
  })  : _tokenStorage = tokenStorage,
        dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: connectTimeout,
          receiveTimeout: receiveTimeout,
          headers: {
            'Content-Type': 'application/json',
          },
        )) {
    // 1. Token 注入拦截器（每次请求动态读取）
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        try {
          final token = await _tokenStorage.readToken();
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
        } catch (e) {
          debugPrint('[DioClient] 读取 Token 失败: $e');
        }
        handler.next(options);
      },
    ));

    // 2. Auth 拦截器（401 自动刷新 Token）
    dio.interceptors.add(AuthInterceptor(
      tokenStorage: tokenStorage,
      baseUrl: baseUrl,
      onAuthFailure: onAuthFailure,
    ));

    // 3. Sentry 性能监控拦截器（Phase 1）
    dio.interceptors.add(SentryDioInterceptor());
  }
}
