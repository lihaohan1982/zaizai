import 'package:flutter/material.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'package:location_chat_app/features/chat/widgets/interaction_bubble.dart';
import 'package:location_chat_app/features/chat/widgets/message_entry_animation.dart';

/// 消息列表区域（独立组件，P3 抽离）
///
/// 职责：
///   - 根据 controller 状态渲染加载中 / 加载失败 / 空引导 / 消息列表
///   - 使用 ListenableBuilder 响应式刷新
///   - 消息入场动画配合 ValueKey 防止复用重播
class MessageListArea extends StatelessWidget {
  final ChatInteractionController controller;

  const MessageListArea({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // 加载中
        if (controller.isLoading) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.white));
        }

        // 加载失败
        if (controller.loadError) {
          return Center(
            child: TextButton(
              onPressed: () => controller.retryLoadHistory(),
              child: const Text('加载失败，点击重试',
                  style: TextStyle(color: Colors.white70)),
            ),
          );
        }

        // 空消息列表引导
        if (controller.messages.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '你们还没说过话，拍一拍打个招呼吧',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withAlpha((0.6 * 255).round()),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ),
          );
        }

        // 消息列表渲染
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          reverse: true,
          itemCount: controller.messages.length,
          itemBuilder: (context, index) {
            final msg = controller.messages[index];
            final isMe = msg.senderId == controller.currentUserId;
            return MessageEntryAnimation(
              key: ValueKey(msg.id),
              isMe: isMe,
              child: InteractionBubble(
                message: msg,
                isMe: isMe,
                onRetry: msg.status == MessageStatus.failed
                    ? () => controller.retrySendMessage(msg)
                    : null,
              ),
            );
          },
        );
      },
    );
  }
}
