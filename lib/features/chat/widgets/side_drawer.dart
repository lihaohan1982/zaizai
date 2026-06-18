import 'dart:ui';
import 'package:flutter/material.dart';

/// P1：侧边栏抽屉
///
/// 从左侧滑入的毛玻璃抽屉，带半透明遮罩层和关闭按钮。
/// 通过 isOpen 控制显隐，didUpdateWidget 驱动动画。
class SideDrawer extends StatefulWidget {
  final bool isOpen;
  final VoidCallback? onClose;
  final Widget? child;

  const SideDrawer({
    super.key,
    required this.isOpen,
    this.onClose,
    this.child,
  });

  @override
  State<SideDrawer> createState() => _SideDrawerState();
}

class _SideDrawerState extends State<SideDrawer>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slideAnimation = Tween<double>(begin: -1.0, end: 0.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );
  }

  @override
  void didUpdateWidget(covariant SideDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final drawerWidth = screenWidth * 0.75;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.isDismissed) return const SizedBox.shrink();

        return Stack(
          children: [
            // 半透明遮罩层，点击关闭
            GestureDetector(
              onTap: widget.onClose,
              child: Container(
                color: Colors.black
                    .withAlpha(((0.54 * _controller.value).clamp(0, 1) * 255)
                        .round()),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: drawerWidth,
                child: Transform.translate(
                  offset: Offset(_slideAnimation.value * drawerWidth, 0),
                  child: Semantics(
                    label: '侧边栏菜单',
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
                      child: Container(
                        color: Colors.black.withAlpha((0.6 * 255).round()),
                        child: Column(
                          children: [
                            Align(
                              alignment: Alignment.topRight,
                              child: IconButton(
                                icon: const Icon(Icons.close,
                                    color: Colors.white70),
                                onPressed: widget.onClose,
                              ),
                            ),
                            Expanded(child: child ?? const SizedBox.shrink()),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: widget.child,
    );
  }
}
