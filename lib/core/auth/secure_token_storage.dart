import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:meta/meta.dart';

import 'token_storage.dart';

/// 生产级 Token 存储（iOS Keychain / Android Keystore）
@immutable
class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage _storage;

  static const _tokenKey = 'auth_token';

  const SecureTokenStorage([this._storage = const FlutterSecureStorage()]);

  @override
  Future<String?> readToken() => _storage.read(key: _tokenKey);

  @override
  Future<void> writeToken(String token) => _storage.write(key: _tokenKey, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _tokenKey);
}
