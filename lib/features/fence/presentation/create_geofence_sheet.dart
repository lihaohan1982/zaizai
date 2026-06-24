// lib/features/fence/presentation/create_geofence_sheet.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../controllers/geofence_create_controller.dart';

/// 创建围栏 BottomSheet
///
/// 纯UI组件，接收当前坐标。半径单位：米。
class CreateGeofenceSheet extends ConsumerStatefulWidget {
  final double lat;
  final double lng;

  const CreateGeofenceSheet({
    super.key,
    required this.lat,
    required this.lng,
  });

  @override
  ConsumerState<CreateGeofenceSheet> createState() => _CreateGeofenceSheetState();
}

class _CreateGeofenceSheetState extends ConsumerState<CreateGeofenceSheet> {
  final _nameController = TextEditingController();
  double _radius = 100.0;

  @override
  void dispose() {
    _nameController.dispose();
    // Sheet 关闭时重置状态
    ref.read(geofenceCreateControllerProvider.notifier).reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(geofenceCreateControllerProvider);

    // 创建成功后自动关闭
    if (state.isSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('围栏创建成功'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
      });
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题
          Text('创建电子围栏', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '中心点: ${widget.lat.toStringAsFixed(4)}, ${widget.lng.toStringAsFixed(4)}',
            style: const TextStyle(color: Colors.grey, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // 错误提示
          if (state.error != null) ...[
            Text(state.error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            const SizedBox(height: 8),
          ],

          // 名称输入
          TextField(
            controller: _nameController,
            enabled: !state.isLoading,
            decoration: const InputDecoration(
              labelText: '围栏名称',
              hintText: '例如：公司、家',
              prefixIcon: Icon(Icons.location_on),
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 20),

          // 半径滑块
          Row(
            children: [
              const Icon(Icons.straighten, size: 18, color: Colors.grey),
              const SizedBox(width: 6),
              Text('半径: ${_radius.toInt()} 米',
                  style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
          ),
          Slider(
            value: _radius,
            min: 50,
            max: 1000,
            divisions: 19,
            label: '${_radius.toInt()} 米',
            onChanged: state.isLoading ? null : (v) => setState(() => _radius = v),
          ),
          const SizedBox(height: 16),

          // 提交按钮
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: state.isLoading
                  ? null
                  : () {
                      // ⚠️ 防御：(0,0) 是无效坐标，拦截请求防止 404
                      if (widget.lat == 0.0 && widget.lng == 0.0) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ 定位未就绪，无法创建围栏'),
                            backgroundColor: Colors.orange,
                          ),
                        );
                        return;
                      }
                      final controller =
                          ref.read(geofenceCreateControllerProvider.notifier);
                      controller.createGeofence(
                        name: _nameController.text.trim(),
                        lat: widget.lat,
                        lng: widget.lng,
                        radius: _radius,
                      );
                    },
              child: state.isLoading
                  ? const SizedBox(
                      height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('确认创建'),
            ),
          ),
        ],
      ),
    );
  }
}
