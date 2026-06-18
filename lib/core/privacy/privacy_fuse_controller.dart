// lib/core/privacy/privacy_fuse_controller.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:location_chat_app/core/geofence/geofence_state_machine.dart';
import 'package:location_chat_app/core/models/geofence_config_data.dart';
import 'package:location_chat_app/core/models/privacy_state.dart';
import 'package:location_chat_app/core/repositories/geofence_repository.dart';
import 'package:location_chat_app/core/repositories/privacy_state_repository.dart';

enum PrivacyFuseStatus { normal, paused, resuming }
enum InitializationStatus { loading, success, failed, empty }

class PrivacyFuseController {
  final GeofenceRepository _geofenceRepo;
  final PrivacyStateRepository _privacyRepo;

  GeofenceStateMachine? _stateMachine;
  final ValueNotifier<PrivacyFuseStatus> fuseStatusNotifier =
      ValueNotifier(PrivacyFuseStatus.normal);

  /// [异步安全] 暴露初始化状态，供 UI 层决定展示引导页还是地图
  ///
  /// ## UI 路由契约（P1-6）
  /// | initStatus | UI 行为 |
  /// |------------|---------|
  /// | loading | 显示加载中 Spinner |
  /// | success | 显示地图主页面（GeofenceStatusIndicator + LocationMap） |
  /// | failed | 显示错误重试按钮 |
  /// | empty | **跳转到围栏引导创建页**（家/公司等预设围栏） |
  ///
  /// UI 层示例：
  /// ```dart
  /// ListenableBuilder(
  ///   listenable: controller.initStatusNotifier,
  ///   builder: (_, __) {
  ///     switch (controller.initStatusNotifier.value) {
  ///       case InitializationStatus.empty:
  ///         return const FenceSetupPage(); // ← 围栏引导创建页
  ///       case InitializationStatus.loading:
  ///         return const Center(child: CircularProgressIndicator());
  ///       case InitializationStatus.failed:
  ///         return Center(child: ElevatedButton(onPressed: retry, child: const Text('重试')));
  ///       case InitializationStatus.success:
  ///         return const LocationMapPage();
  ///     }
  ///   },
  /// )
  /// ```
  final ValueNotifier<InitializationStatus> initStatusNotifier =
      ValueNotifier(InitializationStatus.loading);

  bool _isPaused = false;
  bool _isInitializing = false;
  bool _disposed = false;
  Timer? _resumeTimeoutTimer;
  Timer? _saveDebounceTimer; // [性能] 防抖写入定时器

  PrivacyFuseController(this._geofenceRepo, this._privacyRepo);

  /// 隐私共享状态（normal / paused / resuming）
  PrivacyFuseStatus get fuseStatus => fuseStatusNotifier.value;

  /// 初始化状态（loading / success / failed / empty）
  InitializationStatus get initStatus => initStatusNotifier.value;

  /// [测试辅助] 暴露内部状态机（仅测试使用）
  @visibleForTesting
  GeofenceStateMachine? get stateMachineForTest => _stateMachine;

