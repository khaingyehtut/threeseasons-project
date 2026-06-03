import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/message_model.dart';
import '../models/user_model.dart';

class ChatService {
  static final ChatService _instance = ChatService._internal();
  factory ChatService() => _instance;
  ChatService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Deterministic conversation ID — same for both participants
  String _conversationId(String uid1, String uid2) {
    final sorted = [uid1, uid2]..sort();
    return sorted.join('_');
  }

  // ─── Real-time Messages Stream ────────────────────────────────────────────────

  Stream<List<MessageModel>> messagesStream(
    String userId,
    String otherUserId,
  ) {
    final convId = _conversationId(userId, otherUserId);
    return _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('createdAt')
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => _messageFromDoc(doc, convId))
            .toList());
  }

  // ─── Send Message ─────────────────────────────────────────────────────────────

  /// Saves message to Firestore and returns a socket-ready map for instant delivery.
  Future<Map<String, dynamic>> sendMessage(
    String senderId,
    String senderName,
    String senderAvatar,
    String receiverId,
    String content, {
    String type = 'text',
    String senderRole = 'user',
  }) async {
    final convId = _conversationId(senderId, receiverId);
    final now = FieldValue.serverTimestamp();

    // Generate the Firestore doc reference before committing so we have the ID
    final msgRef = _db
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .doc();

    final messageData = {
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'senderRole': senderRole,
      'receiverId': receiverId,
      'content': content,
      'type': type,
      'isRead': false,
      'isDeleted': false,
      'createdAt': now,
    };

    final batch = _db.batch();
    batch.set(msgRef, messageData);

    final convRef = _db.collection('conversations').doc(convId);
    batch.set(
      convRef,
      {
        'participants': [senderId, receiverId],
        'lastMessage': content,
        'lastMessageAt': now,
        'lastSenderId': senderId,
        'unreadCounts.$receiverId': FieldValue.increment(1),
      },
      SetOptions(merge: true),
    );

    await batch.commit();

    // Return socket-ready map — uses epoch ms instead of Firestore Timestamp
    return {
      'id': msgRef.id,
      'conversationId': convId,
      'senderId': senderId,
      'senderName': senderName,
      'senderAvatar': senderAvatar,
      'senderRole': senderRole,
      'receiverId': receiverId,
      'content': content,
      'type': type,
      'isRead': false,
      'createdAt': DateTime.now().toIso8601String(),
    };
  }

  // ─── Conversations Stream ─────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> conversationsStream(
    String userId, {
    bool adminOnly = false,
  }) {
    return _db
        .collection('conversations')
        .where('participants', arrayContains: userId)
        .snapshots()
        .asyncMap((snapshot) async {
          final futures = snapshot.docs.map((doc) async {
            final data = Map<String, dynamic>.from(doc.data());
            data['id'] = doc.id;

            // Normalize timestamp and add updatedAt alias
            final rawTs = data['lastMessageAt'];
            String? isoTs;
            if (rawTs is Timestamp) {
              isoTs = rawTs.toDate().toIso8601String();
            } else if (rawTs is String) {
              isoTs = rawTs;
            }
            if (isoTs != null) {
              data['lastMessageAt'] = isoTs;
              data['updatedAt'] = isoTs;
            }

            // Per-user unread count
            final unreadCounts =
                Map<String, dynamic>.from(data['unreadCounts'] as Map? ?? {});
            data['unreadCount'] =
                (unreadCounts[userId] as num?)?.toInt() ?? 0;

            // Fetch the other participant's user data
            final participants =
                List<String>.from(data['participants'] ?? []);
            final otherUserId = participants.firstWhere(
              (id) => id != userId,
              orElse: () =>
                  participants.isNotEmpty ? participants.first : '',
            );

            if (otherUserId.isNotEmpty) {
              try {
                final userDoc = await _db
                    .collection('users')
                    .doc(otherUserId)
                    .get();
                if (userDoc.exists) {
                  final ud =
                      Map<String, dynamic>.from(userDoc.data()!);
                  data['otherUser'] = {
                    '_id': otherUserId,
                    'id': otherUserId,
                    'name': ud['name'] ?? 'Unknown',
                    'avatar': ud['avatar'] ?? '',
                    'role': ud['role'] ?? 'user',
                    'isOnline': ud['isOnline'] ?? false,
                  };
                }
              } catch (_) {}
            }

            return data;
          });

          final results = await Future.wait(futures);

          // If adminOnly, drop any conversation where the other side is not an admin
          final filtered = adminOnly
              ? results.where((c) {
                  final role =
                      (c['otherUser'] as Map?)?['role'] as String? ?? 'user';
                  return role == 'admin';
                }).toList()
              : results;

          // Sort by lastMessageAt descending (avoids composite index requirement)
          filtered.sort((a, b) {
            final aTs = a['lastMessageAt'] as String? ?? '';
            final bTs = b['lastMessageAt'] as String? ?? '';
            return bTs.compareTo(aTs);
          });
          return filtered;
        });
  }

  // ─── Typing Indicator ────────────────────────────────────────────────────────

  Future<void> setTyping(
      String conversationId, String userId, bool isTyping) async {
    await _db.collection('conversations').doc(conversationId).set(
      {'typing': {userId: isTyping}},
      SetOptions(merge: true),
    );
  }

  Stream<bool> typingStream(String conversationId, String otherUserId) {
    return _db
        .collection('conversations')
        .doc(conversationId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return false;
      final typing =
          (doc.data()!['typing'] as Map<String, dynamic>?) ?? {};
      return typing[otherUserId] == true;
    });
  }

  // ─── Mark Messages as Read ────────────────────────────────────────────────────

  Future<void> markMessagesRead(
    String conversationId,
    String currentUserId,
  ) async {
    final unreadSnapshot = await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .where('receiverId', isEqualTo: currentUserId)
        .where('isRead', isEqualTo: false)
        .get();

    if (unreadSnapshot.docs.isEmpty) return;

    final batch = _db.batch();
    for (final doc in unreadSnapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }

    // Reset only this user's unread count
    batch.update(
      _db.collection('conversations').doc(conversationId),
      {'unreadCounts.$currentUserId': 0},
    );

    await batch.commit();
  }

  // ─── Get Admins ───────────────────────────────────────────────────────────────

  Future<List<UserModel>> getAdmins() async {
    final snapshot = await _db
        .collection('users')
        .where('role', isEqualTo: 'admin')
        .get();

    return snapshot.docs.map((doc) => _userFromDoc(doc)).toList();
  }

  // ─── Edit Message ─────────────────────────────────────────────────────────────

  Future<void> editMessage(
    String conversationId,
    String messageId,
    String newContent,
  ) async {
    await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({'content': newContent, 'isEdited': true});
  }

  // ─── Delete Message (soft delete) ────────────────────────────────────────────

  Future<void> deleteMessage(
    String conversationId,
    String messageId,
  ) async {
    await _db
        .collection('conversations')
        .doc(conversationId)
        .collection('messages')
        .doc(messageId)
        .update({
      'isDeleted': true,
      'content': 'This message was deleted',
    });
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  MessageModel _messageFromDoc(DocumentSnapshot doc, String convId) {
    final data = Map<String, dynamic>.from(doc.data() as Map);

    DateTime createdAt = DateTime.now();
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    }

    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      receiverId: data['receiverId'] ?? '',
      senderName: data['senderName'] ?? '',
      senderAvatar: data['senderAvatar'] ?? '',
      senderRole: data['senderRole'] ?? 'user',
      content: data['content'] ?? '',
      type: data['type'] ?? 'text',
      isRead: data['isRead'] ?? false,
      conversationId: convId,
      createdAt: createdAt,
    );
  }

  UserModel _userFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);

    DateTime? lastSeen;
    final rawLastSeen = data['lastSeen'];
    if (rawLastSeen is Timestamp) {
      lastSeen = rawLastSeen.toDate();
    }

    return UserModel(
      id: doc.id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      role: data['role'] ?? 'user',
      avatar: data['avatar'] ?? '',
      phone: data['phone'] ?? '',
      isOnline: data['isOnline'] ?? false,
      lastSeen: lastSeen,
    );
  }
}
