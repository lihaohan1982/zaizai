// lib/features/chat/pages/add_friend_page.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:location_chat_app/core/providers.dart';

/// 添加好友页面（搜索手机号 + 发送请求）
///
/// 后端 API：
///   - POST /api/friends/search?phone=13800138000 → 搜索用户
///   - POST /api/friends/request → 发送好友请求 {target_phone, message}
///   - GET /api/friends/requests → 获取待处理请求列表
///   - POST /api/friends/accept/:id → 接受请求
///   - POST /api/friends/reject/:id → 拒绝请求
class AddFriendPage extends ConsumerStatefulWidget {
  const AddFriendPage({super.key});

  @override
  ConsumerState<AddFriendPage> createState() => _AddFriendPageState();
}

class _AddFriendPageState extends ConsumerState<AddFriendPage> {
  final _phoneController = TextEditingController();
  // message 字段暂未使用（后端不支持）
  bool _searching = false;
  Map<String, dynamic>? _searchResult;
  String? _error;

  @override
  void dispose() {
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _searchUser() async {
    final phone = _phoneController.text.trim();
    if (phone.isEmpty || phone.length != 11) {
      setState(() => _error = '请输入11位手机号');
      return;
    }

    setState(() {
      _searching = true;
      _error = null;
      _searchResult = null;
    });

    try {
      final dioClient = ref.read(dioClientProvider);
      // 后端用 GET /api/friends/add?phone=xxx 搜索+发送请求
      // 如果用户不存在返回404，已存在返回400
      final response = await dioClient.dio.get(
        '/api/friends/add',
        queryParameters: {'phone': phone},
      );
      final wrapper = response.data as Map<String, dynamic>;
      if (wrapper['code'] == 0) {
        // 请求发送成功，直接显示成功提示
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('好友请求已发送'), backgroundColor: Colors.green),
          );
          ref.invalidate(friendListProvider);
          ref.invalidate(_friendRequestsProvider);
          Navigator.pop(context);
        }
      } else {
        setState(() => _error = wrapper['message']?.toString() ?? '操作失败');
      }
    } on DioException catch (e) {
      final detail = e.response?.data;
      if (detail is Map) {
        setState(() => _error = detail['detail']?.toString() ?? '操作失败');
      } else {
        setState(() => _error = '操作失败: $e');
      }
    } catch (e) {
      setState(() => _error = '操作失败: $e');
    } finally {
      setState(() => _searching = false);
    }
  }

  // 注：后端 /api/friends/add 同时执行搜索+发送请求，无需单独发送步骤

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('添加好友')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: '手机号',
                hintText: '请输入对方手机号',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              maxLength: 11,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _searching ? null : _searchUser,
              icon: _searching
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(_searching ? '搜索中...' : '搜索用户'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 13)),
              ),

            // 搜索结果
            if (_searchResult != null) ...[
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 12),
              _buildSearchResult(),
            ],

            const SizedBox(height: 32),
            const Divider(),
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 8),
              child: Text('好友请求', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            _FriendRequestsList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResult() {
    final user = _searchResult!;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade100,
          child: Text((user['nickname'] as String?)?.substring(0, 1) ?? '?'),
        ),
        title: Text(user['nickname'] ?? user['phone'] ?? '未知用户'),
        subtitle: Text(user['phone'] ?? ''),
      ),
    );
  }
}

/// 好友请求列表（接受/拒绝）
class _FriendRequestsList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(_friendRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Text('加载失败: $err', style: const TextStyle(color: Colors.red)),
      data: (requests) {
        if (requests.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('暂无好友请求', style: TextStyle(color: Colors.grey)),
          );
        }
        return Column(
          children: requests.map((req) {
            final id = req['id']?.toString();
            final nickname = req['nickname'] ?? req['phone'] ?? '未知';
            final phone = req['phone'] ?? '';

            return Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: Colors.green.shade100,
                  child: Text(nickname.substring(0, 1)),
                ),
                title: Text(nickname),
                subtitle: Text(phone),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      tooltip: '接受',
                      onPressed: id != null ? () => _handleRequest(ref, id, true) : null,
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.red),
                      tooltip: '拒绝',
                      onPressed: id != null ? () => _handleRequest(ref, id, false) : null,
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Future<void> _handleRequest(WidgetRef ref, String requestId, bool accept) async {
    try {
      final dioClient = ref.read(dioClientProvider);
      // 后端用 GET /api/friends/accept?friendship_id=xxx
      final response = await dioClient.dio.get(
        '/api/friends/accept',
        queryParameters: {'friendship_id': requestId},
      );
      final wrapper = response.data as Map<String, dynamic>;
      if (wrapper['code'] == 0) {
        ref.invalidate(_friendRequestsProvider);
        ref.invalidate(friendListProvider);
      }
    } catch (_) {}
  }
}

/// 好友请求列表 Provider
final _friendRequestsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final dioClient = ref.read(dioClientProvider);
  try {
    final response = await dioClient.dio.get('/api/friends/requests');
    final wrapper = response.data as Map<String, dynamic>;
    if (wrapper['code'] == 0) {
      final List<dynamic> raw = wrapper['data'] ?? [];
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
  } catch (_) {}
  return [];
});
