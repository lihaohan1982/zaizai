// lib/core/messaging/offline_message_store_impl.dart
import 'package:location_chat_app/core/messaging/message_payload.dart';
import 'package:location_chat_app/core/messaging/offline_message_store.dart';

/// 内存版 OfflineMessageStore（开发阶段使用）
class InMemoryOfflineMessageStore implements OfflineMessageStore {
  final Map<String, List<MessagePayload>> _pending = {};

  @override
  Future<void> saveForRetry(MessagePayload payload) async {
    final key = payload.receiverId;
    _pending.putIfAbsent(key, () => []);
    _pending[key]!.add(payload);
  }

  @override
  Future<List<MessagePayload>> fetchPendingMessages(String userId) async {
    return _pending.remove(userId) ?? [];
  }

  @override
  Future<void> markAsSent(String messageId) async {
    for (final list in _pending.values) {
      list.removeWhere((m) => m.id == messageId);
    }
  }
}
