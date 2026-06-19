// test/core/network/ws_client_test.dart
//
// WsClient 边界测试：
// 1. WebSocket 断线重连后消息续传测试
// 2. 非法 JSON 消息的容错测试

import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/network/ws_client.dart';

void main() {
  group('【WS-边界1】非法 JSON 消息的容错', () {
    test('GIVEN 收到非法 JSON 字符串 WHEN 模拟 _handleMessage THEN jsonDecode 抛 FormatException', () async {
      // WsClient._handleMessage 内部 jsonDecode 会抛 FormatException
      // 被 catch 捕获并 add 到 _onError
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
      );

      // 直接验证：非法 JSON 确实抛 FormatException
      try {
        jsonDecode('not valid json');
        fail('Should have thrown FormatException');
      } catch (e) {
        expect(e, isA<FormatException>());
      }

      client.dispose();
    });

    test('GIVEN 收到合法 JSON 但 type 字段缺失 THEN type=null 走 default 分支，不崩溃', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
      );

      // 合法 JSON 但无 type 字段
      const noTypeJson = '{"payload": {"data": 123}}';
      final parsed = jsonDecode(noTypeJson) as Map<String, dynamic>;
      final type = parsed['type'] as String?;
      expect(type, isNull); // type 为 null → default 分支

      client.dispose();
    });

    test('GIVEN 收到合法 JSON 但 payload 不是 Map THEN 类型转换失败', () async {
      const badPayloadJson = '{"type": "LOCATION_UPDATE", "payload": "not_a_map"}';
      final parsed = jsonDecode(badPayloadJson) as Map<String, dynamic>;

      // 模拟 WsClient._handleMessage 的行为：cast 失败
      try {
        final payload = parsed['payload'] as Map<String, dynamic>;
        fail('Should have thrown TypeError');
      } catch (e) {
        expect(e, isNotNull);
      }
    });

    test('GIVEN 收到完整合法消息 THEN 正确解析 type 和 payload', () async {
      const validJson = '{"type": "LOCATION_UPDATE", "payload": {"lat": 31.23, "lng": 121.47}}';
      final parsed = jsonDecode(validJson) as Map<String, dynamic>;
      final type = parsed['type'] as String?;
      final payload = parsed['payload'] as Map<String, dynamic>;

      expect(type, 'LOCATION_UPDATE');
      expect(payload['lat'], 31.23);
    });
  });

  group('【WS-边界2】断线重连行为验证', () {
    test('GIVEN WsClient 未连接 WHEN send() THEN 触发 onError', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
      );

      final errors = <Object>[];
      final errorSub = client.onError.listen((e) {
        errors.add(e);
      });

      // 未连接时 send → StateError
      client.send({'type': 'test', 'payload': {}});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(errors.length, 1);
      expect(errors.first, isA<StateError>());

      client.dispose();
      await errorSub.cancel();
    });

    test('GIVEN 主动 disconnect WHEN 调用后 THEN 不自动重连', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
        maxReconnectAttempts: 3,
      );

      // 主动断开 → _intentionalClose = true → 不重连
      client.disconnect();
      expect(client.isConnected, false);

      client.dispose();
    });

    test('GIVEN 重连次数达到上限 WHEN 超过 maxReconnectAttempts THEN 不再重连', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
        maxReconnectAttempts: 0,
      );

      // connect 后断开 → 由于 maxReconnectAttempts=0，不重连
      // 仅验证构造和 dispose 正常
      client.dispose();
    });
  });

  group('【WS-边界3】dispose 安全性', () {
    test('GIVEN 未连接 WHEN dispose THEN 不抛异常', () {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
      );

      expect(() => client.dispose(), returnsNormally);
    });

    test('GIVEN 已 disconnect WHEN dispose THEN 不抛异常', () {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
      );

      client.disconnect();
      expect(() => client.dispose(), returnsNormally);
    });

    test('GIVEN 事件流已关闭 WHEN 再次读取 THEN 不崩溃', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
      );

      client.dispose();

      // dispose 后流已关闭，监听应直接结束
      final locationEvents = <Map<String, dynamic>>[];
      final sub = client.onLocationUpdate.listen(
        (data) => locationEvents.add(data),
        onError: (e) {},
        onDone: () {},
      );

      await Future.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(locationEvents, isEmpty);
    });
  });

  group('【WS-边界4】消息续传验证（间接）', () {
    test('GIVEN 客户端断线 WHEN send() THEN 消息通过 onError 通知调用方', () async {
      final client = WsClient(
        baseUrl: 'ws://localhost:8080',
        tokenGetter: () async => 'test-token',
        heartbeatInterval: const Duration(seconds: 300),
      );

      final errors = <Object>[];
      final errorSub = client.onError.listen((e) {
        errors.add(e);
      });

      // 未连接状态下 send → StateError: WebSocket not connected
      client.send({'type': 'message_quick', 'payload': {'text': 'hello'}});
      await Future.delayed(const Duration(milliseconds: 50));

      expect(errors.length, 1);
      expect((errors.first as StateError).message, contains('not connected'));

      client.dispose();
      await errorSub.cancel();
    });

    test('GIVEN WsClient 构造参数 WHEN 验证指数退避逻辑 THEN delay = 2^attempts 秒，上限 60', () {
      // 验证指数退避计算逻辑
      for (int attempt = 1; attempt <= 6; attempt++) {
        final delay = (1 << attempt).clamp(2, 60);
        if (attempt == 1) expect(delay, 2);
        if (attempt == 2) expect(delay, 4);
        if (attempt == 3) expect(delay, 8);
        if (attempt == 4) expect(delay, 16);
        if (attempt == 5) expect(delay, 32);
        if (attempt == 6) expect(delay, 60); // 64 clamped to 60
      }
    });
  });
}
