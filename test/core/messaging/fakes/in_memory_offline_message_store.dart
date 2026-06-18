// test/core/messaging/fakes/in_memory_offline_message_store.dart

import 'package:location_chat_app/core/messaging/offline_message_store.dart';
import 'package:location_chat_app/core/messaging/message_payload.dart';

class InMemoryOfflineMessageStore implements OfflineMessageStore {
  final List<MessagePayload> _pending = [];

  List<MessagePayload> get pending => List.unmodifiable(_pending);
  int get pendingCount => _pending.length;

  @override
  Future<void> saveForRetry(MessagePayload message) async {
    _pending.add(message);
  }

  @override
  Future<List<MessagePayload>> fetchPendingMessages(String userId) async {
    return _pending.where((msg) => msg.receiverId == userId).toList();
  }

  @override
  Future<void> markAsSent(String messageId) async {
    _pending.removeWhere((m) => m.id == messageId);
  }

  void clear() {
    _pending.clear();
  }
}
