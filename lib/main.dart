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

/// 渐进初始化诊断版本
///
/// 工作方式：
/// 1. 立即显示红色屏幕 + "FLUTTER ENGINE WORKS!"（已确认小米 14 Ultra 可见）
/// 2. 逐步执行每个初始化步骤
/// 3. 每一步成功后 UI 颜色改变，用户可以直观看到卡在哪一步
///
/// 颜色变化顺序：
///   RED    → 引擎启动
///   ORANGE → Step 1: WidgetsFlutterBinding
///   YELLOW → Step 2: Hive.initFlutter
///   PINK   → Step 3: EnvConfig.load
///   GREEN  → Step 4: SentryService.initialize
///   BLUE   → 全部完成
///   PURPLE → 任意步骤出错
void main() {
  // 立即启动 UI，用户马上能看到颜色
  runApp(const _ProgressiveInitApp(phase: _InitPhase.engineStart));
}

/// 初始化阶段枚举
enum _InitPhase {
  engineStart,  // 红色
  bindingReady, // 橙色
  hiveReady,    // 黄色
  configReady,  // 粉色
  sentryReady,  // 绿色
  allDone,      // 蓝色
  error,        // 紫色
}

class _ProgressiveInitApp extends StatefulWidget {
  final _InitPhase phase;
  const _ProgressiveInitApp({super.key, required this.phase});

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
    // 延迟 100ms 确保 UI 帧已渲染完成再开始初始化
    Future.delayed(const Duration(milliseconds: 100), _startInitialization);
  }

  Color get _bgColor {
    switch (_phase) {
      case _InitPhase.engineStart: return Colors.red;
      case _InitPhase.bindingReady: return Colors.orange;
      case _InitPhase.hiveReady: return Colors.yellow;
      case _InitPhase.configReady: return Colors.pink;
      case _InitPhase.sentryReady: return Colors.green;
      case _InitPhase.allDone: return Colors.blue;
      case _InitPhase.error: return Colors.purple;
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
      _setPhase(_InitPhase.bindingReady, '⏳ Step 1: WidgetsFlutterBinding...');
      WidgetsFlutterBinding.ensureInitialized();
      _addLog('✅ Step 1: WidgetsFlutterBinding 完成', _LogLevel.success);
    } catch (e, s) {
      _setPhase(_InitPhase.error, '❌ Step 1 失败: $e');
      _addLog('❌ Step 1: $e', _LogLevel.error);
      _addLog('📍 $s', _LogLevel.stack);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // Step 2: Hive.initFlutter
    try {
      _setPhase(_InitPhase.hiveReady, '⏳ Step 2: Hive.initFlutter...');
      _addLog('⏳ Step 2: 开始初始化 Hive...', _LogLevel.info);
      await Hive.initFlutter();
      _addLog('✅ Step 2: Hive.initFlutter 完成', _LogLevel.success);
    } catch (e, s) {
      _setPhase(_InitPhase.error, '❌ Step 2 失败: $e');
      _addLog('❌ Step 2: Hive.initFlutter 失败: $e', _LogLevel.error);
      _addLog('📍 $s', _LogLevel.stack);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // Step 3: EnvConfig.load
    try {
      _setPhase(_InitPhase.configReady, '⏳ Step 3: EnvConfig.load...');
      _addLog('⏳ Step 3: 开始加载环境配置...', _LogLevel.info);
      await EnvConfig.load();
      _addLog('✅ Step 3: EnvConfig.load 完成', _LogLevel.success);
    } catch (e, s) {
      _setPhase(_InitPhase.error, '❌ Step 3 失败: $e');
      _addLog('❌ Step 3: EnvConfig.load 失败: $e', _LogLevel.error);
      _addLog('📍 $s', _LogLevel.stack);
      return;
    }

    await Future.delayed(const Duration(milliseconds: 300));

    // Step 4: SentryService.initialize
    try {
      _setPhase(_InitPhase.sentryReady, '⏳ Step 4: SentryService.initialize...');
      _addLog('⏳ Step 4: 开始初始化 Sentry...', _LogLevel.info);
      await SentryService.initialize().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _addLog('⚠️ Step 4: Sentry 初始化超时(5s)，跳过', _LogLevel.warning);
        },
      );
      _addLog('✅ Step 4: SentryService.initialize 完成', _LogLevel.success);
    } catch (e, s) {
      _setPhase(_InitPhase.error, '❌ Step 4 失败: $e');
      _addLog('❌ Step 4: SentryService.initialize 失败: $e', _LogLevel.error);
      _addLog('📍 $s', _LogLevel.stack);
      return;
    }

    // All done!
    _setPhase(_InitPhase.allDone, '✅ 全部初始化完成！');
    _addLog('✅ 所有 4 个初始化步骤均完成', _LogLevel.success);
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

                  // 标题
                  Text(
                    'FLUTTER ENGINE WORKS!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _phase == _InitPhase.allDone
                          ? Colors.cyanAccent
                          : Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 当前状态
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
                  const SizedBox(height: 12),

                  // 颜色说明
                  Text(
                    '当前颜色: ${_colorName(_bgColor)} (${_phase.name})',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),

                  // 日志面板
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
                            case _LogLevel.error: textColor = Colors.redAccent;
                            case _LogLevel.warning: textColor = Colors.yellowAccent;
                            case _LogLevel.info: textColor = Colors.white70;
                            case _LogLevel.stack: textColor = Colors.orangeAccent;
                          }
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1),
                            child: Text(
                              log.message,
                              style: TextStyle(
                                color: textColor,
                                fontSize: 12,
                                fontFamily: 'monospace',
                              ),
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

  String _colorName(Color c) {
    if (c == Colors.red) return '红';
    if (c == Colors.orange) return '橙';
    if (c == Colors.yellow) return '黄';
    if (c == Colors.pink) return '粉';
    if (c == Colors.green) return '绿';
    if (c == Colors.blue) return '蓝';
    if (c == Colors.purple) return '紫';
    return '?';
  }
}

enum _LogLevel { success, error, warning, info, stack }

class _LogEntry {
  final String message;
  final _LogLevel level;
  _LogEntry(this.message, this.level);
}
