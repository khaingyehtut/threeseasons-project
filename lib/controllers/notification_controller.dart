import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/notification_model.dart';
import '../controllers/auth_controller.dart';

class NotificationController extends GetxController {
  final notifications = <NotificationModel>[].obs;
  final unreadCount = 0.obs;
  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    ever(Get.find<AuthController>().user, (user) {
      if (user != null) {
        _subscribe(user.id);
      } else {
        _sub?.cancel();
        notifications.clear();
        unreadCount.value = 0;
      }
    });
    // Also subscribe immediately if already logged in
    final u = Get.find<AuthController>().user.value;
    if (u != null && u.id.isNotEmpty) _subscribe(u.id);
  }

  void _subscribe(String userId) {
    _sub?.cancel();

    // Notifications are saved per-userId individually (including announcements),
    // so a simple equality query is sufficient for all user types.
    _sub = FirebaseFirestore.instance
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .listen((snap) {
      final list = snap.docs
          .map((d) => NotificationModel.fromDoc(d))
          .toList()
        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
      notifications.value = list;
      unreadCount.value = list.where((n) => !n.isRead).length;
    }, onError: (e) {
      debugPrint('[NotificationController] stream error: $e');
    });
  }

  Future<void> markAsRead(String notifId) async {
    await FirebaseFirestore.instance
        .collection('notifications')
        .doc(notifId)
        .update({'isRead': true});
  }

  Future<void> markAllAsRead() async {
    final userId = Get.find<AuthController>().user.value?.id ?? '';
    if (userId.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final n in notifications.where((n) => !n.isRead)) {
      batch.update(
        FirebaseFirestore.instance.collection('notifications').doc(n.id),
        {'isRead': true},
      );
    }
    await batch.commit();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}
