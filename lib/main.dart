import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/env_config.dart';
import 'core/monitoring/sentry_service.dart';
import 'core/privacy/privacy_fuse_controller.dart';
import 'core/providers.dart';
import 'features/chat/pages/add_friend_page.dart';
import 'features/chat/pages/interaction_sheet.dart';
import 'features/fence/pages/fence_event_history_page.dart';
import 'features/map/presentation/pages/empty_state_page.dart';
import 'features/profile/pages/privacy_settings_page.dart';
import 'demo/location_demo.dart';

void main() async {
  final mainStart = DateTime.now();

  // 在 runZonedGuarded 内部完成所有初始化
  await runZonedGuarded(
    () async {
      // ── 探针 ① 绑定初始化 ──
      debugPrint('[启动] ① WidgetsFlutterBinding.ensureInitialized 开始 ${DateTime.now()}');
      try {
        WidgetsFlutterBinding.ensureInitialized();
        debugPrint('[启动] ① 完成 (+${DateTime.now().difference(mainStart).inMilliseconds}ms)');
      } catch (e) {
        debugPrint('[启动] ① 异常: $e');
      }

      // Flutter 框架异常捕获
      FlutterError.onError = _handleFlutterError;

      // ── 探针 ② Hive 初始化（带 try/catch，失败不影响 runApp）──
      debugPrint('[启动] ② Hive.initFlutter 开始');
      try {
        await Hive.initFlutter();
        debugPrint('[启动] ② 完成 (+${DateTime.now().difference(mainStart).inMilliseconds}ms)');
      } catch (e) {
        debugPrint('[启动] ② 异常: $e — Hive 初始化失败，跳过继续启动');
      }

      // ── 探针 ③ 环境配置加载 ──
      debugPrint('[启动] ③ EnvConfig.load 开始');
      try {
        await EnvConfig.load();
      } catch (e) {
        debugPrint('[启动] ③ 异常: $e');
      }

      // ── 探针 ③.5 自动登录（开发环境）──
      debugPrint('[启动] ③.5 自动登录开始');
      try {
        await _ensureLoggedIn();
        debugPrint('[启动] ③.5 完成');
      } catch (e) {
        debugPrint('[启动] ③.5 异常: $e');
      }
      debugPrint('[启动] ③ 完成 (+${DateTime.now().difference(mainStart).inMilliseconds}ms)');

      // ── 探针 ④ Sentry 崩溃监控（带 5 秒超时保护）──
      debugPrint('[启动] ④ SentryService.initialize 开始');
      try {
        await SentryService.initialize().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('[启动] ④ Sentry 初始化超时(5s)，跳过继续启动');
          },
        );
      } catch (e) {
        debugPrint('[启动] ④ Sentry 异常: $e — 跳过继续启动');
      }
      debugPrint('[启动] ④ 完成 (+${DateTime.now().difference(mainStart).inMilliseconds}ms)');

      // ── 探针 ⑤ 启动 App（必须执行，否则白屏）──
      debugPrint('[启动] ⑤ runApp 开始 (+${DateTime.now().difference(mainStart).inMilliseconds}ms)');

      // 设置全局错误 Widget，防止瓦片加载等同步异常在生产环境上显示为红屏
      // 原来的红屏画面（"ClientException with SocketException"）会被这个替代
      ErrorWidget.builder = (FlutterErrorDetails details) {
        debugPrint('[错误瓦片] ${details.exception}');
        return Container(
          color: const Color(0xFFFF9800),
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: const Text(
            '瓦片加载异常\n（已捕获）',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14),
          ),
        );
      };

      runApp(const ProviderScope(child: MyApp()));
    },
    (error, stack) => _handleUncaughtError(error, stack),
  );
}

/// Flutter 框架异常处理器
///
/// 捕获 build/layout/paint 阶段的异常，避免 UI 白屏，并上报 Sentry。
void _handleFlutterError(FlutterErrorDetails details) {
  // 始终打印（开发阶段快速定位）
  FlutterError.dumpErrorToConsole(details);

  // [Phase 1] 上报 Sentry
  SentryService.captureException(
    details.exception,
    stackTrace: details.stack,
    hint: 'flutter_error',
    extra: {
      'library': details.library,
      'context': details.context?.toString(),
      'silent': details.silent,
    },
  );
}

