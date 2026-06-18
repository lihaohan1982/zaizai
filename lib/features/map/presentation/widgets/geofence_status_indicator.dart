import 'package:flutter/material.dart';

import '../../../../core/geofence/geofence_state_machine.dart';
import '../../../../core/privacy/privacy_fuse_controller.dart';

/// 围栏状态指示器
///
/// 监听 [GeofenceStateMachine.statusNotifier] 和 [PrivacyFuseController.fuseStatusNotifier]，
/// 按优先级展示五种状态：
///
/// 1. paused（最高优先级）→ 灰色圆点 + "共享已暂停"
/// 2. resuming → 灰色圆点 + "正在恢复..." 脉冲动画
/// 3. transitioning → 橙色圆点 + "确认中..."
/// 4. inside → 绿色圆点 + "安全区域内"
/// 5. outside → 红色圆点 + "区域外"
///
/// 状态优先级：paused > resuming > 围栏状态
class GeofenceStatusIndicator extends StatefulWidget {
  final GeofenceStateMachine? stateMachine;
  final PrivacyFuseController controller;

  const GeofenceStatusIndicator({
    super.key,
    required this.stateMachine,
    required this.controller,
  });

  @override
  State<GeofenceStatusIndicator> createState() => _GeofenceStatusIndicatorState();
}

class _GeofenceStatusIndicatorState extends State<GeofenceStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void didUpdateWidget(covariant GeofenceStatusIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.stateMachine?.statusNotifier ?? ValueNotifier(GeofenceStatus.outside),
        widget.controller.fuseStatusNotifier,
      ]),
      builder: (context, _) {
        final fuseStatus = widget.controller.fuseStatusNotifier.value;
        final geoStatus = widget.stateMachine?.statusNotifier.value ?? GeofenceStatus.outside;

        final config = _resolveStatus(fuseStatus, geoStatus);
        final dotColor = config.$1;
        final label = config.$2;
        final showPulse = config.$3;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildDot(dotColor, showPulse),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  /// 解析状态优先级
  ///
  /// 返回 (圆点颜色, 文案, 是否显示脉冲动画)
  (Color, String, bool) _resolveStatus(
    PrivacyFuseStatus fuseStatus,
    GeofenceStatus geoStatus,
  ) {
    // 优先级 1：暂停（最高）
    if (fuseStatus == PrivacyFuseStatus.paused) {
      return (Colors.grey, '共享已暂停', false);
    }

    // 优先级 2：恢复中
    if (fuseStatus == PrivacyFuseStatus.resuming) {
      return (Colors.grey, '正在恢复...', true);
    }

    // 优先级 3：围栏状态
    switch (geoStatus) {
      case GeofenceStatus.inside:
        return (Colors.green, '安全区域内', false);
      case GeofenceStatus.transitioning:
        return (Colors.orange, '确认中...', false);
      case GeofenceStatus.outside:
        return (Colors.red, '区域外', false);
    }
  }

  Widget _buildDot(Color color, bool showPulse) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );

    if (!showPulse) return dot;

    return FadeTransition(
      opacity: _pulseAnimation,
      child: dot,
    );
  }
}
