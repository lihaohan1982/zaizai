// lib/features/chat/widgets/interaction_sheet_body.dart
import 'package:flutter/material.dart';
import 'package:location_chat_app/core/config/app_config.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'package:location_chat_app/features/chat/widgets/disconnection_banner.dart';
import 'package:location_chat_app/features/chat/widgets/interaction_bar.dart';
import 'package:location_chat_app/features/chat/widgets/interaction_sheet_header.dart';
import 'package:location_chat_app/features/chat/widgets/message_list_area.dart';
import 'package:location_chat_app/features/chat/widgets/pause_notice_bar.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer_content.dart';

/// InteractionSheet 主体内容：
/// 静态地图 + 顶栏 + 暂停条 + 断线条 + 消息列表 + 底部互动栏 + 侧边栏
///
/// 顶层通过 ListenableBuilder 监听 controller 变化，
/// 各子组件独立接收 controller 引用，各自按需 listen。
class InteractionSheetBody extends StatelessWidget {
  final String friendId;
  final String friendName;
  final String avatarUrl;
  final double? friendLat;
  final double? friendLng;
  final ChatInteractionController controller;
  final bool isPrivacyPaused;
  final bool isDrawerOpen;
  final VoidCallback onToggleDrawer;

  const InteractionSheetBody({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.avatarUrl,
    this.friendLat,
    this.friendLng,
    required this.controller,
    required this.isPrivacyPaused,
    required this.isDrawerOpen,
    required this.onToggleDrawer,
  });

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    final noticeBarHeight = controller.isFriendPaused ? 48.0 : 0.0;
    final disconnectionHeight = controller.isWsDisconnected ? 32.0 : 0.0;

    return Scaffold(
      backgroundColor: Colors.black87,
      body: Stack(
        children: [
          // 1. 静态地图背景
          if (friendLat != null && friendLng != null)
            Positioned.fill(
              child: Image.network(
                'https://restapi.amap.com/v3/staticmap'
                    '?location=$friendLng,$friendLat'
                    '&zoom=15&size=400*300'
                    '&key=${AppConfig.amapApiKey}',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.grey.shade900,
                  child: const Center(
                    child: Icon(Icons.map, size: 48, color: Colors.white24),
                  ),
                ),
                loadingBuilder: (_, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return Container(
                    color: Colors.grey.shade900,
                    child: const Center(child: CircularProgressIndicator()),
                  );
                },
              ),
            ),

          // 2. 顶部栏
          Positioned(
            top: topPadding + 8,
            left: 16,
            right: 16,
            child: InteractionSheetHeader(
              friendName: friendName,
              avatarUrl: avatarUrl,
              controller: controller,
              onBack: () => Navigator.of(context).pop(),
              onAvatarTap: onToggleDrawer,
            ),
          ),

          // 3. 暂停提示条
          Positioned(
            top: topPadding + 56,
            left: 0,
            right: 0,
            height: noticeBarHeight,
            child: PauseNoticeBar(isVisible: controller.isFriendPaused),
          ),

          // 4. 断线重连条
          Positioned(
            top: topPadding + 56 + noticeBarHeight,
            left: 0,
            right: 0,
            child: DisconnectionBanner(isDisconnected: controller.isWsDisconnected),
          ),

          // 5. 消息列表区
          Positioned(
            top: topPadding + 96 + noticeBarHeight + disconnectionHeight,
            left: 0,
            right: 0,
            bottom: 100,
            child: MessageListArea(controller: controller),
          ),

          // 6. 底部互动操作栏
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: InteractionBar(
              isPaused: isPrivacyPaused,
              onSendQuick: (contentKey) {
                controller.sendQuickMessage(
                  MessagePayload(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    type: MessageType.quick,
                    senderId: controller.currentUserId,
                    receiverId: friendId,
                    contentKey: contentKey,
                    source: MessageSource.manual,
                    timestamp: DateTime.now(),
                  ),
                );
              },
              onPoke: () {
                controller.sendQuickMessage(
                  MessagePayload(
                    id: DateTime.now().millisecondsSinceEpoch.toString(),
                    type: MessageType.quick,
                    senderId: controller.currentUserId,
                    receiverId: friendId,
                    contentKey: 'poke',
                    source: MessageSource.poke,
                    timestamp: DateTime.now(),
                    transient: true,
                  ),
                );
              },
            ),
          ),

          // 7. 侧边栏抽屉
          SideDrawer(
            isOpen: isDrawerOpen,
            onClose: onToggleDrawer,
            child: SideDrawerContent(
              onClose: onToggleDrawer,
              onPrivacySettingsTap: () {
                Navigator.pushNamed(context, '/privacy-settings');
              },
            ),
          ),
        ],
      ),
    );
  }
}
