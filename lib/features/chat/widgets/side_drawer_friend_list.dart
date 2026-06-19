// lib/features/chat/widgets/side_drawer_friend_list.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';

/// 侧边栏好友动态列表
class SideDrawerFriendList extends ConsumerWidget {
  final void Function(String friendId) onFriendTap;

  const SideDrawerFriendList({
    super.key,
    required this.onFriendTap,
  });

  String _getDynamicStatus(Map<String, dynamic> friend) {
    final location = friend['locationDesc'] as String?;
    final battery = friend['battery'];
    if (location != null && location.isNotEmpty) return '📍 $location';
    if (battery != null) return '🔋 电量 $battery%';
    return '暂无动态';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final friendsAsync = ref.watch(friendListProvider);

    return Expanded(
      child: friendsAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: Colors.white54)),
        error: (err, _) => Center(
          child: Text('加载失败: $err',
              style: TextStyle(color: Colors.white.withAlpha((0.6 * 255).round()))),
        ),
        data: (friends) {
          if (friends.isEmpty) {
            return Center(
              child: Text('暂无好友',
                  style: TextStyle(color: Colors.white.withAlpha((0.4 * 255).round()))),
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
                    style: const TextStyle(color: Colors.white, fontSize: 15)),
                subtitle: Text(
                  _getDynamicStatus(friend),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  final friendId = friend['id']?.toString();
                  if (friendId == null || friendId.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('好友数据异常，无法进入聊天')),
                    );
                    return;
                  }
                  onFriendTap(friendId);
                },
              );
            },
          );
        },
      ),
    );
  }
}
