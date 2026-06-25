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

/// 渐进初始化诊断版本 v3 - MyApp 分步验证
///
/// 已知情况：
///   ✅ Flutter 引擎正常
///   ✅ Step 1-4（初始化）全部成功
///   ✅ runApp() 被调用了
///   ❓ MyApp Widget 树构建 → 白屏
///
/// 颜色含义：
///   🔴 引擎启动 -> 🟠 binding -> 🟡 Hive -> 🩷 config -> 🟢 Sentry
///   🔵 MyApp 开始构建 -> 🟢 深绿 = ProviderScope 完成
///   🟡 黄 = MaterialApp 壳完成 -> 🩷 粉 = MyApp 状态初始化
///   🟢 绿 = MyApp.build() 开始 -> 🔵 蓝 = Scaffold 壳完成
///   深蓝 = EmptyStatePage 挂载中 -> 🟣 紫 = 失败
///
/// 安装后：等 10 秒，如果变成紫色，看日志定位。
///         如果停在某色超过 10 秒，该色就是卡住点。
void main() {
  runApp(const _ProgressiveInitApp());
}

enum _Phase {
  engineStart,
  bindingDone,
  hiveDone,
  configDone,
  sentryDone,
  myAppStart,
  providerScopeDone,
  materialAppDone,
  myAppStateDone,
  myAppBuildStart,
  scaffoldDone,
  emptyStateMounting,
  allDone,
  error,
}

class _ProgressiveInitApp extends StatefulWidget {
  const _ProgressiveInitApp();

  @override
  State<_ProgressiveInitApp> createState() => _ProgressiveInitAppState();
}

class _ProgressiveInitAppState extends State<_ProgressiveInitApp> {
  _Phase _phase = _Phase.engineStart;
  String _status = '⚡ 引擎启动...';
  final List<String> _logs = [];
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 100), _init);
  }

  Color get _bgColor {
    switch (_phase) {
      case _Phase.engineStart:        return Colors.red;
      case _Phase.bindingDone:        return Colors.orange;
      case _Phase.hiveDone:           return Colors.yellow;
      case _Phase.configDone:         return Colors.pink;
      case _Phase.sentryDone:         return Colors.green;
      case _Phase.myAppStart:         return Colors.cyan;
      case _Phase.providerScopeDone:   return Colors.teal;
      case _Phase.materialAppDone:    return Colors.lime;
      case _Phase.myAppStateDone:     return Colors.deepOrange;
      case _Phase.myAppBuildStart:    return Colors.blueGrey;
      case _Phase.scaffoldDone:       return Colors.indigo;
      case _Phase.emptyStateMounting: return Colors.blue;
      case _Phase.allDone:            return Colors.blue;
      case _Phase.error:              return Colors.purple;
    }
  }

  void _log(String msg) {
    _logs.add(msg);
    if (mounted) setState(() {});
    debugPrint('[诊断] $msg');
  }

  void _set(_Phase p, String status) {
    if (!mounted) return;
    setState(() {
      _phase = p;
      _status = status;
    });
  }

  Future<void> _init() async {
    // Step 1: binding
    _set(_Phase.bindingDone, '✅ Step 1: WidgetsFlutterBinding');
    _log('✅ Step 1: WidgetsFlutterBinding 完成');
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 2: Hive
    try {
      _set(_Phase.hiveDone, '⏳ Step 2: Hive...');
      _log('⏳ Step 2: Hive.initFlutter()...');
      await Hive.initFlutter();
      _log('✅ Step 2: Hive 完成');
    } catch (e, s) {
      _log('❌ Step 2 失败: $e');
      _log('📍 $s');
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 3: EnvConfig
    try {
      _set(_Phase.configDone, '⏳ Step 3: EnvConfig...');
      _log('⏳ Step 3: EnvConfig.load()...');
      await EnvConfig.load();
      _log('✅ Step 3: EnvConfig 完成');
    } catch (e, s) {
      _log('❌ Step 3 失败: $e');
      _log('📍 $s');
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 100));

    // Step 4: Sentry
    try {
      _set(_Phase.sentryDone, '⏳ Step 4: Sentry...');
      _log('⏳ Step 4: SentryService.initialize()...');
      await SentryService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () => _log('⚠️ Step 4: Sentry 超时，跳过'),
      );
      _log('✅ Step 4: Sentry 完成');
    } catch (e, s) {
      _log('❌ Step 4 失败: $e');
      _log('📍 $s');
    }
    await Future.delayed(Duration.zero);
    await Future.delayed(const Duration(milliseconds: 100));

    // All init steps done → 启动真实 MyApp
    _log('🚀 启动 MyApp...');
    _set(_Phase.myAppStart, '🚀 MyApp 启动中...');
    await Future.delayed(Duration.zero);

    _initDone = true;
    if (mounted) setState(() {});

    // runApp 替换当前 isolate，永远不会执行到这里
    runApp(
      ProviderScope(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: _MyAppTest(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initDone) {
      // 初始化等待界面（颜色随阶段变化）
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        home: _InitScreen(phase: _phase, status: _status, logs: _logs),
      );
    }
    // _initDone=true 时，应该已经 runApp 了
    // 如果还渲染到这里，说明 runApp 被拦截了
    return _InitScreen(phase: _Phase.error, status: '❌ runApp 被拦截!', logs: _logs);
  }
}

