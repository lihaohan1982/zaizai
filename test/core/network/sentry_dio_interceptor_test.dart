import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/network/sentry_dio_interceptor.dart';

void main() {
  group('SentryDioInterceptor', () {
    late Dio dio;
    late SentryDioInterceptor interceptor;

    setUp(() {
      dio = Dio(BaseOptions(baseUrl: 'http://localhost:3001'));
      interceptor = SentryDioInterceptor();
      dio.interceptors.add(interceptor);
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: {'ok': true},
          ));
        },
      ));
    });

    test('Sentry 禁用时请求正常透传，不抛异常', () async {
      final response = await dio.get('/api/test');
      expect(response.statusCode, 200);
      expect(response.data, {'ok': true});
    });

    test('请求错误时拦截器不抛异常', () async {
      dio.interceptors.clear();
      dio.interceptors.add(interceptor);
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.reject(DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
            error: 'connection refused',
          ));
        },
      ));

      await expectLater(
        dio.get('/api/test'),
        throwsA(isA<DioException>()),
      );
    });
  });
}
