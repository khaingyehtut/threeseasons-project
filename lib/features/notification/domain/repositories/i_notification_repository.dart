import 'package:three_seasons_project/features/notification/data/models/notification_model.dart';

abstract class INotificationRepository {
  Stream<List<NotificationModel>> notificationsStream(String userId);
  Future<void> markAsRead(String notificationId);
  Future<void> markAllAsRead(String userId);
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String body,
    String type,
    Map<String, dynamic> data,
  });
}
