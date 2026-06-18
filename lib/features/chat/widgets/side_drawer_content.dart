import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';

/// P2：侧边栏内容（全局状态驱动，无硬编码）
///
/// 修正点：
///   - 从 AuthState 获取当前用户信息（nickname / currentUserId / isLoggedIn）
///   - 通过 friendListProvider 获取好友列表（需在 providers.dart 注册）
///   - 隐私设置点击执行真实路由跳转
class SideDrawerContent extends ConsumerWidget {
  final VoidCallback onClose;
  final VoidCallback onPrivacySettingsTap;

  const SideDrawerContent({
    super.key,
    required this.onClose,
    required this.onPrivacySettingsTap,
  });

  /// 动态计算好友状态文案
  String _getDynamicStatus(Map<String, dynamic> friend) {
    final location = friend['locationDesc'] as String?;
    final battery = friend['battery'];
    if (location != null && location.isNotEmpty) return '📍 $location';
    if (battery != null) return '🔋 电量 $battery%';
    return '暂无动态';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 从全局 AuthState 获取当前用户信息
    final authState = ref.watch(authStateProvider);
    final currentUserName = authState.nickname ?? '我';
    final isOnline = authState.isLoggedIn;

    // 从全局状态获取好友列表
    final friendsAsync = ref.watch(friendListProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部：当前用户信息
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            child: Row(
              children: [
                const CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.person, color: Colors.white70)),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(currentUserName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    if (isOnline)
                      Text('在线',
                          style: TextStyle(
                              color: Colors.greenAccent
                                  .withAlpha((0.8 * 255).round()),
                              fontSize: 12))
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ],
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // 2. 中部：好友列表（全局状态驱动）
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text('好友动态',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: friendsAsync.when(
              loading: () => const Center(
                  child: CircularProgressIndicator(color: Colors.white54)),
              error: (err, _) => Center(
                child: Text('加载失败: $err',
                    style: TextStyle(
                        color: Colors.white
                            .withAlpha((0.6 * 255).round()))),
              ),
              data: (friends) {
                if (friends.isEmpty) {
                  return Center(
                    child: Text('暂无好友',
                        style: TextStyle(
                            color: Colors.white
                                .withAlpha((0.4 * 255).round()))),
                  );
                }
                return ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: friends.length,
                  itemBuilder: (context, index) {
                    final friend = friends[index];
                    return ListTile(
                      leading: CircleAvatar(
                          backgroundColor: Colors.white24,
                          backgroundImage: friend['avatarUrl'] != null
                              ? NetworkImage(friend['avatarUrl'] as String)
                              : null,
                          child: friend['avatarUrl'] == null
                              ? Text(friend['name']?[0] ?? '?',
                                  style: const TextStyle(color: Colors.white))
                              : null),
                      title: Text(friend['name'] ?? '未知',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 15)),
                      subtitle: Text(
                        _getDynamicStatus(friend),
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                      onTap: () {
                        // 【空安全校验】防止 id 为 null 导致 /interaction/null 崩溃
                        final friendId = friend['id']?.toString();
                        if (friendId == null || friendId.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('好友数据异常，无法进入聊天')),
                          );
                          return;
                        }
                        onClose();
                        Navigator.pushNamed(
                            context, '/interaction/$friendId');
                      },
                    );
                  },
                );
              },
            ),
          ),

          const Divider(color: Colors.white24, height: 1),

          // 3. 底部：隐私设置入口（真实路由跳转）
          ListTile(
            leading:
                const Icon(Icons.lock_outline, color: Colors.white70),
            title: const Text('隐私与位置设置',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            trailing: const Icon(Icons.chevron_right,
                color: Colors.white54),
            onTap: () {
              onClose(); // 先关闭侧边栏
              onPrivacySettingsTap(); // 再触发真实导航
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
