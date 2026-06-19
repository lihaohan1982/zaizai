// lib/features/chat/widgets/disconnection_banner.dart
import 'package:flutter/material.dart';

/// 断线重连提示横幅
///
/// 当 WebSocket 连接断开时显示红色警告条，
/// 恢复连接后自动消失（通过 ListenableBuilder 驱动）
class DisconnectionBanner extends StatelessWidget {
  final bool isDisconnected;

  const DisconnectionBanner({
    super.key,
    required this.isDisconnected,
  });

  @override
  Widget build(BuildContext context) {
    return isDisconnected
        ? Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.redAccent,
            child: const Text(
              '⚠️ 连接已断开，正在尝试重连...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 12),
            ),
          )
        : const SizedBox.shrink();
  }
}