  /// [测试辅助] 手动启动 60 秒超时计时器（模拟 resuming 卡住场景）
  @visibleForTesting
  void startTimeoutForTest() {
    _clearResumeTimeout();
    _resumeTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (fuseStatusNotifier.value == PrivacyFuseStatus.resuming) {
        fuseStatusNotifier.value = PrivacyFuseStatus.normal;
      }
    });
  }

  /// [核心] 异步初始化入口，必须在状态机使用前 await
  Future<void> initialize(String fenceId) async {
    // [P1 竞态防护] 防止重复调用 initialize 覆盖未销毁旧实例
    if (_isInitializing) return;
    _isInitializing = true;

    try {
      initStatusNotifier.value = InitializationStatus.loading;

      // [时序安全] 必须先 await 解密加载，再构造状态机
      final GeofenceConfigData? configData = await _geofenceRepo.loadConfig(fenceId);

      if (configData == null) {
        // [空状态处理] 明确告知 UI 层无围栏数据，展示引导创建 UI
        initStatusNotifier.value = InitializationStatus.empty;
        return;
      }

      // 基于解密后的数据，安全构造状态机
      _stateMachine = GeofenceStateMachine(
        fenceId: configData.fenceId,
        centerLat: configData.centerLat,
        centerLon: configData.centerLon,
        radiusMeters: configData.radiusMeters,
        config: GeofenceConfig(
          enterConfirmationWindow: configData.enterConfirmationWindow,
          exitConfirmationWindow: configData.exitConfirmationWindow,
          fenceAccuracyThreshold: configData.fenceAccuracyThreshold,
          snapAccuracyThreshold: configData.snapAccuracyThreshold,
        ),
      );

      // [V5.3.2 规划官修正②] 注册监听器
      _stateMachine!.statusNotifier.addListener(_onGeofenceStatusChanged);
      _stateMachine!.coldStartGeneration.addListener(_onColdStartCompleted);

      // 恢复跨生命周期的隐私状态
      final PrivacyState privacyState = await _privacyRepo.loadState();
      if (privacyState.isPaused) {
        final bool isExpired = privacyState.pauseUntil != null &&
            DateTime.now().isAfter(privacyState.pauseUntil!);
        if (isExpired) {
          // 暂停已过期，自动恢复
          unawaited(_savePrivacyState(const PrivacyState(isPaused: false)));
        } else {
          _isPaused = true;
          _stateMachine?.suspend();
          fuseStatusNotifier.value = PrivacyFuseStatus.paused;
        }
      }

      initStatusNotifier.value = InitializationStatus.success;
    } catch (e, stackTrace) {
      debugPrint('Initialization failed: $e\n$stackTrace');
      initStatusNotifier.value = InitializationStatus.failed;
    } finally {
      _isInitializing = false;
    }
  }

  /// [V5.3.2 规划官修正②] 仅负责正常共享期间的状态同步，不再触碰 resuming
  void _onGeofenceStatusChanged() {
    if (_isPaused) return;
    // 职责单一化：仅用于未来扩展（如状态指示灯）
  }

  /// [V5.3.2 规划官修正②] 唯一负责解除 resuming 状态的监听
  void _onColdStartCompleted() {
    if (fuseStatusNotifier.value == PrivacyFuseStatus.resuming) {
      _clearResumeTimeout();
      fuseStatusNotifier.value = PrivacyFuseStatus.normal;
    }
  }

  /// [性能] 异步、防抖落盘，不阻塞 UI 线程（用于 resumeSharing）
  void _debouncedSaveState(PrivacyState state) {
    _saveDebounceTimer?.cancel();
    _saveDebounceTimer = Timer(const Duration(milliseconds: 300), () {
      unawaited(_savePrivacyState(state));
    });
  }

  /// [正确性] 立即同步落盘（用于 pauseSharing，必须确保 pause 状态不丢失）
  Future<void> _saveStateNow(PrivacyState state) async {
    _saveDebounceTimer?.cancel();
    await _savePrivacyState(state);
  }

  Future<void> _savePrivacyState(PrivacyState state) async {
    try {
      await _privacyRepo.saveState(state);
    } catch (e) {
      debugPrint('Failed to save privacy state: $e');
    }
  }

  /// [P3] 异步切换暂停状态（乐观更新 + 失败回滚）
  ///
  /// 调用方（如 SwitchListTile）通过 [messengerKey] 在失败时弹出 Toast。
  Future<void> togglePause(
    bool val, {
    Duration? duration,
    GlobalKey<ScaffoldMessengerState>? messengerKey,
  }) async {
    final previousPaused = _isPaused;
    final previousStatus = fuseStatusNotifier.value;

    // 1. 乐观更新 UI
    if (val) {
      pauseSharing(duration: duration);
    } else {
      resumeSharing();
    }

    // 2. 发起后端请求
    try {
      // TODO: 替换为真实 API 调用
      // await _dio.post('/api/privacy/${val ? 'pause' : 'resume'}');
      debugPrint('API: POST /api/privacy/${val ? 'pause' : 'resume'}');
    } catch (e) {
      // 3. 请求失败：状态回滚
      _isPaused = previousPaused;
      fuseStatusNotifier.value = previousStatus;
      if (previousPaused) {
        _stateMachine?.suspend();
      } else {
        _stateMachine?.resume();
      }
      fuseStatusNotifier.value = previousStatus;

      // 4. 弹出错误提示
      final ctx = messengerKey?.currentContext;
      if (ctx != null) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('操作失败，请重试')),
        );
      }
    }
  }

  void pauseSharing({Duration? duration}) {
    if (_stateMachine == null) return;
    _isPaused = true;
    _stateMachine!.suspend();
    fuseStatusNotifier.value = PrivacyFuseStatus.paused;

    final DateTime? until = duration != null ? DateTime.now().add(duration) : null;
    // [PFC-4 修复] 立即同步落盘，确保 pause 状态不丢失
    // 防抖保存会被 cancel，故需同步一次
    final pauseState = PrivacyState(isPaused: true, pauseUntil: until);
    unawaited(_saveStateNow(pauseState));

    // TODO: 调用后端 API POST /api/privacy/pause
    debugPrint('API: POST /api/privacy/pause, duration: $duration');
  }

  void resumeSharing() {
    if (_stateMachine == null) return;
    // [V5.3.2 竞态修复] 必须先设置 resuming 状态，再触发底层 resume
    fuseStatusNotifier.value = PrivacyFuseStatus.resuming;

    _isPaused = false;
    _stateMachine!.resume();

    _debouncedSaveState(const PrivacyState(isPaused: false));

    // 兜底：60秒超时强制解除
    _clearResumeTimeout();
    _resumeTimeoutTimer = Timer(const Duration(seconds: 60), () {
      if (fuseStatusNotifier.value == PrivacyFuseStatus.resuming) {
        fuseStatusNotifier.value = PrivacyFuseStatus.normal;
      }
    });
  }

  void _clearResumeTimeout() {
    _resumeTimeoutTimer?.cancel();
    _resumeTimeoutTimer = null;
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearResumeTimeout();
    _saveDebounceTimer?.cancel();
    try {
      _stateMachine?.statusNotifier.removeListener(_onGeofenceStatusChanged);
      _stateMachine?.coldStartGeneration.removeListener(_onColdStartCompleted);
    } catch (_) {}
    _stateMachine?.dispose();
    fuseStatusNotifier.dispose();
    initStatusNotifier.dispose();
  }
}
