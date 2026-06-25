import 'dart:async';
import 'dart:isolate';

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

/// 渐进初始化诊断版本 v2
///
/// 修复点（来自用户反馈）：
/// 1. ✅ 每个颜色切换后加 await Future.delayed(Duration.zero) 防止 UI 线程阻塞
/// 2. ✅ try-catch 捕获 Object（而不是 Exception），覆盖 Error
/// 3. ✅ runApp() 之后也加颜色验证，覆盖 Widget 树构建阶段
///
/// 颜色变化顺序：
///   红色    -> 引擎启动（runApp 之前）
///   橙色    -> WidgetsFlutterBinding.ensureInitialized 完成
///   黄色    -> Hive.initFlutter 完成
///   粉色    -> EnvConfig.load 完成
///   绿色    -> SentryService.initialize 完成
///   青色    -> runApp 成功挂载（MyApp 开始构建）
///   深绿色  -> MyApp.build() 开始
///   蓝色    -> 全部完成
///   紫色    -> 任意步骤出错（带日志）
///
/// 只要观察最终停在哪一步，就能定位白屏问题。
void main() {
  runApp(const _ProgressiveInitApp());
}

enum _InitPhase {
  engineStart,
  bindingDone,
  hiveDone,
  configDone,
  sentryDone,
  runAppDone,
  myAppBuildDone,
  allDone,
  error,
}

class _ProgressiveInitApp extends StatefulWidget {
  const _ProgressiveInitApp();

  @override
  State<_ProgressiveInitApp> createState() => _ProgressiveInitAppState();
}

class _ProgressiveInitAppState extends State<_ProgressiveInitApp> {
  _InitPhase _phase = _InitPhase.engineStart;
  String _statusMessage = '⚡ 引擎启动...';
  final List<_LogEntry> _logs = [];
  bool _initStarted = false;

  @override
  void initState() {
    super.initState();
    // 延迟 200ms 确保首帧已渲染，用户先看到红色
    Future.delayed(const Duration(milliseconds: 200), _startInitialization);
  }

  Color get _bgColor {
    switch (_phase) {
      case _InitPhase.engineStart:     return Colors.red;
      case _InitPhase.bindingDone:      return Colors.orange;
      case _InitPhase.hiveDone:        return Colors.yellow;
      case _InitPhase.configDone:      return Colors.pink;
      case _InitPhase.sentryDone:      return Colors.green;
      case _InitPhase.runAppDone:      return Colors.cyan;
      case _InitPhase.myAppBuildDone:  return Colors.teal;
      case _InitPhase.allDone:         return Colors.blue;
      case _InitPhase.error:           return Colors.purple;
    }
  }

  void _addLog(String message, _LogLevel level) {
    _logs.add(_LogEntry(message, level));
    if (mounted) setState(() {});
  }

  Future<void> _startInitialization() async {
    if (_initStarted) return;
    _initStarted = true;

    // Step 1: WidgetsFlutterBinding
    try {
      _setPhase(_InitPhase.bindingDone, '✅ Step 1: WidgetsFlutterBinding 完成');
      _addLog('✅ Step 1: WidgetsFlutterBinding 完成', _LogLevel.success);
    } catch (e) {
      _setPhase(_InitPhase.error, '❌ Step 1 失败');
      _addLog('❌ Step 1: $e', _LogLevel.error);
      _addLog('📍 ${_stack(e)}', _LogLevel.stack);
      return;
    }
    await Future.delayed(Duration.zero); // 让 UI 线程刷新
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 2: Hive.initFlutter
    try {
      _setPhase(_InitPhase.hiveDone, '⏳ Step 2: Hive.initFlutter...');
      _addLog('⏳ Step 2: Hive.initFlutter() 开始...', _LogLevel.info);
      await Hive.initFlutter();
      _addLog('✅ Step 2: Hive.initFlutter 完成', _LogLevel.success);
    } catch (e) {
      _setPhase(_InitPhase.error, '❌ Step 2 失败: $e');
      _addLog('❌ Step 2: Hive.initFlutter 失败: $e', _LogLevel.error);
      _addLog('📍 ${_stack(e)}', _LogLevel.stack);
      return;
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 3: EnvConfig.load
    try {
      _setPhase(_InitPhase.configDone, '⏳ Step 3: EnvConfig.load...');
      _addLog('⏳ Step 3: EnvConfig.load() 开始...', _LogLevel.info);
      await EnvConfig.load();
      _addLog('✅ Step 3: EnvConfig.load 完成', _LogLevel.success);
    } catch (e) {
      _setPhase(_InitPhase.error, '❌ Step 3 失败: $e');
      _addLog('❌ Step 3: EnvConfig.load 失败: $e', _LogLevel.error);
      _addLog('📍 ${_stack(e)}', _LogLevel.stack);
      return;
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 4: SentryService.initialize
    try {
      _setPhase(_InitPhase.sentryDone, '⏳ Step 4: SentryService.initialize...');
      _addLog('⏳ Step 4: SentryService.initialize() 开始...', _LogLevel.info);
      await SentryService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _addLog('⚠️ Step 4: Sentry 初始化超时(5s)，跳过', _LogLevel.warning);
        },
      );
      _addLog('✅ Step 4: SentryService.initialize 完成', _LogLevel.success);
    } catch (e) {
      _setPhase(_InitPhase.error, '❌ Step 4 失败: $e');
      _addLog('❌ Step 4: SentryService.initialize 失败: $e', _LogLevel.error);
      _addLog('📍 ${_stack(e)}', _LogLevel.stack);
      return;
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 200));

