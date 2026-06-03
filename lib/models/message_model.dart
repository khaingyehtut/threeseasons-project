class MessageModel {
  final String id;
  final String senderId;
  final String receiverId;
  final String senderName;
  final String senderAvatar;
  final String senderRole;
  final String content;
  final String type;
  final bool isRead;
  final bool isEdited;
  final String conversationId;
  final DateTime createdAt;

  const MessageModel({
    required this.id,
    required this.senderId,
    required this.receiverId,
    this.senderName = '',
    this.senderAvatar = '',
    this.senderRole = 'user',
    required this.content,
    this.type = 'text',
    this.isRead = false,
    this.isEdited = false,
    this.conversationId = '',
    required this.createdAt,
  });

  bool isFromMe(String userId) => senderId == userId;

  factory MessageModel.fromJson(Map<String, dynamic> json) {
    String senderId = json['senderId']?.toString() ?? '';
    String senderName = json['senderName']?.toString() ?? '';
    String senderAvatar = json['senderAvatar']?.toString() ?? '';
    String senderRole = json['senderRole']?.toString() ?? 'user';
    String receiverId = json['receiverId']?.toString() ?? '';

    if (senderId.isEmpty) {
      final rawSender = json['sender'];
      if (rawSender is Map<String, dynamic>) {
        senderId = rawSender['_id'] ?? rawSender['id'] ?? '';
        senderName = rawSender['name'] ?? '';
        senderAvatar = rawSender['avatar'] ?? '';
        senderRole = rawSender['role'] ?? 'user';
      } else if (rawSender is String) {
        senderId = rawSender;
      }
    }

    if (receiverId.isEmpty) {
      final rawReceiver = json['receiver'];
      if (rawReceiver is Map<String, dynamic>) {
        receiverId = rawReceiver['_id'] ?? rawReceiver['id'] ?? '';
      } else if (rawReceiver is String) {
        receiverId = rawReceiver;
      }
    }

    DateTime parsedDate = DateTime.now();
    final rawDate = json['createdAt'];
    if (rawDate is String && rawDate.isNotEmpty) {
      parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
    }

    return MessageModel(
      id: json['id'] ?? json['_id'] ?? '',
      senderId: senderId,
      receiverId: receiverId,
      senderName: senderName,
      senderAvatar: senderAvatar,
      senderRole: senderRole,
      content: json['content'] ?? '',
      type: json['type'] ?? 'text',
      isRead: json['isRead'] ?? false,
      isEdited: json['isEdited'] ?? false,
      conversationId: json['conversationId'] ?? '',
      createdAt: parsedDate,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'sender': {
          '_id': senderId,
          'name': senderName,
          'avatar': senderAvatar,
          'role': senderRole,
        },
        'receiver': receiverId,
        'content': content,
        'type': type,
        'isRead': isRead,
        'conversationId': conversationId,
        'createdAt': createdAt.toIso8601String(),
      };

  MessageModel copyWith({
    String? id,
    String? senderId,
    String? receiverId,
    String? senderName,
    String? senderAvatar,
    String? senderRole,
    String? content,
    String? type,
    bool? isRead,
    String? conversationId,
    DateTime? createdAt,
  }) {
    return MessageModel(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      senderName: senderName ?? this.senderName,
      senderAvatar: senderAvatar ?? this.senderAvatar,
      senderRole: senderRole ?? this.senderRole,
      content: content ?? this.content,
      type: type ?? this.type,
      isRead: isRead ?? this.isRead,
      conversationId: conversationId ?? this.conversationId,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
