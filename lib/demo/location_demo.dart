// lib/demo/location_demo.dart
//
// ⚠️ 诊断模式：DEBUG_FAKE_POSITION = true
// 强制使用假GPS数据（北京），绕过所有权限和网络依赖
// 用于验证：地图瓦片本身能否加载
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

/// ⚠️ 诊断模式开关：true = 强制假GPS（跳过所有权限和网络依赖）
const bool DEBUG_FAKE_POSITION = true;

/// 诊断用假GPS流：每3秒发一个北京天安门的固定坐标
Stream<Position> _fakePositionStream() {
  return Stream.periodic(const Duration(seconds: 3), (count) {
    // ignore: invalid_use_of_visible_for_testing_member
    return Position(
      latitude: 39.909187,
      longitude: 116.397451,
      timestamp: DateTime.now(),
      accuracy: 10.0,
      altitude: 50.0,
      altitudeAccuracy: 5.0,
      heading: 0.0,
      headingAccuracy: 0.0,
      speed: 0.0,
      speedAccuracy: 0.0,
    );
  });
}

/// 诊断用假GPS的 StreamProvider
final _fakePositionStreamProvider = StreamProvider<Position>((ref) {
  return _fakePositionStream();
});

/// 主页面（地图 + 侧边栏 + 好友互动入口）
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
    // 诊断模式：强制用假GPS数据，否则用真实数据
    final positionAsync = DEBUG_FAKE_POSITION
        ? ref.watch(_fakePositionStreamProvider)
        : ref.watch(positionStreamProvider);
    final fencesAsync = ref.watch(fencesProvider);
    final privacyAsync = ref.watch(privacyFuseControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(DEBUG_FAKE_POSITION ? '🔧 诊断模式：假GPS' : '定位陪伴'),
        actions: [
          _SystemTimeButton(),
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
          Positioned.fill(
            child: _buildMap(positionAsync, fencesAsync, privacyAsync),
          ),
          SideDrawer(
            isOpen: _drawerOpen,
            onClose: _drawerOpen ? _closeDrawer : () {},
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
          FloatingActionButton(
            heroTag: 'create_fence',
            onPressed: _currentLat != null
                ? () => _showCreateGeofenceSheet()
                : null,
            tooltip: '创建围栏',
            child: const Icon(Icons.add_location_alt),
          ),
          const SizedBox(height: 12),
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
            Text(
              '定位失败: $err',
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                if (DEBUG_FAKE_POSITION) {
                  ref.invalidate(_fakePositionStreamProvider);
                } else {
                  ref.invalidate(positionStreamProvider);
                }
              },
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

        if (!_mapInitialized) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _mapController.move(LatLng(lat, lon), 15);
              _mapInitialized = true;
            }
          });
        }

        final fences = fencesAsync.valueOrNull ?? [];
        final controller = privacyAsync.valueOrNull;

        if (controller == null) {
          return FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(lat, lon),
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.locationchat.location_chat_app',
                // 显式注入 User-Agent
                tileProvider: NetworkTileProvider(
                  headers: {
                    'User-Agent':
                        'location_chat_app/1.0 (com.locationchat.location_chat_app)',
                  },
                ),
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
