import 'dart:ui';
import 'package:flutter/material.dart';

/// 好友状态卡：纯展示组件，显示头像、名称、位置、电量
///
/// P2 修正：移除 onAvatarTap 回调，侧边栏打开入口由顶栏独立头像承担
class BuddyStatusCard extends StatelessWidget {
  final String friendName;
  final String avatarUrl;
  final Map<String, dynamic>? locationData;

  const BuddyStatusCard({
    super.key,
    required this.friendName,
    required this.avatarUrl,
    this.locationData,
  });

  Color _getBatteryColor(int batteryLevel) {
    if (batteryLevel > 50) return const Color(0xFF4CAF50);
    if (batteryLevel >= 20) return const Color(0xFFFF9800);
    return const Color(0xFFF44336);
  }

  @override
  Widget build(BuildContext context) {
    // 安全解析，防崩溃
    final battery = int.tryParse(locationData?['battery']?.toString() ?? '') ?? 100;
    final charging = locationData?['charging'] == true ||
        locationData?['charging'] == 'true';
    final batteryColor = _getBatteryColor(battery);
    final locationDesc = locationData?['locationDesc'] ?? '📍 未知';

    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withAlpha((0.1 * 255).round()),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // P2：纯展示头像，无点击回调
              CircleAvatar(
                radius: 18,
                backgroundImage: NetworkImage(avatarUrl),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    friendName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        locationDesc,
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.battery_std, size: 12, color: batteryColor),
                      const SizedBox(width: 2),
                      Text(
                        '$battery%',
                        style: TextStyle(
                          color: batteryColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (charging) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.flash_on,
                            size: 12, color: Colors.yellow),
                      ],
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
