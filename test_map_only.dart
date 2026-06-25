// test_map_only.dart - 极简地图渲染测试
// 用途：隔离测试 FlutterMap 是否能正常渲染
// 运行：flutter run test_map_only.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

void main() {
  runApp(const MapOnlyApp());
}

class MapOnlyApp extends StatelessWidget {
  const MapOnlyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('极简地图测试')),
        body: const MapOnlyPage(),
      ),
    );
  }
}

class MapOnlyPage extends StatelessWidget {
  const MapOnlyPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 底层：蓝色背景（如果看到蓝色说明地图没渲染）
        Container(color: Colors.blue),

        // 中层：红色诊断条（应该始终可见）
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            color: Colors.red,
            child: const Center(
              child: Text(
                '极简测试：能看到红色说明布局正常',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ),

        // 上层：地图（如果瓦片加载失败，应该能看到地图控件但无瓦片）
        Positioned.fill(
          top: 80, // 给红色诊断条留空间
          child: FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(39.909187, 116.397451),
              initialZoom: 13,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: ['a', 'b', 'c'],
                userAgentPackageName: 'com.locationchat.location_chat_app',
                // 诊断：瓦片加载失败时打印日志
                errorTileCallback: (tile, error, stackTrace) {
                  debugPrint('[极简测试] 瓦片加载失败: z=${tile.coordinates.z} x=${tile.coordinates.x} y=${tile.coordinates.y} — $error');
                },
              ),
            ],
          ),
        ),

        // 顶层：交互提示
        Positioned(
          bottom: 20,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text(
              '测试要点：\n1. 能看到红色条？ → 布局正常\n2. 能拖动/缩放地图？ → 地图控件正常\n3. 有瓦片图片？ → 网络正常\n4. 全白/全蓝？ → 渲染引擎问题',
              style: TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ),
      ],
    );
  }
}
