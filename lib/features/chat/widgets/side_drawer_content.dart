// lib/features/chat/widgets/side_drawer_content.dart
import 'package:flutter/material.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer_friend_list.dart';
import 'package:location_chat_app/features/chat/widgets/side_drawer_user_section.dart';

/// 侧边栏内容组件
///
/// 职责单一：组合 UserSection + FriendList + PrivacySettings
/// 数据来源全部通过 Riverpod Provider（全局状态驱动，无硬编码假数据）
class SideDrawerContent extends StatelessWidget {
  final VoidCallback onClose;
  final VoidCallback onPrivacySettingsTap;

  const SideDrawerContent({
    super.key,
    required this.onClose,
    required this.onPrivacySettingsTap,
  });

  void _navigateToFriend(BuildContext context, String friendId) {
    onClose();
    Navigator.pushNamed(context, '/interaction/$friendId');
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 当前用户信息区
          const SideDrawerUserSection(),

          const Divider(color: Colors.white24, height: 1),

          // 2. 好友动态标题
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Text('好友动态',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
          ),

          // 3. 好友列表
          SideDrawerFriendList(onFriendTap: (id) => _navigateToFriend(context, id)),

          const Divider(color: Colors.white24, height: 1),

          // 4. 添加好友入口
          ListTile(
            leading: const Icon(Icons.person_add, color: Colors.white70),
            title: const Text('添加好友',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              onClose();
              Navigator.pushNamed(context, '/add-friend');
            },
          ),

          // 5. 隐私设置入口
          ListTile(
            leading: const Icon(Icons.lock_outline, color: Colors.white70),
            title: const Text('隐私与位置设置',
                style: TextStyle(color: Colors.white, fontSize: 15)),
            trailing: const Icon(Icons.chevron_right, color: Colors.white54),
            onTap: () {
              onClose();
              onPrivacySettingsTap();
            },
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
