import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_storage.dart';

/// Dio 客户端 — 依赖注入版本
///
/// 阶段三安全整改：
///   - 不再使用 SharedPreferences 明文存储 Token
///   - 构造时注入 [TokenStorage]，每次请求从安全存储动态读取 Token
///   - baseUrl 由调用方提供（来自 EnvConfig / AppConfig）
class DioClient {
  final Dio dio;
  final TokenStorage _tokenStorage;

  DioClient({
    required String baseUrl,
    required TokenStorage tokenStorage,
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
    // 添加 Token 拦截器：每次请求动态从安全存储读取
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
  }
}
