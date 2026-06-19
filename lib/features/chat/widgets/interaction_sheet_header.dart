// lib/features/chat/widgets/interaction_sheet_header.dart
import 'package:flutter/material.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'package:location_chat_app/features/chat/widgets/buddy_status_card.dart';

/// InteractionSheet 顶部栏：
/// 返回按钮 + 独立头像（侧边栏入口）+ BuddyStatusCard 纯展示
class InteractionSheetHeader extends StatelessWidget {
  final String friendName;
  final String avatarUrl;
  final ChatInteractionController controller;
  final VoidCallback onBack;
  final VoidCallback onAvatarTap;

  const InteractionSheetHeader({
    super.key,
    required this.friendName,
    required this.avatarUrl,
    required this.controller,
    required this.onBack,
    required this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 返回按钮
        GestureDetector(
          onTap: onBack,
          child: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        // P2：独立头像作为侧边栏统一入口
        GestureDetector(
          onTap: onAvatarTap,
          child: CircleAvatar(
            radius: 18,
            backgroundImage: NetworkImage(avatarUrl),
          ),
        ),
        const SizedBox(width: 10),
        // BuddyStatusCard 纯展示，无点击回调
        Expanded(
          child: BuddyStatusCard(
            friendName: friendName,
            avatarUrl: avatarUrl,
            locationData: controller.friendLocationData,
          ),
        ),
      ],
    );
  }
}
