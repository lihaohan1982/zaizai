import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:location_chat_app/core/providers.dart';

/// P4：围栏事件历史页面
///
/// 修正点：
///   - 事件类型判断使用 `event['event_type'] == 'enter'`（对齐后端真实字段）
///   - 时间字段安全取值 `event['timestamp'] ?? event['created_at']`
///   - `DateTime.tryParse` 防止格式异常导致崩溃
class FenceEventHistoryPage extends ConsumerWidget {
  final String fenceId;
  final String fenceName;

  const FenceEventHistoryPage({
    super.key,
    required this.fenceId,
    required this.fenceName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final eventsAsync = ref.watch(fenceEventsProvider(fenceId));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('$fenceName - 事件历史',
            style: const TextStyle(color: Colors.white)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: eventsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: Colors.white54)),
        error: (e, _) => Center(
            child: Text('加载失败: $e',
                style: const TextStyle(color: Colors.redAccent))),
        data: (events) {
          if (events.isEmpty) {
            return const Center(
                child: Text('暂无事件',
                    style: TextStyle(color: Colors.white54)));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16),
            itemCount: events.length,
            itemBuilder: (context, index) {
              final event = events[index];

              // 【修正一】对齐后端真实字段 event_type: 'enter' / 'exit'
              final isEnter = event['event_type'] == 'enter';

              // 【修正二】安全获取时间字段，兼容 timestamp 或 created_at
              final timeStr = event['timestamp'] ?? event['created_at'];
              final time =
                  timeStr != null ? DateTime.tryParse(timeStr) : null;

              return ListTile(
                leading: Icon(
                  isEnter ? Icons.login : Icons.logout,
                  color: isEnter ? Colors.greenAccent : Colors.orangeAccent,
                ),
                title: Text(
                  isEnter ? '进入围栏' : '离开围栏',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  time != null
                      ? DateFormat('yyyy-MM-dd HH:mm').format(time)
                      : '未知时间',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
