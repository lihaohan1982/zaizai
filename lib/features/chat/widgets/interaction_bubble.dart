// lib/features/chat/widgets/interaction_bubble.dart
import 'package:flutter/material.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/messaging/message_templates.dart';

/// 消息气泡组件：区分手动/围栏/隐私消息样式
///
/// 布局规则：
/// - isMe=true（右侧，蓝色气泡）
/// - contentKey 为围栏类（左侧，暖色气泡 + 地图图标）
/// - contentKey 为隐私类（居中，灰色小字系统消息）
class InteractionBubble extends StatelessWidget {
  final MessagePayload message;
  final bool isMe;
  final VoidCallback? onRetry;

  const InteractionBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onRetry,
  });

  bool get _isSystem =>
      message.source == MessageSource.privacy ||
      message.contentKey == 'sharing_paused' ||
      message.contentKey == 'sharing_resumed';

  bool get _isGeofence => MessageTemplates.isGeofenceMessage(message.contentKey);

  @override
  Widget build(BuildContext context) {
    // 系统消息居中展示
    if (_isSystem) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              MessageTemplates.resolveText(message.contentKey, fenceId: message.fenceId),
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ),
        ),
      );
    }

    final displayText = MessageTemplates.resolveText(
      message.contentKey,
      customText: message.customText,
      fenceId: message.fenceId,
    );

    // 气泡颜色
    final bubbleColor = _isGeofence
        ? const Color(0xFFFFB74D) // 暖橙色 = 围栏消息
        : (isMe ? const Color(0xFF6B7BFF) : Colors.white.withValues(alpha: 0.9));

    final textColor = isMe ? Colors.white : Colors.black87;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            // 围栏消息：加地图图标
            if (_isGeofence)
              const Icon(Icons.location_on, size: 18, color: Color(0xFFFFB74D)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.65,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(displayText, style: TextStyle(color: textColor, fontSize: 15)),
                  if (message.status == MessageStatus.sending)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: textColor.withValues(alpha: 0.6),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('发送中…', style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.6))),
                        ],
                      ),
                    ),
                  if (message.status == MessageStatus.failed && onRetry != null)
                    GestureDetector(
                      onTap: onRetry,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '发送失败，点击重试',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade300),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (isMe && _isGeofence) ...[
            const SizedBox(width: 6),
            const Icon(Icons.location_on, size: 18, color: Color(0xFFFFB74D)),
          ],
        ],
      ),
    );
  }
}
