import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import 'package:location_chat_app/core/providers.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';

/// 初始化空状态页
///
/// 状态机：
///   loading     → 首次启动，正在初始化定位服务
///   noPermission → 定位权限被拒绝
///   locationOff  → 设备定位已关闭
///   ready        → 初始化完成，App 跳转到主地图页（通知上层）
///
/// 上层通过 [onReady] 回调接收初始化成功信号，
/// 并自行处理路由跳转。
class EmptyStatePage extends ConsumerStatefulWidget {
  /// 初始化完成后回调（返回 true 表示继续，跳过）
  final void Function()? onReady;

  const EmptyStatePage({super.key, this.onReady});

  @override
  ConsumerState<EmptyStatePage> createState() => _EmptyStatePageState();
}

class _EmptyStatePageState extends ConsumerState<EmptyStatePage>
    with SingleTickerProviderStateMixin {
  /// 当前页面状态
  _EmptyState _state = _EmptyState.loading;

  /// 详细说明文案
  String _message = '正在初始化定位服务...';

  /// 是否正在请求权限（防止重复点击）
  bool _isRequesting = false;

  /// 动画控制器（呼吸灯效果）
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // 延迟一小段时间再检测（避免冷启动误判）
    Future.delayed(const Duration(milliseconds: 300), _checkInitialState);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// 检查初始状态（权限 + 定位开关）
  Future<void> _checkInitialState() async {
    if (!mounted) return;

    // 1. 检查权限
    final permission = await Geolocator.checkPermission();
    if (!mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _state = _EmptyState.noPermission;
        _message = '需要定位权限才能正常使用';
      });
      return;
    }

    // 2. 检查定位开关
    final isEnabled = await Geolocator.isLocationServiceEnabled();
    if (!mounted) return;

    if (!isEnabled) {
      setState(() {
        _state = _EmptyState.locationOff;
        _message = '请在设置中开启定位服务';
      });
      return;
    }

    // 3. 尝试获取一次定位，确认服务可用
    setState(() {
      _state = _EmptyState.loading;
      _message = '正在获取位置...';
    });

    try {
      await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } on LocationServiceDisabledException {
      if (!mounted) return;
      setState(() {
        _state = _EmptyState.locationOff;
        _message = '定位服务已关闭';
      });
      return;
    } catch (e) {
      // 权限或其他错误：允许进入主界面（地图页会处理）
    }

    if (!mounted) return;
    // 初始化成功
    widget.onReady?.call();
  }

  /// 用户点击「开启定位」或「重试」
  Future<void> _requestPermission() async {
    if (_isRequesting) return;
    setState(() => _isRequesting = true);

    final permission = await Geolocator.requestPermission();
    if (!mounted) return;

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() {
        _state = _EmptyState.noPermission;
        _message = '权限被拒绝，请在设置中开启';
        _isRequesting = false;
      });
      return;
    }

    // 权限已授予，重试检查
    _isRequesting = false;
    await _checkInitialState();
  }

  /// 用户点击「去设置」
  Future<void> _openSettings() async {
    await Geolocator.openAppSettings();
  }

  /// 用户点击「去开启定位」
  Future<void> _openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 动画图标
              _buildIcon(theme),
              const SizedBox(height: 40),

              // 标题
              Text(
                _titleText,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              // 说明文案
              Text(
                _message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 48),

              // 主操作按钮
              _buildPrimaryButton(theme),
              const SizedBox(height: 16),

              // 辅助文案
              if (_state == _EmptyState.noPermission ||
                  _state == _EmptyState.locationOff)
                TextButton(
                  onPressed: _state == _EmptyState.locationOff
                      ? _openSettings
                      : _openLocationSettings,
                  child: Text(
                    _state == _EmptyState.locationOff
                        ? '打开系统设置'
                        : '去设置页开启定位',
                  ),
                ),

              // 隐私状态指示（仅在加载状态显示）
              if (_state == _EmptyState.loading) ...[
                const SizedBox(height: 40),
                const _PrivacyStatusChip(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String get _titleText {
    switch (_state) {
      case _EmptyState.loading:
        return '准备就绪';
      case _EmptyState.noPermission:
        return '需要定位权限';
      case _EmptyState.locationOff:
        return '定位服务已关闭';
    }
  }

  Widget _buildIcon(ThemeData theme) {
    final iconData = switch (_state) {
      _EmptyState.loading => Icons.location_on,
      _EmptyState.noPermission => Icons.location_off,
      _EmptyState.locationOff => Icons.gps_off,
    };

    final color = switch (_state) {
      _EmptyState.loading => Colors.blue,
      _EmptyState.noPermission => Colors.orange,
      _EmptyState.locationOff => Colors.grey,
    };

    if (_state == _EmptyState.loading) {
      return FadeTransition(
        opacity: _pulseAnimation,
        child: Icon(iconData, size: 80, color: color),
      );
    }

    return Icon(iconData, size: 80, color: color.withValues(alpha: 0.6));
  }

  Widget _buildPrimaryButton(ThemeData theme) {
    if (_state == _EmptyState.loading) {
      return FilledButton.icon(
        onPressed: null,
        icon: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        label: const Text('初始化中...'),
      );
    }

    final label = _state == _EmptyState.noPermission
        ? '开启定位权限'
        : '开启定位服务';

    return FilledButton(
      onPressed: _isRequesting
          ? null
          : (_state == _EmptyState.noPermission
              ? _requestPermission
              : _openLocationSettings),
      child: Text(label),
    );
  }
}

/// 空状态枚举
enum _EmptyState {
  /// 正在加载/初始化
  loading,

  /// 定位权限被拒绝
  noPermission,

  /// 设备定位已关闭
  locationOff,
}

/// 隐私状态指示芯片
///
/// 依赖 PrivacyFuseControllerProvider（由上层注入）
class _PrivacyStatusChip extends ConsumerWidget {
  const _PrivacyStatusChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    final (label, color, icon) = privacyAsync.when(
      data: (controller) => switch (controller.initStatus) {
        InitializationStatus.loading || InitializationStatus.failed =>
          ('隐私控制初始化中', Colors.grey, Icons.settings),
        _ => switch (controller.fuseStatus) {
          PrivacyFuseStatus.normal =>
            ('位置共享已开启', Colors.green, Icons.visibility),
          PrivacyFuseStatus.paused =>
            ('位置共享已暂停', Colors.orange, Icons.visibility_off),
          PrivacyFuseStatus.resuming =>
            ('正在恢复共享...', Colors.blue, Icons.sync),
        },
      },
      loading: () => ('隐私控制初始化中', Colors.grey, Icons.settings),
      error: (_, __) => ('隐私控制初始化失败', Colors.red, Icons.error),
    );

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