/// 未捕获异常处理器（Dart 层 + 异步异常）
void _handleUncaughtError(Object error, StackTrace stack) {
  // 始终打印
  debugPrint('[UncaughtError] $error');
  debugPrint('$stack');

  // [Phase 1] 上报 Sentry
  SentryService.captureException(
    error,
    stackTrace: stack,
    hint: 'uncaught_error',
  );
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  /// 是否已完成定位环境检测（EmptyStatePage onReady 回调）
  bool _locationReady = false;

  @override
  Widget build(BuildContext context) {
    final messengerKey = ref.watch(scaffoldMessengerKeyProvider);
    final theme = ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      useMaterial3: true,
    );

    return MaterialApp(
      title: 'Location Chat',
      debugShowCheckedModeBanner: false,
      theme: theme,
      scaffoldMessengerKey: messengerKey,
      navigatorObservers: [SentryNavigatorObserver()],
      onGenerateRoute: _onGenerateRoute,
      home: _buildRootPage(),
      // 捕获所有未处理的 Flutter 异常，显示错误页面而非纯白
      builder: (context, child) => _ErrorBoundary(child: child),
    );
  }

  Widget _buildRootPage() {
    // 第一道门：EmptyStatePage 检测定位权限与服务状态
    // 权限通过后 → _InitializationRouter 检查围栏/隐私初始化
    if (!_locationReady) {
      return EmptyStatePage(
        onReady: () {
          setState(() => _locationReady = true);
        },
      );
    }
    return _InitializationRouter();
  }

  /// 应用路由契约
  ///
  /// 支持：
  ///   - /interaction/:friendId  → 好友互动页
  ///   - /privacy-settings       → 隐私与位置设置页
  ///   - /fence/:fenceId/events  → 围栏事件历史页
  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final name = settings.name;
    if (name == null) return null;

    // /add-friend
    if (name == '/add-friend') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const AddFriendPage(),
      );
    }

    // /interaction/:friendId
    if (name.startsWith('/interaction/')) {
      final friendId = name.substring('/interaction/'.length);
      if (friendId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => InteractionSheet(
            friendId: friendId,
            friendName: '好友',
            avatarUrl: '',
          ),
        );
      }
    }

    // /privacy-settings
    if (name == '/privacy-settings') {
      return MaterialPageRoute(
        settings: settings,
        builder: (_) => const PrivacySettingsPage(),
      );
    }

    // /fence/:fenceId/events
    if (name.startsWith('/fence/') && name.endsWith('/events')) {
      final prefix = '/fence/';
      final suffix = '/events';
      final fenceId = name.substring(prefix.length, name.length - suffix.length);
      if (fenceId.isNotEmpty) {
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => FenceEventHistoryPage(
            fenceId: fenceId,
            fenceName: fenceId == 'home' ? '家' : '围栏',
          ),
        );
      }
    }

    // 未知路由：返回一个空错误页，避免抛异常崩溃
    return MaterialPageRoute(
      settings: settings,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('页面未找到')),
        body: Center(child: Text('未知路由: $name')),
      ),
    );
  }
}

/// 围栏初始化路由器
///
/// 监听 PrivacyFuseController 的 initStatus，
/// 根据 UI 路由契约（P1-6）决定展示哪个页面。
class _InitializationRouter extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return privacyAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('初始化失败: $e', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(privacyFuseControllerProvider),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
      data: (controller) => ListenableBuilder(
        listenable: Listenable.merge([
          controller.initStatusNotifier,
        ]),
        builder: (_, __) {
          switch (controller.initStatusNotifier.value) {
            case InitializationStatus.loading:
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );

            case InitializationStatus.failed:
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('围栏数据加载失败'),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          controller.initialize('home');
                        },
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );

            case InitializationStatus.empty:
              // MVP 期间：空状态也进入地图页面（后续改为强制创建围栏）
              // 用户可在地图页手动创建围栏
              return const LocationDemoPage();

            case InitializationStatus.success:
              return const LocationDemoPage();
          }
        },
      ),
    );
  }
}

