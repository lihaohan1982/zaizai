// lib/demo/location_demo.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

import '../core/location/location_providers.dart';
import '../core/providers.dart';
import '../core/privacy/privacy_fuse_controller.dart';
import '../features/chat/widgets/side_drawer.dart';
import '../features/chat/widgets/side_drawer_content.dart';
import '../features/map/presentation/widgets/geofence_status_indicator.dart';
import '../features/map/presentation/widgets/location_map.dart';
import '../features/fence/presentation/create_geofence_sheet.dart';

/// 主页面（地图 + 侧边栏 + 好友互动入口）
///
/// 核心职责：
/// 1. 地图渲染（flutter_map + OSM瓦片 + 围栏Polygon）
/// 2. 实时位置跟踪（positionStreamProvider → 地图中心跟随）
/// 3. 侧边栏导航（好友列表 → InteractionSheet / 隐私设置）
/// 4. 系统时间显示（AppBar）
/// 5. 围栏状态指示器（AppBar）
class LocationDemoPage extends ConsumerStatefulWidget {
  const LocationDemoPage({super.key});

  @override
  ConsumerState<LocationDemoPage> createState() => _LocationDemoPageState();
}

class _LocationDemoPageState extends ConsumerState<LocationDemoPage> {
  bool _drawerOpen = false;
  final MapController _mapController = MapController();
  bool _mapInitialized = false;
  double? _currentLat;
  double? _currentLng;

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  void _openDrawer() => setState(() => _drawerOpen = true);
  void _closeDrawer() => setState(() => _drawerOpen = false);

  void _showCreateGeofenceSheet() {
    if (_currentLat == null || _currentLng == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => CreateGeofenceSheet(
        lat: _currentLat!,
        lng: _currentLng!,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final positionAsync = ref.watch(positionStreamProvider);
    final fencesAsync = ref.watch(fencesProvider);
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('定位陪伴'),
        actions: [
          // 系统时间显示
          _SystemTimeButton(),
          // 围栏状态指示器
          privacyAsync.when(
            data: (controller) => GeofenceStatusIndicator(
              stateMachine: null,
              controller: controller,
            ),
            loading: () => const SizedBox(width: 16),
            error: (_, __) => const SizedBox(width: 16),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Stack(
        children: [
          // 地图层
          _buildMap(positionAsync, fencesAsync, privacyAsync),

          // 侧边栏（叠加层，非 Drawer widget）
          SideDrawer(
            isOpen: _drawerOpen,
            onClose: _closeDrawer,
            child: SideDrawerContent(
              onClose: _closeDrawer,
              onPrivacySettingsTap: () {
                Navigator.pushNamed(context, '/privacy-settings');
              },
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // 围栏创建按钮
          FloatingActionButton(
            heroTag: 'create_fence',
            onPressed: _currentLat != null
                ? () => _showCreateGeofenceSheet()
                : null,
            tooltip: '创建围栏',
            child: const Icon(Icons.add_location_alt),
          ),
          const SizedBox(height: 12),
          // 好友列表按钮
          FloatingActionButton(
            heroTag: 'open_drawer',
            onPressed: _openDrawer,
            tooltip: '打开好友列表',
            child: const Icon(Icons.people),
          ),
        ],
      ),
    );
  }

  Widget _buildMap(
    AsyncValue<Position> positionAsync,
    AsyncValue<List<Map<String, dynamic>>> fencesAsync,
    AsyncValue<PrivacyFuseController> privacyAsync,
  ) {
    return positionAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('定位失败: $err', style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => ref.invalidate(positionStreamProvider),
              child: const Text('重试'),
            ),
          ],
        ),
      ),
      data: (position) {
        final lat = position.latitude;
        final lon = position.longitude;
        _currentLat = lat;
        _currentLng = lon;

        // 首次获取位置时移动地图中心
        if (!_mapInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _mapController.move(LatLng(lat, lon), 15);
              _mapInitialized = true;
            }
          });
        }

        // 围栏列表和隐私控制器（给 LocationMap 使用）
        final fences = fencesAsync.valueOrNull ?? [];
        final controller = privacyAsync.valueOrNull;

        if (controller == null) {
          // 隐私控制器尚未就绪，先显示纯地图
          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(lat, lon),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                // 国内可访问的 OSM 德国镜像
                urlTemplate:
                    'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.locationchat.location_chat_app',
                tileProvider: NetworkTileProvider(),
              ),
            ],
          );
        }

        return LocationMap(
          fences: fences,
          triggeredFenceId: null,
          privacyController: controller,
        );
      },
    );
  }
}

/// 系统时间按钮（AppBar action）
class _SystemTimeButton extends StatefulWidget {
  @override
  State<_SystemTimeButton> createState() => _SystemTimeButtonState();
}

class _SystemTimeButtonState extends State<_SystemTimeButton> {
  late Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    return IconButton(
      icon: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.access_time, size: 18),
          const SizedBox(width: 2),
          Text(timeStr, style: const TextStyle(fontSize: 14)),
        ],
      ),
      tooltip: '系统时间',
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '当前系统时间: ${now.toString().substring(0, 19)}',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }
}
