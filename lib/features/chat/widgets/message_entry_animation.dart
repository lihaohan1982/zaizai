import 'package:flutter/material.dart';

/// P1：消息入场动画包装器
///
/// 自己发送的消息从右侧滑入，对方发送的从左侧滑入。
/// 配合父级 ListView 使用 ValueKey(msg.id)，确保动画仅在首次挂载时播放。
class MessageEntryAnimation extends StatefulWidget {
  final bool isMe;
  final Widget child;
  final Duration duration;

  const MessageEntryAnimation({
    super.key,
    required this.isMe,
    required this.child,
    this.duration = const Duration(milliseconds: 200),
  });

  @override
  State<MessageEntryAnimation> createState() => _MessageEntryAnimationState();
}

class _MessageEntryAnimationState extends State<MessageEntryAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    // 自己发送：从右侧滑入 (1.0 -> 0.0)
    // 对方发送：从左侧滑入 (-1.0 -> 0.0)
    final beginOffset =
        widget.isMe ? const Offset(1.0, 0.0) : const Offset(-1.0, 0.0);

    _slideAnimation = Tween<Offset>(
      begin: beginOffset,
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    // 直接在 initState 中启动，配合父级 ValueKey 保证仅首次播放
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: widget.child,
      ),
    );
  }
}
