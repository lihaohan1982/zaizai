// lib/features/chat/pages/interaction_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/config/app_config.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/network/dio_client.dart';
import 'package:location_chat_app/core/providers.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'package:location_chat_app/features/chat/widgets/buddy_status_card.dart';
import 'package:location_chat_app/features/chat/widgets/interaction_bar.dart';
import 'package:location_chat_app/features/chat/widgets/message_list_area.dart';
import 'package:location_chat_app/features/chat/widgets/pause_notice_bar.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer_content.dart';

/// 好友互动页面：静态地图背景 + 好友状态卡 + 消息列表 + 互动操作栏
///
/// P2 最终闭环：
///   - 顶栏独立头像作为侧边栏统一入口，BuddyStatusCard 纯展示
///   - SideDrawerContent 全局状态驱动，无硬编码假数据
///   - 隐私设置点击执行真实路由跳转
///   - MessageEntryAnimation + ValueKey 防复用重播
class InteractionSheet extends ConsumerStatefulWidget {
  final String friendId;
  final String friendName;
  final String avatarUrl;
  final double? friendLat;
  final double? friendLng;

  const InteractionSheet({
    super.key,
    required this.friendId,
    required this.friendName,
    required this.avatarUrl,
    this.friendLat,
    this.friendLng,
  });

  @override
  ConsumerState<InteractionSheet> createState() => _InteractionSheetState();
}

class _InteractionSheetState extends ConsumerState<InteractionSheet> {
  ChatInteractionController? _controller;
  bool _isDrawerOpen = false;

  @override
  Widget build(BuildContext context) {
    final serviceAsync = ref.watch(quickMessageServiceProvider(widget.friendId));
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return serviceAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black87,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Text('加载失败: $err',
              style: const TextStyle(color: Colors.white)),
        ),
      ),
      data: (service) {
        _controller ??= ChatInteractionController(
          messengerKey: ref.read(scaffoldMessengerKeyProvider),
          friendId: widget.friendId,
          fences: const [],
          quickMessageService: service,
          wsClient: ref.read(wsClientProvider),
          authState: ref.read(authStateProvider),
          dioClient: DioClient(),
        );

        final isPaused = privacyAsync.maybeWhen(
          data: (ctrl) => ctrl.fuseStatus == PrivacyFuseStatus.paused,
          orElse: () => false,
        );

        return ListenableBuilder(
          listenable: _controller!,
          builder: (context, _) {
            if (_controller!.loadError) {
              return Scaffold(
                backgroundColor: Colors.black87,
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off,
                          size: 48, color: Colors.white54),
                      const SizedBox(height: 16),
                      const Text('消息加载失败',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => _controller!.retryLoadHistory(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final noticeBarHeight =
                _controller!.isFriendPaused ? 48.0 : 0.0;

            return Scaffold(
              backgroundColor: Colors.black87,
              body: Stack(
                children: [
                  // 静态地图背景
                  if (widget.friendLat != null && widget.friendLng != null)
                    Positioned.fill(
                      child: Image.network(
                        'https://restapi.amap.com/v3/staticmap'
                            '?location=${widget.friendLng},${widget.friendLat}'
                            '&zoom=15&size=400*300'
                            '&key=${AppConfig.amapApiKey}',
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: Colors.grey.shade900,
                          child: const Center(
                            child: Icon(Icons.map,
                                size: 48, color: Colors.white24),
                          ),
                        ),
                        loadingBuilder: (_, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey.shade900,
                            child: const Center(
                                child: CircularProgressIndicator()),
                          );
                        },
                      ),
                    ),

                  // P2 顶栏：返回按钮 + 独立头像入口 + BuddyStatusCard 纯展示
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        // 返回按钮
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: const Icon(Icons.arrow_back_ios,
                              color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        // P2：独立头像作为侧边栏统一入口
                        GestureDetector(
                          onTap: () =>
                              setState(() => _isDrawerOpen = true),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundImage:
                                NetworkImage(widget.avatarUrl),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // BuddyStatusCard 纯展示，无点击回调
                        Expanded(
                          child: BuddyStatusCard(
                            friendName: widget.friendName,
                            avatarUrl: widget.avatarUrl,
                            locationData:
                                _controller!.friendLocationData,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // P1：暂停提示条
                  Positioned(
                    top: MediaQuery.of(context).padding.top + 56,
                    left: 0,
                    right: 0,
                    height: noticeBarHeight,
                    child: PauseNoticeBar(
                      isVisible: _controller!.isFriendPaused,
                    ),
                  ),

                  // P3：断线重连提示条
                  Positioned(
                    top: MediaQuery.of(context).padding.top +
                        56 +
                        noticeBarHeight,
                    left: 0,
                    right: 0,
                    child: ListenableBuilder(
                      listenable: _controller!,
                      builder: (context, _) {
                        if (_controller!.isWsDisconnected) {
                          return Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            color: Colors.redAccent,
                            child: const Text(
                              '⚠️ 连接已断开，正在尝试重连...',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: Colors.white, fontSize: 12),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),

                  // 消息列表区
                  Positioned(
                    top: MediaQuery.of(context).padding.top +
                        96 +
                        noticeBarHeight +
                        (_controller!.isWsDisconnected ? 32.0 : 0.0),
                    left: 0,
                    right: 0,
                    bottom: 100,
                    child: MessageListArea(controller: _controller!),
                  ),

                  // 底部互动操作栏
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: InteractionBar(
                      isPaused: isPaused,
                      onSendQuick: (contentKey) {
                        _controller!.sendQuickMessage(
                          MessagePayload(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            type: MessageType.quick,
                            senderId: _controller!.currentUserId,
                            receiverId: widget.friendId,
                            contentKey: contentKey,
                            source: MessageSource.manual,
                            timestamp: DateTime.now(),
                          ),
                        );
                      },
                      onPoke: () {
                        _controller!.sendQuickMessage(
                          MessagePayload(
                            id: DateTime.now()
                                .millisecondsSinceEpoch
                                .toString(),
                            type: MessageType.quick,
                            senderId: _controller!.currentUserId,
                            receiverId: widget.friendId,
                            contentKey: 'poke',
                            source: MessageSource.poke,
                            timestamp: DateTime.now(),
                            transient: true,
                          ),
                        );
                      },
                    ),
                  ),

                  // P2：侧边栏抽屉（接入真实内容组件）
                  SideDrawer(
                    isOpen: _isDrawerOpen,
                    onClose: () =>
                        setState(() => _isDrawerOpen = false),
                    child: SideDrawerContent(
                      onClose: () =>
                          setState(() => _isDrawerOpen = false),
                      onPrivacySettingsTap: () {
                        Navigator.pushNamed(
                            context, '/privacy-settings');
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
