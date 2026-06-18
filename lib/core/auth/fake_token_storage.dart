import 'token_storage.dart';

/// 测试用 Fake Token 存储（内存实现，无平台通道依赖）
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> writeToken(String token) async => _token = token;

  @override
  Future<void> deleteToken() async => _token = null;
}
