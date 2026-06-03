import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationModel {
  final String id;
  final String userId;
  final String title;
  final String body;
  final String type;
  final Map<String, dynamic> data;
  final bool isRead;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    this.type = 'custom',
    this.data = const {},
    this.isRead = false,
    required this.createdAt,
  });

  factory NotificationModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    DateTime createdAt = DateTime.now();
    final raw = d['createdAt'];
    if (raw is Timestamp) createdAt = raw.toDate();
    return NotificationModel(
      id: doc.id,
      userId: d['userId'] ?? '',
      title: d['title'] ?? '',
      body: d['body'] ?? '',
      type: d['type'] ?? 'custom',
      data: Map<String, dynamic>.from(d['data'] as Map? ?? {}),
      isRead: d['isRead'] ?? false,
      createdAt: createdAt,
    );
  }

  // Notification type အလိုက် Firebase TTL ရက်များ သတ်မှတ်ခြင်း
  static int _daysToKeep(String type) {
    switch (type) {
      case 'processing':
        return 3;   // အော်ဒါပြင်ဆင်ဆဲ - DB မပွအောင် ၃ ရက်
      case 'promo':
        return 7;   // ပရိုမိုးရှင်း - ၇ ရက်
      case 'order_placed':
        return 7;   // Admin ဘက် - Dashboard မှာ ကြည့်နိုင်လို့ ၇ ရက်ပဲ လုံလောက်
      case 'shipping':
      case 'order_success':
      case 'order_status':
        return 2;   // အော်ဒါ အပ်ဒိတ် - ၂ ရက်သာ သိမ်းမည်
      case 'system':
        return 90;  // လုံခြုံရေး/စနစ်ဆိုင်ရာ - ၉၀ ရက်
      default:
        return 30;
    }
  }

  static Future<void> save({
    required String userId,
    required String title,
    required String body,
    String type = 'custom',
    Map<String, dynamic> data = const {},
  }) async {
    final now = DateTime.now();
    // **အရေးကြီး** Firebase TTL က ဤ field ကြည့်ပြီး auto-delete လုပ်သည်
    final expireAt = now.add(Duration(days: _daysToKeep(type)));

    await FirebaseFirestore.instance.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'data': data,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
      'expireAt': Timestamp.fromDate(expireAt),
    });
  }
}
