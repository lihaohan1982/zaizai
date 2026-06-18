import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/marker_data.dart';

/// 好友地图标记组件
/// 
/// 根据 [MarkerData.freshness] 状态渲染不同样式：
/// - FRESH: 正常彩色头像
/// - STALE: 橙色"X分钟前"标签
/// - EXPIRED: 置灰头像（数据过期）
/// - PAUSED: 置灰头像 + "暂停共享"提示文案
class FriendMarkerWidget extends ConsumerWidget {
  final String userId;
  final MarkerData marker;

  const FriendMarkerWidget({
    super.key,
    required this.userId,
    required this.marker,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isExpired = marker.freshness == LocationFreshness.expired;
    final isPaused = marker.freshness == LocationFreshness.paused;
    final isStale = marker.freshness == LocationFreshness.stale;

    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        // 头像主体（过期或暂停均置灰）
        ColorFiltered(
          colorFilter: ColorFilter.mode(
            (isExpired || isPaused) ? Colors.grey : Colors.transparent,
            BlendMode.saturation,
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: isPaused ? Colors.grey : Colors.blue,
                width: 2,
              ),
            ),
            child: CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey[300],
              // TODO: 使用真实头像 URL
              child: Icon(
                Icons.person,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),

        // 暂停共享提示文案（仅 PAUSED 触发）
        if (isPaused)
          Positioned(
            bottom: -24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                marker.pauseMessage ?? '对方暂时关闭了位置共享',
                style: const TextStyle(
                  fontSize: 9,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // 电量角标（暂停时隐藏）
        if (marker.battery != null && !isPaused)
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: _getBatteryColor(marker.battery!),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    marker.charging == true 
                        ? Icons.battery_charging_full 
                        : Icons.battery_std,
                    size: 10,
                    color: Colors.white,
                  ),
                  Text(
                    '${marker.battery}%',
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // STALE 状态标注
        if (isStale && marker.ageMinutes != null)
          Positioned(
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${marker.ageMinutes}分钟前',
                style: const TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                ),
              ),
            ),
          ),

        // EXPIRED 状态标注
        if (isExpired)
          Positioned(
            top: -12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.grey,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '位置已过期',
                style: TextStyle(
                  fontSize: 8,
                  color: Colors.white,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Color _getBatteryColor(int battery) {
    if (battery > 50) return Colors.green;
    if (battery > 20) return Colors.orange;
    return Colors.red;
  }
}
