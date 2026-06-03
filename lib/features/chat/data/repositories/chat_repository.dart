import 'package:three_seasons_project/features/auth/data/models/user_model.dart';
import 'package:three_seasons_project/features/chat/data/models/message_model.dart';
import 'package:three_seasons_project/features/chat/domain/repositories/i_chat_repository.dart';
import 'package:three_seasons_project/services/chat_service.dart';

class ChatRepository implements IChatRepository {
  final ChatService _service;

  ChatRepository({ChatService? service}) : _service = service ?? ChatService();

  @override
  Stream<List<MessageModel>> messagesStream(String userId, String otherUserId) =>
      _service.messagesStream(userId, otherUserId);

  @override
  Future<Map<String, dynamic>> sendMessage(
    String senderId,
    String senderName,
    String senderAvatar,
    String receiverId,
    String content, {
    String type = 'text',
    String senderRole = 'user',
  }) =>
      _service.sendMessage(
        senderId,
        senderName,
        senderAvatar,
        receiverId,
        content,
        type: type,
        senderRole: senderRole,
      );

  @override
  Stream<List<Map<String, dynamic>>> conversationsStream(
    String userId, {
    bool adminOnly = false,
  }) =>
      _service.conversationsStream(userId, adminOnly: adminOnly);

  @override
  Future<void> setTyping(
          String conversationId, String userId, bool isTyping) =>
      _service.setTyping(conversationId, userId, isTyping);

  @override
  Stream<bool> typingStream(String conversationId, String otherUserId) =>
      _service.typingStream(conversationId, otherUserId);

  @override
  Future<void> markMessagesRead(
          String conversationId, String currentUserId) =>
      _service.markMessagesRead(conversationId, currentUserId);

  @override
  Future<List<UserModel>> getAdmins() => _service.getAdmins();

  @override
  Future<void> deleteMessage(String conversationId, String messageId) =>
      _service.deleteMessage(conversationId, messageId);
}
