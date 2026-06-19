// lib/features/chat/pages/interaction_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';
import 'package:location_chat_app/features/chat/controllers/chat_interaction_controller.dart';
import 'package:location_chat_app/features/chat/widgets/interaction_sheet_body.dart';

/// 好友互动页面入口
///
/// 职责：
///   - 监听 controller 的 loading/error/data 三态
///   - 监听隐私状态（isPrivacyPaused）
///   - 管理侧边栏开合状态（本地 UI 状态）
///   - 组合 InteractionSheetBody 渲染完整 UI
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
  bool _isDrawerOpen = false;

  void _toggleDrawer() => setState(() => _isDrawerOpen = !_isDrawerOpen);

  @override
  Widget build(BuildContext context) {
    final controllerAsync =
        ref.watch(chatInteractionControllerProvider(widget.friendId));
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return controllerAsync.when(
      loading: () => const Scaffold(
        backgroundColor: Colors.black87,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (err, stack) => Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
              const SizedBox(height: 16),
              Text('控制器加载失败: $err',
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      ),
      data: (ChatInteractionController controller) {
        final isPrivacyPaused = privacyAsync.maybeWhen(
          data: (ctrl) => ctrl.fuseStatus == PrivacyFuseStatus.paused,
          orElse: () => false,
        );

        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            if (controller.loadError) {
              return Scaffold(
                backgroundColor: Colors.black87,
                body: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off, size: 48, color: Colors.white54),
                      const SizedBox(height: 16),
                      const Text('消息加载失败',
                          style: TextStyle(color: Colors.white70, fontSize: 16)),
                      const SizedBox(height: 16),
                      FilledButton.tonal(
                        onPressed: () => controller.retryLoadHistory(),
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return InteractionSheetBody(
              friendId: widget.friendId,
              friendName: widget.friendName,
              avatarUrl: widget.avatarUrl,
              friendLat: widget.friendLat,
              friendLng: widget.friendLng,
              controller: controller,
              isPrivacyPaused: isPrivacyPaused,
              isDrawerOpen: _isDrawerOpen,
              onToggleDrawer: _toggleDrawer,
            );
          },
        );
      },
    );
  }
}