/// 初始化等待界面
class _InitScreen extends StatelessWidget {
  final _Phase phase;
  final String status;
  final List<String> logs;

  const _InitScreen({required this.phase, required this.status, required this.logs});

  Color get _bgColor {
    switch (phase) {
      case _Phase.engineStart:        return Colors.red;
      case _Phase.bindingDone:        return Colors.orange;
      case _Phase.hiveDone:           return Colors.yellow;
      case _Phase.configDone:         return Colors.pink;
      case _Phase.sentryDone:         return Colors.green;
      case _Phase.myAppStart:         return Colors.cyan;
      case _Phase.providerScopeDone:  return Colors.teal;
      case _Phase.materialAppDone:    return Colors.lime;
      case _Phase.myAppStateDone:     return Colors.deepOrange;
      case _Phase.myAppBuildStart:    return Colors.blueGrey;
      case _Phase.scaffoldDone:       return Colors.indigo;
      case _Phase.emptyStateMounting: return Colors.blue;
      case _Phase.allDone:            return Colors.blue;
      case _Phase.error:              return Colors.purple;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bgColor,
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text(
                  '🚀 初始化中...',
                  style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                  child: Text(status, style: const TextStyle(color: Colors.white70, fontFamily: 'monospace')),
                ),
                const SizedBox(height: 8),
                const Text(
                  '如果超过 10 秒停在同一步 → 该步卡住',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 8),
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
                        if (log.startsWith('⏳')) c = Colors.cyanAccent;
                        if (log.startsWith('📍')) c = Colors.orangeAccent;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(log, style: TextStyle(color: c, fontSize: 11, fontFamily: 'monospace')),
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
    );
  }
}

/// MyApp 测试组件 - 分步颜色渲染
///
/// 每个组件单独渲染，逐步暴露哪个环节崩溃
class _MyAppTest extends StatefulWidget {
  @override
  State<_MyAppTest> createState() => _MyAppTestState();
}

class _MyAppTestState extends State<_MyAppTest> {
  Color _bg = Colors.cyan; // 初始色
  String _label = '🚀 MyApp 创建中...';
  bool _locationReady = false;
  bool _initRouterDone = false;
  Object? _error;
  StackTrace? _stack;

  @override
  void initState() {
    super.initState();
    _log(Colors.teal, '🟢 MyApp State initState()');
    _buildTree();
  }

  void _log(Color c, String msg) {
    debugPrint('[MyApp] $msg');
    if (mounted) setState(() { _bg = c; _label = msg; });
  }

  Future<void> _buildTree() async {
    try {
      // 1. ProviderScope 已在外层，这里直接 build
      _log(Colors.lime, '⏳ MyApp.build() 开始...');

      // 2. Scaffold 壳
      await Future.delayed(Duration.zero);
      _log(Colors.indigo, '⏳ Scaffold 渲染中...');

      // 3. EmptyStatePage（包含定位权限检测）
      await Future.delayed(Duration.zero);
      _log(Colors.blue, '⏳ EmptyStatePage 挂载中...');
      _log(Colors.blue, '⚠️  EmptyStatePage 可能在这里卡住');

      // 渲染真实 EmptyStatePage
      if (!mounted) return;
      setState(() {
        _locationReady = true;
        _bg = Colors.deepPurple;
        _label = '🔵 EmptyStatePage 已挂载';
      });

    } catch (e, s) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _stack = s;
        _bg = Colors.purple;
        _label = '❌ MyApp 渲染异常: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Container(
        color: Colors.purple,
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error, color: Colors.white, size: 64),
                  const SizedBox(height: 16),
                  Text('MyApp 渲染异常', style: TextStyle(color: Colors.redAccent.shade100, fontSize: 20)),
                  const SizedBox(height: 12),
                  Text(_error.toString(), style: const TextStyle(color: Colors.white, fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(_stack.toString().split('\n').take(5).join('\n'),
                      style: const TextStyle(color: Colors.orangeAccent, fontSize: 11, fontFamily: 'monospace')),
                ],
              ),
            ),
          ),
        ),
      );
    }

    // 如果 EmptyStatePage 还没挂载，先显示等待色
    return Container(
      color: _bg,
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_label, style: const TextStyle(color: Colors.white, fontSize: 20)),
              const SizedBox(height: 20),
              const CircularProgressIndicator(color: Colors.white),
              const SizedBox(height: 16),
              const Text(
                '🚀 MyApp Widget 树渲染中...\n'
                '如果变成紫色 → MyApp 某处崩溃\n'
                '如果显示地图/内容 → 问题已定位！',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
