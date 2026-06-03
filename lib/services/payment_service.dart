import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../core/constants.dart';
import '../models/payment_model.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final _dio = Dio(BaseOptions(
    baseUrl: AppConstants.socketUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
    sendTimeout:    const Duration(seconds: 30),
  ));

  // ── Upload screenshot + create payment record ─────────────────────────────

  Future<PaymentModel> submitPayment({
    required Uint8List screenshotBytes,
    required String screenshotFilename,
    required double amount,
    required String paymentMethod,
    required String firebaseIdToken,
    String? orderId,
    String note = '',
  }) async {
    final formData = FormData.fromMap({
      'screenshot': MultipartFile.fromBytes(
        screenshotBytes,
        filename: screenshotFilename,
      ),
      'amount':        amount.toString(),
      'paymentMethod': paymentMethod,
      if (orderId != null) 'orderId': orderId,
      if (note.isNotEmpty) 'note': note,
    });

    final response = await _dio.post(
      '/api/payments/upload',
      data: formData,
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );

    final paymentId = response.data['paymentId'] as String;
    final doc = await FirebaseFirestore.instance
        .collection('payments')
        .doc(paymentId)
        .get();
    return PaymentModel.fromDoc(doc);
  }

  // ── Admin: approve ────────────────────────────────────────────────────────

  Future<void> approvePayment(
    String paymentId,
    String firebaseIdToken, {
    String adminNote = '',
  }) async {
    await _dio.patch(
      '/api/payments/$paymentId/approve',
      data: {'adminNote': adminNote},
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );
  }

  // ── Admin: reject ─────────────────────────────────────────────────────────

  Future<void> rejectPayment(
    String paymentId,
    String firebaseIdToken, {
    String adminNote = '',
  }) async {
    await _dio.patch(
      '/api/payments/$paymentId/reject',
      data: {'adminNote': adminNote},
      options: Options(headers: {'Authorization': 'Bearer $firebaseIdToken'}),
    );
  }

  // ── Stream for user's own payments ────────────────────────────────────────

  Stream<List<PaymentModel>> userPaymentsStream(String userId) {
    return FirebaseFirestore.instance
        .collection('payments')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map(PaymentModel.fromDoc).toList())
        .handleError((e) {
          debugPrint('[PaymentService] stream error: $e');
          return <PaymentModel>[];
        });
  }

  // ── Payment account settings ─────────────────────────────────────────────

  static const _settingsPath = 'settings/payment_accounts';

  Stream<Map<String, String>> accountSettingsStream() {
    return FirebaseFirestore.instance
        .doc(_settingsPath)
        .snapshots()
        .map((snap) {
      final d = snap.data() ?? {};
      return {
        'kpayNumber': (d['kpayNumber'] ?? '09-XXX-XXX-XXX').toString(),
        'kpayName':   (d['kpayName']   ?? 'TSfootwear').toString(),
        'waveNumber': (d['waveNumber'] ?? '09-XXX-XXX-XXX').toString(),
        'waveName':   (d['waveName']   ?? 'TSfootwear').toString(),
      };
    });
  }

  Future<void> saveAccountSettings({
    required String kpayNumber,
    required String kpayName,
    required String waveNumber,
    required String waveName,
  }) async {
    await FirebaseFirestore.instance.doc(_settingsPath).set({
      'kpayNumber': kpayNumber.trim(),
      'kpayName':   kpayName.trim(),
      'waveNumber': waveNumber.trim(),
      'waveName':   waveName.trim(),
    }, SetOptions(merge: true));
  }

  // ── Delivery fee settings ─────────────────────────────────────────────────

  static const _deliveryPath = 'settings/delivery';

  /// Streams the flat Mandalay city delivery fee set by admin.
  Stream<double> mandalayFeeStream() {
    return FirebaseFirestore.instance.doc(_deliveryPath).snapshots().map((snap) {
      final d = snap.data() ?? {};
      return (d['mandalayFee'] as num?)?.toDouble() ?? 3000.0;
    });
  }

  Future<void> saveMandalayFee(double fee) async {
    await FirebaseFirestore.instance.doc(_deliveryPath).set(
      {'mandalayFee': fee},
      SetOptions(merge: true),
    );
  }

  // ── Admin: delete ────────────────────────────────────────────────────────

  Future<void> deletePayment(String paymentId) async {
    await FirebaseFirestore.instance
        .collection('payments')
        .doc(paymentId)
        .delete();
  }

  // ── Stream all payments (admin) ───────────────────────────────────────────

  Stream<List<PaymentModel>> allPaymentsStream({String? status}) {
    Query query = FirebaseFirestore.instance
        .collection('payments')
        .orderBy('createdAt', descending: true);
    if (status != null) query = query.where('status', isEqualTo: status);
    return query
        .snapshots()
        .map((s) => s.docs
            .map((d) => PaymentModel.fromDoc(d as DocumentSnapshot))
            .toList())
        .handleError((e) {
          debugPrint('[PaymentService] admin stream error: $e');
          return <PaymentModel>[];
        });
  }
}
