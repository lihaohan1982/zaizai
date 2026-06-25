import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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

/// v4 - 错误日志强化版
///
/// 已知：v3 显示紫色崩溃，说明 MyApp 渲染时抛异常
/// 目标：把异常完整打在屏幕上
void main() {
  // 全局错误捕获
  FlutterError.onError = (details) {
    debugPrint('=== FlutterError ===');
    debugPrint('${details.exception}');
    debugPrint('${details.stack}');
  };

  runZonedGuarded(
    () => runApp(const _InitApp()),
    (error, stack) {
      debugPrint('=== Zone Error ===');
      debugPrint('$error');
      debugPrint('$stack');
    },
  );
}

class _InitApp extends StatefulWidget {
  const _InitApp();
  @override
  State<_InitApp> createState() => _InitAppState();
}

class _InitAppState extends State<_InitApp> {
  String? _error;
  String? _stack;
  bool _initDone = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      _addLog('⏳ WidgetsFlutterBinding...');
      WidgetsFlutterBinding.ensureInitialized();
      _addLog('✅ WidgetsFlutterBinding 完成');
      await Future.delayed(Duration.zero);

      _addLog('⏳ Hive.initFlutter()...');
      await Hive.initFlutter();
      _addLog('✅ Hive 完成');
      await Future.delayed(Duration.zero);

      _addLog('⏳ EnvConfig.load()...');
      await EnvConfig.load();
      _addLog('✅ EnvConfig 完成');
      await Future.delayed(Duration.zero);

      _addLog('⏳ SentryService.initialize()...');
      try {
        await SentryService.initialize().timeout(const Duration(seconds: 5));
        _addLog('✅ Sentry 完成');
      } catch (e) {
        _addLog('⚠️ Sentry 超时，跳过');
      }
      await Future.delayed(Duration.zero);

      _addLog('🚀 初始化完成，启动 MyApp...');
      setState(() => _initDone = true);
    } catch (e, s) {
      _addLog('❌ 初始化失败: $e');
      setState(() {
        _error = e.toString();
        _stack = s.toString();
      });
    }
  }

  void _addLog(String msg) {
    _logs.add(msg);
    debugPrint('[v4] $msg');
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorScreen(title: '初始化失败', error: _error!, stack: _stack, logs: _logs);
    }

    if (!_initDone) {
      return _LoadingScreen(logs: _logs);
    }

    // 初始化成功 → 启动真实 MyApp
    return ProviderScope(
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _MyAppWithErrorCatch(),
      ),
    );
  }
}

/// 带错误捕获的 MyApp
class _MyAppWithErrorCatch extends StatefulWidget {
  @override
  State<_MyAppWithErrorCatch> createState() => _MyAppWithErrorCatchState();
}

class _MyAppWithErrorCatchState extends State<_MyAppWithErrorCatch> {
  Object? _error;
  StackTrace? _stack;
  bool _caught = false;

  @override
  void initState() {
    super.initState();
    // 捕获 build 期间错误
    FlutterError.onError = (details) {
      if (!_caught) {
        _caught = true;
        debugPrint('=== MyApp Build Error ===');
        debugPrint('${details.exception}');
        debugPrint('${details.stack}');
        if (mounted) {
          setState(() {
            _error = details.exception;
            _stack = details.stack;
          });
        }
      }
    };
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _ErrorScreen(
        title: 'MyApp 渲染失败',
        error: _error.toString(),
        stack: _stack?.toString(),
        logs: [],
      );
    }

    try {
      return _buildRealApp();
    } catch (e, s) {
      debugPrint('=== MyApp.build() Exception ===');
      debugPrint('$e');
      debugPrint('$s');
      return _ErrorScreen(title: 'MyApp.build() 异常', error: e.toString(), stack: s.toString(), logs: []);
    }
  }

  Widget _buildRealApp() {
    // 逐步构建，每一步单独 try
    return Scaffold(
      body: _TestStep(
        stepName: 'PrivacyFuseControllerProvider',
        builder: (ctx) => Consumer(
          builder: (ctx, ref, _) {
            final asyncCtrl = ref.watch(privacyFuseControllerProvider);
            return asyncCtrl.when(
              loading: () => _StepWidget('⏳ PrivacyFuseController 加载中...', Colors.cyan),
              error: (e, s) => _StepWidget('❌ PrivacyFuseController 失败: $e', Colors.red, s.toString()),
              data: (ctrl) => _TestStep(
                stepName: 'EmptyStatePage',
                builder: (ctx) => EmptyStatePage(
                  onReady: () {
                    debugPrint('✅ EmptyStatePage onReady');
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// 测试步骤包装器
class _TestStep extends StatelessWidget {
  final String stepName;
  final WidgetBuilder builder;

  const _TestStep({required this.stepName, required this.builder});

  @override
  Widget build(BuildContext context) {
    debugPrint('[v4] 构建步骤: $stepName');
    try {
      return builder(context);
    } catch (e, s) {
      debugPrint('[v4] 步骤失败: $stepName → $e');
      return _StepWidget('❌ $stepName 失败', Colors.red, '$e\n\n$s');
    }
  }
}

class _StepWidget extends StatelessWidget {
  final String message;
  final Color bg;
  final String? details;

  const _StepWidget(this.message, this.bg, [this.details]);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: bg,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
              if (details != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    details!,
                    style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 加载界面
class _LoadingScreen extends StatelessWidget {
  final List<String> logs;
  const _LoadingScreen({required this.logs});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.blue,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text('⏳ 初始化中...', style: TextStyle(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.all(10),
                  child: ListView.builder(
                    itemCount: logs.length,
                    itemBuilder: (_, i) {
                      final log = logs[i];
                      Color c = Colors.white70;
                      if (log.startsWith('✅')) c = Colors.greenAccent;
                      if (log.startsWith('❌')) c = Colors.redAccent;
                      if (log.startsWith('⚠️')) c = Colors.yellowAccent;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(log, style: TextStyle(color: c, fontSize: 12, fontFamily: 'monospace')),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 错误界面
class _ErrorScreen extends StatelessWidget {
  final String title;
  final String error;
  final String? stack;
  final List<String> logs;

  const _ErrorScreen({
    required this.title,
    required this.error,
    this.stack,
    this.logs = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.purple,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                child: SelectableText(
                  error,
                  style: const TextStyle(color: Colors.redAccent, fontFamily: 'monospace', fontSize: 14),
                ),
              ),
              if (stack != null) ...[
                const SizedBox(height: 16),
                const Text('堆栈:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  child: SelectableText(
                    stack!.split('\n').take(30).join('\n'),
                    style: const TextStyle(color: Colors.orangeAccent, fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ],
              if (logs.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text('日志:', style: TextStyle(color: Colors.white70, fontSize: 14)),
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(8)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: logs.map((l) {
                      Color c = Colors.white70;
                      if (l.startsWith('✅')) c = Colors.greenAccent;
                      if (l.startsWith('❌')) c = Colors.redAccent;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 1),
                        child: Text(l, style: TextStyle(color: c, fontSize: 11, fontFamily: 'monospace')),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
