import 'dart:ui';
import 'package:flutter/material.dart';

/// P1：暂停共享提示条
///
/// 当好友暂停位置共享时显示提示。
/// isVisible=false 时返回 SizedBox.shrink()，阻断 BackdropFilter 渲染开销。
class PauseNoticeBar extends StatelessWidget {
  final bool isVisible;
  final String message;

  const PauseNoticeBar({
    super.key,
    required this.isVisible,
    this.message = '她暂时不想暴露位置，但你的消息她能看到',
  });

  @override
  Widget build(BuildContext context) {
    if (!isVisible) return const SizedBox.shrink();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      height: 48.0,
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withAlpha((0.6 * 255).round()),
            ),
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
