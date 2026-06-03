import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../services/notification_service.dart';
import '../services/socket_service.dart';

class ChatController extends GetxController {
  final _chatService = ChatService();
  final _socketService = SocketService();

  final messages = <MessageModel>[].obs;
  final conversations = <Map<String, dynamic>>[].obs;
  final admins = <UserModel>[].obs;
  final isLoading = false.obs;
  final isOtherUserTyping = false.obs;
  final error = Rxn<String>();

  StreamSubscription<List<MessageModel>>? _messagesSub;
  StreamSubscription<List<Map<String, dynamic>>>? _conversationsSub;
  String? _activeOtherUserId;
  String? _activeConversationId;

  @override
  void onClose() {
    _messagesSub?.cancel();
    _conversationsSub?.cancel();
    _socketService.offTypingEvents();
    _socketService.offMessageEvents();
    super.onClose();
  }

  // ─── Typing (Socket.IO) ───────────────────────────────────────────────────────

  void subscribeToTyping(String conversationId, String otherUserId) {
    _activeConversationId = conversationId;

    // Clear existing listeners before re-registering
    _socketService.offTypingEvents();
    _socketService.offMessageEvents();

    // Connect + join room — socket is guaranteed to exist after this call
    _socketService.joinConversation(conversationId);

    // Typing events
    _socketService.onTyping((data) {
      final uid = (data as Map)['userId']?.toString() ?? '';
      if (uid == otherUserId) isOtherUserTyping.value = true;
    });

    _socketService.onStopTyping((data) {
      final uid = (data as Map)['userId']?.toString() ?? '';
      if (uid == otherUserId) isOtherUserTyping.value = false;
    });

    // Incoming messages via socket (registered here so socket is already connected)
    _socketService.onNewMessage((data) {
      final map = Map<String, dynamic>.from(data as Map);
      final incoming = MessageModel.fromJson(map);
      if (!messages.any((m) => m.id == incoming.id)) {
        messages.add(incoming);
      }
    });
  }

  void cancelTypingSubscription() {
    if (_activeConversationId != null) {
      _socketService.leaveConversation(_activeConversationId!);
      _activeConversationId = null;
    }
    _socketService.offTypingEvents();
    _socketService.offMessageEvents();
    isOtherUserTyping.value = false;
  }

  void setTyping(String conversationId, String userId, bool isTyping) {
    if (isTyping) {
      _socketService.emitTyping(conversationId, userId);
    } else {
      _socketService.emitStopTyping(conversationId, userId);
    }
  }

  // ─── Messages ─────────────────────────────────────────────────────────────────

  void subscribeToMessages(String userId, String otherUserId) {
    if (_activeOtherUserId == otherUserId) return;
    _messagesSub?.cancel();
    _activeOtherUserId = otherUserId;
    messages.clear();

    // Firestore stream — source of truth for message history
    _messagesSub = _chatService
        .messagesStream(userId, otherUserId)
        .listen(
          (msgs) => messages.value = msgs,
          onError: (e) => error.value = e.toString(),
        );
    // Socket message listener is registered in subscribeToTyping
    // (called right after this in initChat) so the socket is guaranteed connected
  }

  void unsubscribeFromMessages() {
    _messagesSub?.cancel();
    _messagesSub = null;
    _activeOtherUserId = null;
    _socketService.offMessageEvents();
    messages.clear();
  }

  // ─── Conversations ────────────────────────────────────────────────────────────

  void subscribeToConversations(String userId, {String role = 'user'}) {
    _conversationsSub?.cancel();
    _conversationsSub = _chatService
        .conversationsStream(userId, adminOnly: role != 'admin')
        .listen(
          (convs) => conversations.value = convs,
          onError: (e) => error.value = e.toString(),
        );
  }

  void unsubscribeFromConversations() {
    _conversationsSub?.cancel();
    _conversationsSub = null;
  }

  // ─── Send / Read / Delete ─────────────────────────────────────────────────────

  Future<bool> sendMessage(
    String senderId,
    String senderName,
    String senderAvatar,
    String receiverId,
    String content, {
    String type = 'text',
    String senderRole = 'user',
  }) async {
    try {
      final socketMsg = await _chatService.sendMessage(
        senderId,
        senderName,
        senderAvatar,
        receiverId,
        content,
        type: type,
        senderRole: senderRole,
      );
      // Emit via socket for instant delivery
      final convId = socketMsg['conversationId'] as String;
      _socketService.emitMessage(convId, socketMsg);

      // Push notification to receiver
      _sendMessageNotification(
        senderId: senderId,
        senderName: senderName,
        senderAvatar: senderAvatar,
        receiverId: receiverId,
        content: content,
      );
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    }
  }

  Future<void> _sendMessageNotification({
    required String senderId,
    required String senderName,
    required String senderAvatar,
    required String receiverId,
    required String content,
  }) async {
    // Never notify yourself
    if (senderId == receiverId) return;

    try {
      final token = await AuthService().getIdToken();
      if (token == null) return;

      // Fetch both tokens in parallel
      final results = await Future.wait([
        FirebaseFirestore.instance.collection('users').doc(receiverId).get(),
        FirebaseFirestore.instance.collection('users').doc(senderId).get(),
      ]);

      final receiverFcmToken = results[0].data()?['fcmToken'] as String?;
      final senderFcmToken   = results[1].data()?['fcmToken'] as String?;

      if (receiverFcmToken == null || receiverFcmToken.isEmpty) return;

      // Skip if sender and receiver share the same device (same FCM token)
      if (receiverFcmToken == senderFcmToken) return;

      await NotificationService().sendToToken(
        token: receiverFcmToken,
        title: senderName,
        body: content,
        firebaseIdToken: token,
        data: {
          'type': 'message',
          'senderId': senderId,
          'senderName': senderName,
          'senderAvatar': senderAvatar,
        },
      );
    } catch (e) {
      debugPrint('[Notification] message notify failed: $e');
    }
  }

  Future<void> markRead(String conversationId, String currentUserId) async {
    try {
      await _chatService.markMessagesRead(conversationId, currentUserId);
    } catch (e) {
      debugPrint('ChatController.markRead error: $e');
    }
  }

  Future<void> fetchAdmins() async {
    isLoading.value = true;
    try {
      admins.value = await _chatService.getAdmins();
    } catch (e) {
      error.value = e.toString();
      debugPrint('ChatController.fetchAdmins error: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> editMessage(
      String conversationId, String messageId, String newContent) async {
    try {
      await _chatService.editMessage(conversationId, messageId, newContent);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    }
  }

  Future<bool> deleteMessage(String conversationId, String messageId) async {
    try {
      await _chatService.deleteMessage(conversationId, messageId);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    }
  }

  void resetChat() {
    _messagesSub?.cancel();
    _conversationsSub?.cancel();
    _messagesSub = null;
    _conversationsSub = null;
    messages.clear();
    conversations.clear();
    admins.clear();
    isOtherUserTyping.value = false;
    _activeOtherUserId = null;
    _activeConversationId = null;
    _socketService.offTypingEvents();
    _socketService.offMessageEvents();
    error.value = null;
  }

  void clearError() => error.value = null;
}
