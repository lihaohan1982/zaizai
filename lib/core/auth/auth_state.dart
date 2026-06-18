// lib/core/auth/auth_state.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 认证状态管理器
///
/// 负责 token/userId/nickname 的持久化（flutter_secure_storage），
/// 并提供当前用户信息的公开访问。
class AuthState extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();

  String? _token;
  String? _userId;
  String? _nickname;

  AuthState() {
    _loadFromStorage();
  }

  String? get token => _token;
  String? get currentUserId => _userId;
  String? get nickname => _nickname;
  bool get isLoggedIn => _token != null && _userId != null;

  Future<void> _loadFromStorage() async {
    try {
      _token = await _storage.read(key: 'auth_token');
      _userId = await _storage.read(key: 'user_id');
      _nickname = await _storage.read(key: 'nickname');
      notifyListeners();
    } catch (e) {
      debugPrint('[AuthState] 从 secure_storage 加载失败: $e');
    }
  }

  /// 登录成功后写入
  Future<void> login({
    required String token,
    required String userId,
    String? nickname,
  }) async {
    _token = token;
    _userId = userId;
    _nickname = nickname;

    await _storage.write(key: 'auth_token', value: token);
    await _storage.write(key: 'user_id', value: userId);
    if (nickname != null) {
      await _storage.write(key: 'nickname', value: nickname);
    }
    notifyListeners();
  }

  /// 登出
  Future<void> logout() async {
    _token = null;
    _userId = null;
    _nickname = null;
    await _storage.deleteAll();
    notifyListeners();
  }
}