/// 全局错误边界
///
/// 捕获 build/layout 阶段的异常，显示红色错误页面而非纯白屏。
/// 配合 builder 参数使用：MaterialApp(builder: (ctx, child) => _ErrorBoundary(child: child))
class _ErrorBoundary extends StatelessWidget {
  final Widget? child;

  const _ErrorBoundary({super.key, this.child});

  @override
  Widget build(BuildContext context) {
    return FlutterError.onError != null
        ? _ErrorBoundaryWidget(child: child)
        : (child ?? const SizedBox.shrink());
  }
}

class _ErrorBoundaryWidget extends StatefulWidget {
  final Widget? child;
  const _ErrorBoundaryWidget({super.key, this.child});

  @override
  State<_ErrorBoundaryWidget> createState() => _ErrorBoundaryWidgetState();
}

class _ErrorBoundaryWidgetState extends State<_ErrorBoundaryWidget> {
  void Function(FlutterErrorDetails)? _originalHandler;

  @override
  void initState() {
    super.initState();
    _originalHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      // 调用原始 handler 保持 Sentry 上报
      _originalHandler?.call(details);
      // 同时刷新 UI 显示错误
      if (mounted) {
        setState(() {
          _lastError = '${details.exception}';
          debugPrint('[ErrorBoundary] ${details.exception}');
          debugPrint('[ErrorBoundary] ${details.stack}');
        });
      }
    };
  }

  String? _lastError;

  @override
  void dispose() {
    // 恢复原始 handler
    FlutterError.onError = _originalHandler;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_lastError != null) {
      return Material(
        color: Colors.red.shade50,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 64, color: Colors.red),
                  const SizedBox(height: 16),
                  const Text(
                    '应用遇到错误',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _lastError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red, fontSize: 14),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => setState(() => _lastError = null),
                    child: const Text('清除错误，继续'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return widget.child ?? const SizedBox.shrink();
  }
}

/// 自动登录函数（开发环境）
///
/// 使用测试账号 13800138000/123456 登录，返回已认证的 Dio 实例
Future<Dio> _ensureLoggedIn() async {
  final storage = const FlutterSecureStorage();
  
  // 检查是否已有 token
  String? token = await storage.read(key: 'auth_token');
  if (token != null && token.isNotEmpty) {
    debugPrint('[自动登录] 已有 token，跳过登录');
    final dio = Dio(BaseOptions(
      baseUrl: EnvConfig.apiBaseUrl,
      headers: {'Authorization': 'Bearer $token'},
    ));
    return dio;
  }
  
  // 没有则登录
  debugPrint('[自动登录] 使用测试账号登录...');
  final dio = Dio(BaseOptions(baseUrl: EnvConfig.apiBaseUrl));
  
  try {
    final response = await dio.get(
      '/api/auth/login',
      queryParameters: {'phone': '13800138000', 'code': '123456'},
    );
    
    final data = response.data as Map<String, dynamic>;
    if (data['code'] == 0) {
      final tokenData = data['data'] as Map<String, dynamic>;
      token = tokenData['token'] as String;
      final user = tokenData['user'] as Map<String, dynamic>;
      final userId = user['id'] as String;
      final nickname = user['nickname'] as String?;
      
      await storage.write(key: 'auth_token', value: token);
      await storage.write(key: 'user_id', value: userId);
      if (nickname != null) {
        await storage.write(key: 'nickname', value: nickname);
      }
      
      debugPrint('[自动登录] 登录成功: token=$token, userId=$userId, nickname=$nickname');
      
      // 返回带认证的 Dio
      return Dio(BaseOptions(
        baseUrl: EnvConfig.apiBaseUrl,
        headers: {'Authorization': 'Bearer $token'},
      ));
    } else {
      throw Exception('登录失败: ${data['message']}');
    }
  } catch (e) {
    debugPrint('[自动登录] 异常: $e');
    rethrow;
  }
}
