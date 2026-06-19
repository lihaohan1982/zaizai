// lib/features/chat/widgets/side_drawer_user_section.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';

/// 侧边栏当前用户信息区
class SideDrawerUserSection extends ConsumerWidget {
  const SideDrawerUserSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final currentUserName = authState.nickname ?? '我';
    final isOnline = authState.isLoggedIn;

    return Padding(
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
                        color: Colors.greenAccent.withAlpha((0.8 * 255).round()),
                        fontSize: 12))
              else
                const SizedBox.shrink(),
            ],
          ),
        ],
      ),
    );
  }
}
