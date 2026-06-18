// lib/features/chat/widgets/interaction_bar.dart
import 'package:flutter/material.dart';

/// 微互动按钮栏
/// 传入 [onSendQuick] 用于快捷消息（传入 contentKey），[onPoke] 用于拍一拍
class InteractionBar extends StatefulWidget {
  final bool isPaused;
  final ValueChanged<String> onSendQuick; // contentKey
  final VoidCallback onPoke;

  const InteractionBar({
    super.key,
    required this.isPaused,
    required this.onSendQuick,
    required this.onPoke,
  });

  @override
  State<InteractionBar> createState() => _InteractionBarState();
}

class _InteractionBarState extends State<InteractionBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pokeController;

  @override
  void initState() {
    super.initState();
    _pokeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _pokeController.value = 1.0; // 初始正常大小
  }

  @override
  void dispose() {
    _pokeController.dispose();
    super.dispose();
  }

  void _triggerPokeAnimation() {
    // 弹性动画：缩小再弹回
    _pokeController
        .animateTo(0.8, curve: Curves.easeOut)
        .then((_) {
      _pokeController.animateTo(1.0, curve: Curves.elasticOut);
    });
  }

  /// 通用按钮构建方法
  Widget _buildButton({
    required String label,
    required IconData icon,
    required VoidCallback? onTap, // null 表示禁用
    bool isPoke = false,
  }) {
    return _PressableButton(
      label: label,
      icon: icon,
      onTap: onTap,
      isPaused: widget.isPaused,
      scaleAnimation: isPoke ? _pokeController : null,
      onPokeAnimationTrigger: isPoke ? _triggerPokeAnimation : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildButton(
                label: '拍一拍',
                icon: Icons.waving_hand,
                onTap: widget.onPoke,
                isPoke: true,
              ),
              const SizedBox(width: 10),
              _buildButton(
                label: '想你了',
                icon: Icons.favorite,
                onTap: () => widget.onSendQuick('miss_you'),
              ),
              const SizedBox(width: 10),
              _buildButton(
                label: '在干嘛',
                icon: Icons.coffee,
                onTap: () => widget.onSendQuick('whats_up'),
              ),
            ],
          ),
          const SizedBox(height: 10), // 设计规范 10dp
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildButton(
                label: '报平安',
                icon: Icons.location_on,
                // 暂停时"报平安"禁用（不可点击）
                onTap: widget.isPaused
                    ? null
                    : () => widget.onSendQuick('location_report'),
              ),
              const SizedBox(width: 10),
              _buildButton(
                label: '记得充电',
                icon: Icons.battery_charging_full,
                onTap: () => widget.onSendQuick('charge_reminder'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 带有按压缩放效果的单个按钮（内部管理 pressed 状态）
class _PressableButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPaused;
  final Animation<double>? scaleAnimation; // 外部动画（拍一拍用）
  final VoidCallback? onPokeAnimationTrigger;

  const _PressableButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isPaused,
    this.scaleAnimation,
    this.onPokeAnimationTrigger,
  });

  @override
  State<_PressableButton> createState() => _PressableButtonState();
}

class _PressableButtonState extends State<_PressableButton> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final bool disabled = widget.onTap == null;
    final double scale = _isPressed ? 0.95 : 1.0;

    Widget button = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white
                .withValues(alpha: disabled ? 0.1 : 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(
            widget.icon,
            color: disabled
                ? Colors.white30
                : (widget.isPaused ? Colors.white54 : Colors.white),
            size: 24,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: TextStyle(
            fontSize: 12,
            color: disabled
                ? Colors.white30
                : (widget.isPaused ? Colors.white54 : Colors.white70),
          ),
        ),
      ],
    );

    // 外部弹性动画包裹（仅拍一拍）
    if (widget.scaleAnimation != null) {
      button = ScaleTransition(scale: widget.scaleAnimation!, child: button);
    }

    return GestureDetector(
      onTapDown: (_) {
        if (!disabled) setState(() => _isPressed = true);
      },
      onTapUp: (_) {
        if (!disabled) setState(() => _isPressed = false);
      },
      onTapCancel: () {
        if (!disabled) setState(() => _isPressed = false);
      },
      onTap: () {
        if (disabled) return;
        widget.onPokeAnimationTrigger?.call();
        widget.onTap?.call();
      },
      child: AnimatedScale(
        scale: scale,
        duration: const Duration(milliseconds: 100),
        child: button,
      ),
    );
  }
}
