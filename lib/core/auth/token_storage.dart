/// Token 持久化抽象层
///
/// 阶段三安全整改：将 Token 存储与具体实现解耦，
/// 生产环境使用 FlutterSecureStorage，测试环境可注入 Fake 实现。
abstract class TokenStorage {
  Future<String?> readToken();
  Future<void> writeToken(String token);
  Future<void> deleteToken();
}
