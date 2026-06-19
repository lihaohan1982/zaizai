import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../auth/token_storage.dart';

/// Auth 拦截器 —— Token 自动刷新 + 请求队列挂起
///
/// 工作流程：
///   1. 请求发出前注入最新 Token（从 TokenStorage 动态读取）
///   2. 收到 401 响应 → 挂起当前请求队列 → 调用 refreshToken
///   3. 刷新成功 → 用新 Token 重发挂起的请求
///   4. 刷新失败 → 强制登出（通过 onAuthFailure 回调）
class AuthInterceptor extends Interceptor {
  final TokenStorage _tokenStorage;
  final Dio _refreshDio;
  final String _refreshTokenPath;
  final void Function()? onAuthFailure;

  /// 是否已有 refresh 请求在进行中（避免并发刷新）
  bool _isRefreshing = false;

  /// 挂起的请求队列（401 时暂存，refresh 成功后重发）
  final _pendingRequests = <void Function()>[];

  AuthInterceptor({
    required TokenStorage tokenStorage,
    required String baseUrl,
    this.onAuthFailure,
    String refreshTokenPath = '/api/auth/refresh',
  })  : _tokenStorage = tokenStorage,
        _refreshTokenPath = refreshTokenPath,
        _refreshDio = Dio(BaseOptions(baseUrl: baseUrl)) {
    // refresh Dio 不挂载 AuthInterceptor，避免无限循环
  }

  @override
  void onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    try {
      final token = await _tokenStorage.readToken();
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    } catch (e) {
      debugPrint('[AuthInterceptor] 读取 Token 失败: $e');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 非 401，直接放行
    handler.next(response);
  }

  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    if (err.response?.statusCode == 401) {
      // 401 → 尝试刷新 Token
      await _handleUnauthorized(err, handler);
    } else {
      handler.next(err);
    }
  }

  /// 处理 401：刷新 Token → 重发请求 或 强制登出
  Future<void> _handleUnauthorized(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    final options = err.requestOptions;

    if (!_isRefreshing) {
      _isRefreshing = true;
      try {
        final newToken = await _refreshToken();
        if (newToken != null) {
          // 刷新成功：更新 Token 存储，重发原始请求
          await _tokenStorage.writeToken(newToken);
          _retryPendingRequests(newToken);

          // 重发当前请求
          final response = await _retryRequest(options, newToken);
          handler.resolve(response);
        } else {
          // 刷新失败：清空 Token，强制登出
          await _tokenStorage.deleteToken();
          onAuthFailure?.call();
          handler.next(err);
        }
      } catch (e) {
        // 刷新异常：强制登出
        await _tokenStorage.deleteToken();
        onAuthFailure?.call();
        handler.next(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      // 已有刷新在进行中 → 将当前请求加入挂起队列
      _pendingRequests.add(() async {
        final token = await _tokenStorage.readToken();
        if (token != null) {
          final response = await _retryRequest(options, token);
          handler.resolve(response);
        } else {
          handler.next(err);
        }
      });
    }
  }

  /// 调用 refresh token 接口
  Future<String?> _refreshToken() async {
    try {
      final refreshToken = await _tokenStorage.readRefreshToken();
      if (refreshToken == null) return null;

      final response = await _refreshDio.post(
        _refreshTokenPath,
        data: {'refresh_token': refreshToken},
      );

      if (response.statusCode == 200) {
        final data = response.data as Map<String, dynamic>;
        // 同时更新 refreshToken（若后端返回新的一版）
        final newRefreshToken = data['refresh_token'] as String?;
        if (newRefreshToken != null) {
          await _tokenStorage.writeRefreshToken(newRefreshToken);
        }
        return data['token'] as String?;
      }
    } catch (e) {
      debugPrint('[AuthInterceptor] 刷新 Token 失败: $e');
    }
    return null;
  }

  /// 用新 Token 重发单个请求
  Future<Response> _retryRequest(
    RequestOptions options,
    String token,
  ) async {
    options.headers['Authorization'] = 'Bearer $token';
    return await Dio().fetch(options);
  }

  /// 重发所有挂起的请求
  void _retryPendingRequests(String token) {
    for (final callback in _pendingRequests) {
      callback();
    }
    _pendingRequests.clear();
  }
}
