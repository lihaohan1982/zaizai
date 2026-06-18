// lib/core/messaging/offline_message_store.dart

import 'package:location_chat_app/core/messaging/message_payload.dart';

abstract class OfflineMessageStore {
  Future<void> saveForRetry(MessagePayload payload);
  Future<List<MessagePayload>> fetchPendingMessages(String userId);
  Future<void> markAsSent(String messageId);
}
