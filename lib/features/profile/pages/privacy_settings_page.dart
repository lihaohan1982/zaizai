import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';
import 'package:location_chat_app/core/privacy/privacy_fuse_controller.dart';

/// 隐私与位置设置页（MVP 占位实现）
///
/// 阶段一：先确保路由可达，避免 /privacy-settings 导航崩溃。
/// 阶段二/三：接入真实 PrivacyFuseController 状态与 API。
class PrivacySettingsPage extends ConsumerWidget {
  const PrivacySettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('隐私与位置设置',
            style: TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: privacyAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white54)),
        error: (e, _) => Center(
          child: Text('加载失败: $e',
              style: const TextStyle(color: Colors.redAccent)),
        ),
        data: (controller) => ListenableBuilder(
          listenable: Listenable.merge([
            controller.fuseStatusNotifier,
          ]),
          builder: (context, _) {
            final status = controller.fuseStatusNotifier.value;
            final isPaused = status == PrivacyFuseStatus.paused;

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard(
                  title: '位置共享',
                  subtitle: isPaused ? '当前已暂停' : '正在共享位置',
                  trailing: Switch(
                    value: !isPaused,
                    onChanged: (value) {
                      if (value) {
                        controller.resumeSharing();
                      } else {
                        controller.pauseSharing();
                      }
                    },
                  ),
                ),
                const SizedBox(height: 16),
                _buildCard(
                  title: '查看围栏事件',
                  subtitle: '进入/离开围栏的历史记录',
                  onTap: () {
                    // TODO: 从 controller 读取真实 fenceId
                    Navigator.pushNamed(context, '/fence/home/events');
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildCard({
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return Card(
      color: Colors.white.withAlpha((0.05 * 255).round()),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(title,
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        subtitle: Text(subtitle,
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
        trailing: trailing ??
            (onTap != null
                ? const Icon(Icons.chevron_right, color: Colors.white54)
                : null),
        onTap: onTap,
      ),
    );
  }
}

