import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// 环境配置加载器与协议强校验
///
/// 阶段三安全整改：
///   - 所有服务端 URL 必须从 .env 读取，禁止硬编码
///   - 生产环境（production）强制要求 https:// / wss://
///   - 开发环境允许 http:// / ws://，但会打印警告
class EnvConfig {
  EnvConfig._();

  static bool _loaded = false;

  static String get apiBaseUrl => _get('API_BASE_URL');
  static String get wsBaseUrl => _get('WS_BASE_URL');
  static String get amapApiKey => _get('AMAP_API_KEY');
  static String get appEnv => _get('APP_ENV');

  static bool get isProduction => appEnv.toLowerCase() == 'production';
  static bool get isDevelopment => appEnv.toLowerCase() == 'development';

  /// 必须在 main() 中调用 dotenv.load() 之后才能访问
  static Future<void> load() async {
    if (_loaded) return;
    await dotenv.load(fileName: '.env');
    _loaded = true;
    _validate();
  }

  /// 测试兜底值（单元测试不加载 .env 时使用，避免直接崩溃）
  static final Map<String, String> _fallbacks = {
    'API_BASE_URL': 'http://localhost:3001/api',
    'WS_BASE_URL': 'ws://localhost:3001/ws',
    'AMAP_API_KEY': 'TEST_AMAP_KEY',
    'APP_ENV': 'development',
  };

  static String _get(String key) {
    final value = dotenv.env[key] ?? _fallbacks[key];
    if (value == null || value.isEmpty) {
      throw StateError(
        '[EnvConfig] 环境变量 $key 未设置。请复制 .env.example 为 .env 并填写。',
      );
    }
    return value;
  }

  /// 协议强校验：生产环境仅允许 HTTPS / WSS
  static void _validate() {
    if (isProduction) {
      if (!apiBaseUrl.startsWith('https://')) {
        throw StateError(
          '[EnvConfig] 生产环境 API_BASE_URL 必须使用 https://，当前: $apiBaseUrl',
        );
      }
      if (!wsBaseUrl.startsWith('wss://')) {
        throw StateError(
          '[EnvConfig] 生产环境 WS_BASE_URL 必须使用 wss://，当前: $wsBaseUrl',
        );
      }
    }

    // 非生产环境若使用明文协议，给出严重警告
    if (!isProduction) {
      if (apiBaseUrl.startsWith('http://')) {
        debugPrint('[EnvConfig] ⚠️ 警告：API 使用明文 http://，仅限本地开发');
      }
      if (wsBaseUrl.startsWith('ws://')) {
        debugPrint('[EnvConfig] ⚠️ 警告：WebSocket 使用明文 ws://，仅限本地开发');
      }
    }
  }
}
