enum MessageSource {
  manual('manual'),
  geofence('geofence'),
  poke('poke'),
  locationCard('location_card'),
  privacy('privacy');

  const MessageSource(this.value);
  final String value;
}

enum MessageStatus { sending, success, failed }

enum MessageType { quick, locationCard, system }

class MessagePayload {
  final String id;
  final String senderId;
  final String receiverId;
  final String? fenceId;
  final String contentKey;
  final String? customText;
  final MessageSource source;
  final String? lat;
  final String? lng;
  final DateTime timestamp;
  final MessageStatus status;
  final bool transient; // 标记是否为不落盘的瞬时消息（如拍一拍）
  final MessageType type;

  const MessagePayload({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.fenceId,
    required this.contentKey,
    this.customText,
    required this.source,
    this.lat,
    this.lng,
    required this.timestamp,
    this.status = MessageStatus.success,
    this.transient = false,
    this.type = MessageType.quick,
  });

  MessagePayload copyWith({MessageStatus? status}) {
    return MessagePayload(
      id: id,
      senderId: senderId,
      receiverId: receiverId,
      fenceId: fenceId,
      contentKey: contentKey,
      customText: customText,
      source: source,
      lat: lat,
      lng: lng,
      timestamp: timestamp,
      status: status ?? this.status,
      transient: transient,
      type: type,
    );
  }

  // 严格对齐服务端下划线命名规范
  factory MessagePayload.fromJson(Map<String, dynamic> json) {
    return MessagePayload(
      id: json['id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      fenceId: json['fence_id'] as String?,
      contentKey: json['content_key'] as String,
      customText: json['custom_text'] as String?,
      source: MessageSource.values.firstWhere(
        (e) => e.value == json['source'],
        orElse: () => MessageSource.manual,
      ),
      lat: json['lat']?.toString(),
      lng: json['lng']?.toString(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      status: json['is_failed'] == true ? MessageStatus.failed : MessageStatus.success,
      transient: json['transient'] == true,
      type: MessageType.values.firstWhere(
        (e) => e.name == (json['type'] ?? 'quick'),
        orElse: () => MessageType.quick,
      ),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'sender_id': senderId,
      'receiver_id': receiverId,
      'fence_id': fenceId,
      'content_key': contentKey,
      'custom_text': customText,
      'source': source.value,
      'lat': lat,
      'lng': lng,
      'timestamp': timestamp.toIso8601String(),
      'transient': transient,
      'type': type.name,
    };
  }
}
