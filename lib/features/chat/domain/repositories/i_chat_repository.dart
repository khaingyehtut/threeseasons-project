import 'package:three_seasons_project/features/chat/data/models/message_model.dart';
import 'package:three_seasons_project/features/auth/data/models/user_model.dart';

abstract class IChatRepository {
  Stream<List<MessageModel>> messagesStream(String userId, String otherUserId);
  Future<Map<String, dynamic>> sendMessage(
    String senderId,
    String senderName,
    String senderAvatar,
    String receiverId,
    String content, {
    String type,
    String senderRole,
  });
  Stream<List<Map<String, dynamic>>> conversationsStream(String userId, {bool adminOnly});
  Future<void> setTyping(String conversationId, String userId, bool isTyping);
  Stream<bool> typingStream(String conversationId, String otherUserId);
  Future<void> markMessagesRead(String conversationId, String currentUserId);
  Future<List<UserModel>> getAdmins();
  Future<void> deleteMessage(String conversationId, String messageId);
}