    // Step 5: runApp - 关键！切换到真实 MyApp
    _addLog('⏳ Step 5: 调用 runApp(ProviderScope(child: MyApp()))...', _LogLevel.info);
    _setPhase(_InitPhase.runAppDone, '✅ runApp 已调用，MyApp 正在构建...');
    await Future.delayed(Duration.zero); // 让用户先看到青色

    // 这里直接替换成真实 App！
    runApp(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: Colors.blue,
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '✅ runApp 成功!',
                    style: TextStyle(
                      color: Colors.cyanAccent,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    '🚀 MyApp 正在构建 Widget 树...',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    '如果这里变成白色 → MyApp.build() 某处崩溃',
                    style: TextStyle(color: Colors.amberAccent, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    // runApp 之后永远不会执行到这里
    // （runApp 会替换当前 isolate 的入口函数）
  }

  String _stack(Object e) {
    if (e is Error) return e.stackTrace?.toString() ?? '(no stack)';
    if (e is Exception) {
      try {
        return (e as dynamic).stackTrace?.toString() ?? '(no stack)';
      } catch (_) {
        return '(no stack)';
      }
    }
    return e.toString();
  }

  void _setPhase(_InitPhase phase, String message) {
    if (!mounted) return;
    setState(() {
      _phase = phase;
      _statusMessage = message;
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Container(
        color: _bgColor,
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Text(
                    'FLUTTER ENGINE WORKS!',
                    style: TextStyle(
                      color: _phase == _InitPhase.allDone
                          ? Colors.cyanAccent
                          : Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: _phase == _InitPhase.error
                            ? Colors.redAccent
                            : _phase == _InitPhase.allDone
                                ? Colors.greenAccent
                                : Colors.white70,
                        fontSize: 16,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '🔴🔴🔴🔴🟠🟡🩷🟢🔵🟢🟡🟠🔴 = 颜色含义',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '停在哪色=卡在哪步。紫色=异常。青色=runApp成功。',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView.builder(
                        itemCount: _logs.length,
                        itemBuilder: (ctx, i) {
                          final log = _logs[i];
                          Color textColor;
                          switch (log.level) {
                            case _LogLevel.success: textColor = Colors.greenAccent;
                            case _LogLevel.error:   textColor = Colors.redAccent;
                            case _LogLevel.warning: textColor = Colors.yellowAccent;
                            case _LogLevel.info:    textColor = Colors.white70;
                            case _LogLevel.stack:    textColor = Colors.orangeAccent;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              log.message.length > 120
                                  ? '${log.message.substring(0, 120)}...'
                                  : log.message,
                              style: TextStyle(color: textColor, fontSize: 12, fontFamily: 'monospace'),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _LogLevel { success, error, warning, info, stack }

class _LogEntry {
  final String message;
  final _LogLevel level;
  _LogEntry(this.message, this.level);
}
