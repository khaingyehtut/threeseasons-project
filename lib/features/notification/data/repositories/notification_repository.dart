import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:three_seasons_project/features/notification/data/models/notification_model.dart';
import 'package:three_seasons_project/features/notification/domain/repositories/i_notification_repository.dart';

class NotificationRepository implements INotificationRepository {
  final FirebaseFirestore _db;

  NotificationRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  @override
  Stream<List<NotificationModel>> notificationsStream(String userId) {
    // Include 'all' broadcast notifications (promos, system) alongside personal ones
    return _db
        .collection('notifications')
        .where('userId', whereIn: [userId, 'all'])
        .snapshots()
        .map((snap) {
          final list = snap.docs.map(NotificationModel.fromDoc).toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _db
        .collection('notifications')
        .doc(notificationId)
        .update({'isRead': true});
  }

  @override
  Future<void> markAllAsRead(String userId) async {
    final snap = await _db
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();

    final batch = _db.batch();
    for (final doc in snap.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  @override
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'custom',
    Map<String, dynamic> data = const {},
  }) =>
      NotificationModel.save(
        userId: userId,
        title: title,
        body: body,
        type: type,
        data: data,
      );
}
