// test/core/security/geo_encryption_service_test.dart
//
// 验证 ProdGeoEncryptionService AES-256-GCM 加密/解密完整性
// 以及 DevGeoEncryptionService 安全禁用

import 'dart:convert';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_test/flutter_test.dart';
import 'package:location_chat_app/core/security/geo_encryption_service.dart';

void main() {
  // -----------------------------------------------------------------------
  // DevGeoEncryptionService — 加密/解密必须抛异常
  // -----------------------------------------------------------------------
  group('DevGeoEncryptionService 安全禁用', () {
    late DevGeoEncryptionService service;

    setUp(() {
      service = DevGeoEncryptionService();
    });

    test('【SEC-1】GIVEN DevGeoEncryptionService WHEN encrypt THEN 抛 EncryptionException', () {
      expect(
        () => service.encrypt('30.1234'),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('【SEC-2】GIVEN DevGeoEncryptionService WHEN decrypt THEN 抛 EncryptionException', () {
      expect(
        () => service.decrypt('any-ciphertext'),
        throwsA(isA<EncryptionException>()),
      );
    });
  });

  // -----------------------------------------------------------------------
  // ProdGeoEncryptionService — AES-256-GCM 格式验证
  // 使用 withKey 构造函数绕过 FlutterSecureStorage 平台依赖
  // -----------------------------------------------------------------------
  group('ProdGeoEncryptionService AES-256-GCM', () {
    late ProdGeoEncryptionService service;

    setUp(() {
      // 测试用固定密钥（256-bit）
      final key = encrypt_pkg.Key.fromUtf8('A1B2C3D4E5F6071829304050A1B2C3D4');
      service = ProdGeoEncryptionService.withKey(key);
    });

    test('【SEC-3】GIVEN 明文坐标 WHEN encrypt THEN 输出格式为 iv:authTag:ciphertext', () async {
      final cipherText = await service.encrypt('30.123456');

      // 格式: base64(IV):base64(authTag):base64(ciphertext)
      final parts = cipherText.split(':');
      expect(parts.length, 3, reason: '密文应为 iv:authTag:ciphertext 三段格式');

      // IV: 12 bytes → base64 编码
      final ivDecoded = base64Decode(parts[0]);
      expect(ivDecoded.length, 12, reason: 'GCM IV 应为 12 字节');

      // authTag: 16 bytes → base64 编码
      final tagDecoded = base64Decode(parts[1]);
      expect(tagDecoded.length, 16, reason: 'GCM authTag 应为 16 字节 (128-bit)');

      // ciphertext: 至少 1 字节
      final cipherDecoded = base64Decode(parts[2]);
      expect(cipherDecoded.isNotEmpty, true, reason: '密文不应为空');
    });

    test('【SEC-4】GIVEN 加密后密文 WHEN decrypt THEN 还原明文', () async {
      const plainText = '121.473701';
      final cipherText = await service.encrypt(plainText);
      final decrypted = await service.decrypt(cipherText);
      expect(decrypted, plainText);
    });

    test('【SEC-5】GIVEN 同一明文连续加密 WHEN 比较密文 THEN 每次不同（随机IV）', () async {
      const plainText = '30.123456';
      final cipher1 = await service.encrypt(plainText);
      final cipher2 = await service.encrypt(plainText);
      expect(cipher1, isNot(equals(cipher2)), reason: '随机 IV 应确保密文不同');
    });

    test('【SEC-6】GIVEN 损坏的密文 WHEN decrypt THEN 抛 EncryptionException', () async {
      expect(
        () => service.decrypt('invalid-not-base64:bad:data'),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('【SEC-7】GIVEN 格式错误的密文（缺段） WHEN decrypt THEN 抛 EncryptionException', () async {
      final cipherText = await service.encrypt('30.0');
      // 去掉最后一段
      final tampered = cipherText.split(':').sublist(0, 2).join(':');
      expect(
        () => service.decrypt(tampered),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('【SEC-8】GIVEN 篡改 authTag 的密文 WHEN decrypt THEN 抛 EncryptionException', () async {
      final cipherText = await service.encrypt('30.0');
      final parts = cipherText.split(':');
      // 篡改 authTag 的最后一个字节
      final tagBytes = base64Decode(parts[1]);
      tagBytes[tagBytes.length - 1] ^= 0xFF;
      parts[1] = base64Encode(tagBytes);
      final tampered = parts.join(':');
      expect(
        () => service.decrypt(tampered),
        throwsA(isA<EncryptionException>()),
      );
    });

    test('【SEC-9】GIVEN 中文明文 WHEN encrypt→decrypt THEN 还原', () async {
      const plainText = '上海市浦东新区';
      final cipherText = await service.encrypt(plainText);
      final decrypted = await service.decrypt(cipherText);
      expect(decrypted, plainText);
    });

    test('【SEC-10】GIVEN 多次加密解密 WHEN 循环100次 THEN 全部正确还原', () async {
      for (int i = 0; i < 100; i++) {
        final plainText = '${30.0 + i * 0.001}';
        final cipherText = await service.encrypt(plainText);
        final decrypted = await service.decrypt(cipherText);
        expect(decrypted, plainText, reason: '第 ${i + 1} 次加密解密失败');
      }
    });
  });
}
