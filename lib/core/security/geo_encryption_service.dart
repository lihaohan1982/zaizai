// lib/core/security/geo_encryption_service.dart
//
// 地理坐标加密服务
// - DevGeoEncryptionService: 加密失败抛异常（禁止生产使用）
// - ProdGeoEncryptionService: AES-256-GCM 真实加密，密钥存储于设备安全区域
//
// 加密格式: base64(IV[12]) : base64(authTag[16]) : base64(ciphertext)
// GCM IV 固定 12 字节（NIST SP 800-38D 推荐），authTag 16 字节 (128-bit)

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

// ---------------------------------------------------------------------------

/// 地理位置加密服务抽象接口
abstract class GeoEncryptionService {
  /// 将明文加密为密文字符串
  Future<String> encrypt(String plainText);

  /// 将密文字符串解密为明文
  Future<String> decrypt(String cipherText);
}

// ---------------------------------------------------------------------------

const String _keyStorageKey = 'geo_encryption_key_v2';

/// 错误类型
class EncryptionException implements Exception {
  final String message;
  EncryptionException(this.message);
  @override
  String toString() => 'EncryptionException: $message';
}

// ---------------------------------------------------------------------------

/// 开发用服务 — 加密/解密均抛异常，禁止在生产环境使用
///
/// 安全红线：Dev 实现不得透传明文。若误用此服务，encrypt/decrypt
/// 立即抛出 EncryptionException，强制开发者切换到 ProdGeoEncryptionService。
class DevGeoEncryptionService implements GeoEncryptionService {
  @override
  Future<String> encrypt(String plainText) async {
    throw EncryptionException(
      'DevGeoEncryptionService.encrypt() must not be used in production. '
      'Switch to ProdGeoEncryptionService to enable AES-256-GCM encryption.',
    );
  }

  @override
  Future<String> decrypt(String cipherText) async {
    throw EncryptionException(
      'DevGeoEncryptionService.decrypt() must not be used in production. '
      'Switch to ProdGeoEncryptionService to enable AES-256-GCM decryption.',
    );
  }
}

// ---------------------------------------------------------------------------

/// 生产用 AES-256-GCM 加密服务
///
/// - 密钥从设备安全存储（iOS Keychain / Android Keystore）读取
/// - 首次启动时自动生成 256-bit 随机密钥并安全存储
/// - GCM 提供 机密性 + 完整性（authTag 128-bit）
/// - 密钥丢失或损坏时解密失败抛异常，上层可优雅降级
///
/// 加密格式: base64(IV[12]) : base64(authTag[16]) : base64(ciphertext)
class ProdGeoEncryptionService implements GeoEncryptionService {
  final FlutterSecureStorage _secureStorage;

  encrypt_pkg.Key? _cachedKey;
  final encrypt_pkg.Key? _preloadedKey;

  /// GCM IV 长度（NIST SP 800-38D 推荐 12 字节）
  static const int _gcmIvLength = 12;

  /// GCM auth tag 长度（128-bit = 16 字节）
  static const int _gcmTagLength = 16;

  /// 生产构造函数：密钥从 FlutterSecureStorage 懒加载
  ProdGeoEncryptionService({FlutterSecureStorage? secureStorage})
      : _secureStorage = secureStorage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock_this_device,
              ),
            ),
        _preloadedKey = null;

  /// 测试构造函数：直接注入密钥，绕过 SecureStorage
  ///
  /// ⚠️ 仅用于单元测试，生产环境必须使用默认构造函数。
  ProdGeoEncryptionService.withKey(encrypt_pkg.Key key)
      : _secureStorage = const FlutterSecureStorage(),
        _preloadedKey = key;

  // -------------------------------------------------------------------------

  /// 确保密钥已加载；首次启动时自动生成并持久化到设备安全存储
  Future<void> _ensureKey() async {
    if (_cachedKey != null) return;

    // 测试模式：直接使用注入的密钥
    if (_preloadedKey != null) {
      _cachedKey = _preloadedKey;
      return;
    }

    String? storedKey = await _secureStorage.read(key: _keyStorageKey);

    if (storedKey == null) {
      // 首次启动：生成 32 字节 (256-bit) 随机密钥
      final random = Random.secure();
      final keyBytes = List<int>.generate(32, (_) => random.nextInt(256));
      storedKey = base64Encode(keyBytes);
      await _secureStorage.write(key: _keyStorageKey, value: storedKey);
    }

    _cachedKey = encrypt_pkg.Key.fromBase64(storedKey);
  }

  // -------------------------------------------------------------------------

  @override
  Future<String> encrypt(String plainText) async {
    await _ensureKey();

    try {
      // 生成随机 IV（12 bytes for GCM）
      final ivBytes = Uint8List.fromList(
        List.generate(_gcmIvLength, (_) => Random.secure().nextInt(256)),
      );
      final iv = encrypt_pkg.IV(ivBytes);

      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(_cachedKey!, mode: encrypt_pkg.AESMode.gcm),
      );

      final encrypted = encrypter.encrypt(plainText, iv: iv);

      // GCM 加密结果: encrypted.bytes 包含 ciphertext + authTag (尾部 16 bytes)
      final allBytes = encrypted.bytes;
      final cipherLen = allBytes.length - _gcmTagLength;
      if (cipherLen < 0) {
        throw EncryptionException('GCM encryption produced invalid output');
      }

      final ciphertextBytes = allBytes.sublist(0, cipherLen);
      final authTagBytes = allBytes.sublist(cipherLen);

      // 格式: base64(IV) : base64(authTag) : base64(ciphertext)
      return '${base64Encode(ivBytes)}:${base64Encode(authTagBytes)}:${base64Encode(ciphertextBytes)}';
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('AES-256-GCM encryption failed: $e');
    }
  }

  // -------------------------------------------------------------------------

  @override
  Future<String> decrypt(String cipherText) async {
    await _ensureKey();

    try {
      // 解析格式: base64(IV) : base64(authTag) : base64(ciphertext)
      final parts = cipherText.split(':');
      if (parts.length != 3) {
        throw EncryptionException(
          'Invalid ciphertext format: expected "iv:authTag:ciphertext", '
          'got ${parts.length} parts',
        );
      }

      final ivBytes = base64Decode(parts[0]);
      final authTagBytes = base64Decode(parts[1]);
      final ciphertextBytes = base64Decode(parts[2]);

      if (ivBytes.length != _gcmIvLength) {
        throw EncryptionException(
          'Invalid IV length: expected $_gcmIvLength, got ${ivBytes.length}',
        );
      }
      if (authTagBytes.length != _gcmTagLength) {
        throw EncryptionException(
          'Invalid authTag length: expected $_gcmTagLength, got ${authTagBytes.length}',
        );
      }

      final iv = encrypt_pkg.IV(ivBytes);

      // GCM 解密: 需要将 ciphertext + authTag 拼接后传入
      final combined = Uint8List(ciphertextBytes.length + authTagBytes.length);
      combined.setRange(0, ciphertextBytes.length, ciphertextBytes);
      combined.setRange(ciphertextBytes.length, combined.length, authTagBytes);

      final encrypted = encrypt_pkg.Encrypted(combined);

      final encrypter = encrypt_pkg.Encrypter(
        encrypt_pkg.AES(_cachedKey!, mode: encrypt_pkg.AESMode.gcm),
      );

      return encrypter.decrypt(encrypted, iv: iv);
    } catch (e) {
      if (e is EncryptionException) rethrow;
      throw EncryptionException('AES-256-GCM decryption failed: $e');
    }
  }
}
