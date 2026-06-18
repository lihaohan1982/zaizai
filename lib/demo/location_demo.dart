import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/location/location_providers.dart';
import '../core/providers.dart';
import '../features/map/presentation/widgets/geofence_status_indicator.dart';

/// 定位 Demo 页面（任务 1.2 验证）
///
/// P4-W4 改造：
/// 1. 所有定位状态（服务、权限、位置流）全部下沉到 Riverpod Provider。
/// 2. 页面本身为纯 View 层，ConsumerWidget，无 setState。
/// 3. 刷新按钮通过 `ref.invalidate` 重新触发权限/位置流。
class LocationDemoPage extends ConsumerWidget {
  const LocationDemoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(locationDemoStatusProvider);
    final positionAsync = ref.watch(positionStreamProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('定位 Demo'),
        actions: [
          // 围栏状态指示器（监听 PrivacyFuseController）
          Consumer(
            builder: (context, ref, _) {
              final privacyAsync = ref.watch(privacyFuseControllerProvider);
              return privacyAsync.when(
                data: (controller) => GeofenceStatusIndicator(
                  stateMachine: null, // MVP 期间不展示围栏状态
                  controller: controller,
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 状态显示
            Text(
              status,
              style: TextStyle(
                fontSize: 16,
                color: status.contains('❌') ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 20),

            // 位置信息显示
            positionAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(),
              ),
              error: (err, stack) => Text(
                '位置流错误: $err',
                style: const TextStyle(color: Colors.red),
              ),
              data: (position) => _buildPositionInfo(position),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // 刷新所有定位相关 Provider，重新触发权限请求和位置流
          ref.invalidate(locationServiceEnabledProvider);
          ref.invalidate(locationPermissionProvider);
          ref.invalidate(positionStreamProvider);
        },
        tooltip: '重新获取位置',
        child: const Icon(Icons.refresh),
      ),
    );
  }

  Widget _buildPositionInfo(Position position) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoRow('纬度', '${position.latitude.toStringAsFixed(6)}°'),
        _buildInfoRow('经度', '${position.longitude.toStringAsFixed(6)}°'),
        _buildInfoRow('精度', '${position.accuracy.toStringAsFixed(1)} 米'),
        _buildInfoRow('海拔', '${position.altitude.toStringAsFixed(1)} 米'),
        _buildInfoRow('速度', '${position.speed.toStringAsFixed(1)} 米/秒'),
        _buildInfoRow(
          '时间戳',
          '${position.timestamp.toLocal()}',
        ),
        const SizedBox(height: 20),
        const Text(
          '📍 位置已获取！可以尝试移动设备查看坐标变化。',
          style: TextStyle(fontSize: 14, color: Colors.blue),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
