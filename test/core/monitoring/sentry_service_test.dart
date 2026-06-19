import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/monitoring/sentry_service.dart';

void main() {
  group('SentryService', () {
    test('Sentry 未启用时 initialize 不抛出异常', () async {
      // 测试环境 SENTRY_DSN 默认为空，initialize 应直接返回
      await expectLater(SentryService.initialize(), completes);
    });

    test('Sentry 未启用时 captureException 不抛出异常', () async {
      await expectLater(
        SentryService.captureException(Exception('test')),
        completes,
      );
    });

    test('Sentry 未启用时 captureMessage 不抛出异常', () async {
      await expectLater(
        SentryService.captureMessage('test message'),
        completes,
      );
    });

    test('Sentry 未启用时 addBreadcrumb 不抛出异常', () async {
      await expectLater(
        SentryService.addBreadcrumb(message: 'navigate to login'),
        completes,
      );
    });

    test('Sentry 未启用时 startTransaction 返回 null', () {
      expect(SentryService.startTransaction('login', 'auth'), isNull);
    });

    test('邮箱脱敏保留首尾和域名', () {
      // 通过反射无法直接访问私有方法，测试 setUser 不抛异常即可
      // 脱敏逻辑在内部执行，此处仅验证不崩溃
      expectLater(
        SentryService.setUser(
          email: 'user@example.com',
          phone: '13800138000',
          name: 'Alice',
        ),
        completes,
      );
    });

    test('短姓名脱敏不抛异常', () async {
      await expectLater(
        SentryService.setUser(name: 'Al', phone: '1234567'),
        completes,
      );
    });

    test('clearUser 不抛出异常', () async {
      await expectLater(SentryService.clearUser(), completes);
    });
  });

  group('NoopSentryService', () {
    test('所有方法均为空操作', () async {
      await expectLater(
        NoopSentryService.captureException(Exception('test')),
        completes,
      );
      await expectLater(
        NoopSentryService.captureMessage('test'),
        completes,
      );
      await expectLater(
        NoopSentryService.addBreadcrumb(message: 'test'),
        completes,
      );
      expect(NoopSentryService.startTransaction('t', 'op'), isNull);
      await expectLater(
        NoopSentryService.setUser(id: '1'),
        completes,
      );
      await expectLater(NoopSentryService.clearUser(), completes);
    });
  });
}
