import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../core/providers.dart';
import '../features/map/presentation/widgets/geofence_status_indicator.dart';

/// 定位 Demo 页面（任务 1.2 验证）
///
/// 功能：
/// 1. 请求定位权限
/// 2. 获取当前位置
/// 3. 显示坐标、精度、时间戳
/// 4. 展示围栏状态指示器（AppBar 右侧）
class LocationDemoPage extends ConsumerStatefulWidget {
  const LocationDemoPage({super.key});

  @override
  ConsumerState<LocationDemoPage> createState() => _LocationDemoPageState();
}

class _LocationDemoPageState extends ConsumerState<LocationDemoPage> {
  Position? _position;
  String _status = '正在请求定位权限...';
  StreamSubscription<Position>? _positionStream;

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  Future<void> _initLocation() async {
    // 1. 检查定位服务是否启用
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() {
        _status = '❌ 定位服务未启用，请在设置中开启';
      });
      return;
    }

    // 2. 检查并请求权限
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() {
          _status = '❌ 定位权限被拒绝';
        });
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() {
        _status = '❌ 定位权限被永久拒绝，请在系统设置中开启';
      });
      return;
    }

    // 3. 权限已获取，开始定位
    setState(() {
      _status = '✅ 权限已获取，正在获取位置...';
    });

    // 4. 获取当前位置（单次）
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _position = position;
        _status = '✅ 位置获取成功';
      });
    } catch (e) {
      setState(() {
        _status = '❌ 获取位置失败: $e';
      });
    }

    // 5. 监听位置更新（持续）
    _positionStream = Geolocator.getPositionStream().listen((position) {
      setState(() {
        _position = position;
        _status = '✅ 位置持续更新中...';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
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
              _status,
              style: TextStyle(
                fontSize: 16,
                color: _status.contains('❌') ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 20),

            // 位置信息显示
            if (_position != null) ...[
              _buildInfoRow('纬度', '${_position!.latitude.toStringAsFixed(6)}°'),
              _buildInfoRow('经度', '${_position!.longitude.toStringAsFixed(6)}°'),
              _buildInfoRow('精度', '${_position!.accuracy.toStringAsFixed(1)} 米'),
              _buildInfoRow('海拔', '${_position!.altitude.toStringAsFixed(1)} 米'),
              _buildInfoRow('速度', '${_position!.speed.toStringAsFixed(1)} 米/秒'),
              _buildInfoRow(
                '时间戳',
                '${_position!.timestamp.toLocal()}',
              ),
              const SizedBox(height: 20),
              Text(
                '📍 位置已获取！可以尝试移动设备查看坐标变化。',
                style: TextStyle(fontSize: 14, color: Colors.blue),
              ),
            ] else
              const Center(
                child: CircularProgressIndicator(),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _initLocation,
        tooltip: '重新获取位置',
        child: const Icon(Icons.refresh),
      ),
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

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }
}
