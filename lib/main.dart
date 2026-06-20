import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import 'core/config/env_config.dart';
import 'core/monitoring/sentry_service.dart';
import 'core/privacy/privacy_fuse_controller.dart';
import 'core/providers.dart';
import 'features/chat/pages/interaction_sheet.dart';
import 'features/fence/pages/fence_event_history_page.dart';
import 'features/map/presentation/pages/empty_state_page.dart';
import 'features/profile/pages/privacy_settings_page.dart';
import 'demo/location_demo.dart';

void main() async {
  // ① 在 runZonedGuarded 内部完成所有初始化，同一 zone
  await runZonedGuarded(
    () async {
      // 绑定初始化（必须在任何 Flutter API 之前）
      WidgetsFlutterBinding.ensureInitialized();

      // Flutter 框架异常捕获
      FlutterError.onError = _handleFlutterError;

      // Hive + 环境配置
      await Hive.initFlutter();
      await EnvConfig.load();

      // Sentry 崩溃监控（Phase 1）
      await SentryService.initialize();

      // 启动 App
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
    );
  }

  Widget _buildRootPage() {
    // 阶段 1：定位环境检测（权限 + 定位开关）
    if (!_locationReady) {
      return EmptyStatePage(
        onReady: () {
          if (mounted) setState(() => _locationReady = true);
        },
      );
    }

    // 阶段 2：围栏初始化 → 决定显示引导页还是地图
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
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add_location_alt, size: 64, color: Colors.blue),
                      const SizedBox(height: 16),
                      const Text(
                        '创建你的第一个围栏',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      const Text('设置家或公司，开启位置共享'),
                      const SizedBox(height: 32),
                      FilledButton.icon(
                        onPressed: () {
                          // TODO: 跳转到围栏创建页面
                          debugPrint('TODO: Navigate to FenceSetupPage');
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('创建围栏'),
                      ),
                    ],
                  ),
                ),
              );

            case InitializationStatus.success:
              return const LocationDemoPage();
          }
        },
      ),
    );
  }
}
