import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:get/get.dart';
import '../core/constants.dart';
import '../core/routes.dart';
import '../firebase_options.dart';

// ── Background / Terminated handler ──────────────────────────────────────────
// Must be a top-level (non-class) function and annotated with vm:entry-point.
// On web, background messages are handled by firebase-messaging-sw.js instead.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  debugPrint('[FCM-BG] type=${message.data['type']} id=${message.messageId}');

  // Show a local notification so the user sees it while the app is
  // in the background or fully terminated.
  if (kIsWeb) return; // web uses service worker — local plugin not available

  final title = message.notification?.title
      ?? message.data['title'] as String?
      ?? 'TSfootwear';
  final body  = message.notification?.body
      ?? message.data['body']  as String?
      ?? '';
  if (body.isEmpty) return;

  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    const InitializationSettings(
      android: AndroidInitializationSettings('ic_notification'),
      iOS:     DarwinInitializationSettings(),
    ),
  );

  await plugin.show(
    message.hashCode,
    title,
    body,
    NotificationDetails(
      android: AndroidNotificationDetails(
        'three_seasons_v3',
        'TSfootwear',
        channelDescription: 'Order and message notifications',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'ic_notification',
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('notification_sound'),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: jsonEncode(message.data),
  );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final _fcm = FirebaseMessaging.instance;

  // flutter_local_notifications is not supported on web — all calls are guarded by !kIsWeb
  final _localNotifications = FlutterLocalNotificationsPlugin();

  static const _channelId = 'three_seasons_v3';

  static const _androidChannel = AndroidNotificationChannel(
    'three_seasons_v3',
    'TSfootwear',
    description: 'Order and message notifications',
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('notification_sound'),
  );

  RemoteMessage? _pendingMessage;

  Future<void> init() async {
    // On web, Notification.requestPermission() requires a user gesture in
    // Chrome and cannot be called automatically on page load.
    if (!kIsWeb) {
      await _fcm.requestPermission(alert: true, badge: true, sound: true);
    }

    if (!kIsWeb) {
      // Android notification channel
      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(_androidChannel);

      // Local notifications (mobile only)
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        defaultPresentAlert: true,
        defaultPresentBadge: true,
        defaultPresentSound: true,
      );
      await _localNotifications.initialize(
        const InitializationSettings(
            android: androidSettings, iOS: iosSettings),
        onDidReceiveNotificationResponse: _onNotificationTap,
      );
    }

    // ── State 1 · FOREGROUND ─────────────────────────────────────────────────
    FirebaseMessaging.onMessage.listen(_showForegroundNotification);

    // ── State 2 · BACKGROUND (app alive, user taps notification) ────────────
    FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

    // ── State 3 · TERMINATED ─────────────────────────────────────────────────
    // On web this is handled by the service worker (firebase-messaging-sw.js)
    if (!kIsWeb) {
      _pendingMessage = await _fcm.getInitialMessage();
    }

    // ── Token refresh ────────────────────────────────────────────────────────
    _fcm.onTokenRefresh.listen((newToken) {
      debugPrint('[FCM] token refreshed — saving to Firestore');
      _onTokenRefreshed(newToken);
    });
  }

  void _onTokenRefreshed(String newToken) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null && uid.isNotEmpty) {
      _saveTokenToFirestore(uid, newToken);
    }
  }

  Future<void> _saveTokenToFirestore(String uid, String token) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({'fcmToken': token}, SetOptions(merge: true));
      debugPrint('[FCM] refreshed token saved for uid=$uid');
    } catch (e) {
      debugPrint('[FCM] save refreshed token failed: $e');
    }
  }

  void handlePendingMessage() {
    final msg = _pendingMessage;
    _pendingMessage = null;
    if (msg != null) {
      debugPrint(
          '[FCM] handling terminated-state message type=${msg.data['type']}');
      _handleNotificationTap(msg);
    }
  }

  // ── FCM Token ─────────────────────────────────────────────────────────────────

  Future<String?> getToken() async {
    try {
      final settings = await _fcm.getNotificationSettings();
      debugPrint('[FCM] permission status: ${settings.authorizationStatus}');
      // Web FCM requires a VAPID key — get it from:
      // Firebase Console → Project Settings → Cloud Messaging → Web Push certificates
      final token = kIsWeb
          ? await _fcm.getToken(vapidKey: AppConstants.fcmVapidKey)
          : await _fcm.getToken();
      debugPrint(
          '[FCM] token: ${token != null ? '${token.substring(0, 20)}…' : 'NULL'}');
      return token;
    } catch (e) {
      debugPrint('[FCM] getToken failed: $e');
      return null;
    }
  }

  Future<String> getTokenOrEmpty() async => (await getToken()) ?? '';

  // ── Foreground notification ───────────────────────────────────────────────────

  void _showForegroundNotification(RemoteMessage message) {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title'] as String?;
    final body = notification?.body ?? message.data['body'] as String?;
    if (title == null || body == null) return;

    // On web, the browser shows its own notification banner — no local plugin needed
    if (kIsWeb) return;

    _localNotifications.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'TSfootwear',
          channelDescription: 'Order and message notifications',
          importance: Importance.max,
          priority: Priority.high,
          icon: 'ic_notification',
          color: const Color(0xFF6C63FF),
          sound: const RawResourceAndroidNotificationSound('notification_sound'),
          playSound: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          sound: 'notification_sound.aiff',
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  // ── Tap navigation ─────────────────────────────────────────────────────────────

  void _onNotificationTap(NotificationResponse response) {
    if (response.payload == null) return;
    try {
      final data = jsonDecode(response.payload!) as Map<String, dynamic>;
      _navigate(data);
    } catch (_) {}
  }

  void _handleNotificationTap(RemoteMessage message) {
    _navigate(message.data);
  }

  void _navigate(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    switch (type) {
      case 'message':
        Get.toNamed(AppRoutes.chat, arguments: {
          'userId': data['senderId'] ?? '',
          'userName': data['senderName'] ?? '',
          'userAvatar': data['senderAvatar'] ?? '',
        });
        break;
      case 'order_placed':
      case 'order_status':
        final orderId = data['orderId'] ?? '';
        if (orderId.isNotEmpty) {
          Get.toNamed(AppRoutes.orderDetail, arguments: orderId);
        }
        break;
    }
  }

  // ── Send helpers (called from controllers) ────────────────────────────────────

  final _dio = Dio(BaseOptions(
    baseUrl: AppConstants.socketUrl,
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
  ));

  Future<void> sendToToken({
    required String token,
    required String title,
    required String body,
    required String firebaseIdToken,
    Map<String, String> data = const {},
  }) async {
    final response = await _dio.post(
      '/api/notifications/send',
      data: {'token': token, 'title': title, 'body': body, 'data': data},
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );
    debugPrint('[FCM] sendToToken result: ${response.data}');
  }

  Future<void> sendToAdmins({
    required String title,
    required String body,
    required String firebaseIdToken,
    Map<String, String> data = const {},
  }) async {
    final response = await _dio.post(
      '/api/notifications/send-to-admins',
      data: {'title': title, 'body': body, 'data': data},
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );
    debugPrint('[FCM] sendToAdmins result: ${response.data}');
  }

  Future<void> sendToAllUsers({
    required String title,
    required String body,
    required String firebaseIdToken,
    Map<String, String> data = const {},
  }) async {
    final response = await _dio.post(
      '/api/notifications/send-to-users',
      data: {'title': title, 'body': body, 'data': data},
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );
    debugPrint('[FCM] sendToAllUsers result: ${response.data}');
  }

  // ── Backend health check ──────────────────────────────────────────────────────

  Future<bool> isBackendReachable() async {
    try {
      final res = await _dio.get('/api/health',
          options: Options(receiveTimeout: const Duration(seconds: 4)));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
