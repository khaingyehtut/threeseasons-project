import 'dart:async';
import 'dart:math' show sin, cos, sqrt, atan2, pi;
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

  /// Streams the full delivery settings (supports per-mile and zone modes).
  Stream<Map<String, dynamic>> deliverySettingsStream() {
    return FirebaseFirestore.instance.doc(_deliveryPath).snapshots().map((snap) {
      final d = snap.data() ?? {};
      final rawZones = d['zones'];
      final zones = <Map<String, dynamic>>[];
      if (rawZones is List) {
        for (final z in rawZones) {
          if (z is Map) {
            zones.add({
              'minMiles': (z['minMiles'] as num?)?.toDouble() ?? 0.0,
              'maxMiles': (z['maxMiles'] as num?)?.toDouble(),
              'fee':      (z['fee']      as num?)?.toDouble() ?? 0.0,
            });
          }
        }
      }
      return {
        'mode':       (d['mode'] as String?) ?? 'per_mile',
        'baseFee':    (d['baseFee']    as num?)?.toDouble() ?? 3000.0,
        'feePerMile': (d['feePerMile'] as num?)?.toDouble() ?? 0.0,
        'storeLat':   (d['storeLat']   as num?)?.toDouble(),
        'storeLng':   (d['storeLng']   as num?)?.toDouble(),
        'zones':      zones,
      };
    });
  }

  Future<void> saveDeliverySettings({
    required String mode,
    required double baseFee,
    required double feePerMile,
    double? storeLat,
    double? storeLng,
    List<Map<String, dynamic>> zones = const [],
  }) async {
    await FirebaseFirestore.instance.doc(_deliveryPath).set({
      'mode':       mode,
      'baseFee':    baseFee,
      'feePerMile': feePerMile,
      if (storeLat != null) 'storeLat': storeLat,
      if (storeLng != null) 'storeLng': storeLng,
      'zones':      zones,
      'mandalayFee': baseFee,
    }, SetOptions(merge: true));
  }

  /// Computes delivery fee for either per-mile or zone mode.
  /// Falls back to [baseFee] (or first zone fee) when coordinates are missing.
  static double computeDeliveryFee({
    required String mode,
    required double baseFee,
    required double feePerMile,
    required List<Map<String, dynamic>> zones,
    required double? storeLat,
    required double? storeLng,
    required double? customerLat,
    required double? customerLng,
  }) {
    if (storeLat == null || storeLng == null ||
        customerLat == null || customerLng == null) {
      if (mode == 'zone' && zones.isNotEmpty) {
        return (zones.first['fee'] as double?) ?? baseFee;
      }
      return baseFee;
    }
    final miles = haversineMiles(storeLat, storeLng, customerLat, customerLng);
    if (mode == 'zone') {
      for (final zone in zones) {
        final minM = (zone['minMiles'] as double?) ?? 0.0;
        final maxM = zone['maxMiles'] as double?;
        final fee  = (zone['fee']      as double?) ?? baseFee;
        if (miles >= minM && (maxM == null || miles < maxM)) return fee;
      }
      return zones.isNotEmpty
          ? (zones.last['fee'] as double?) ?? baseFee
          : baseFee;
    }
    return baseFee + miles * feePerMile;
  }

  static double haversineMiles(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 3958.8; // Earth radius in miles
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_rad(lat1)) * cos(_rad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  static double _rad(double deg) => deg * pi / 180;

  /// Legacy flat-fee stream — kept so old code doesn't break during migration.
  Stream<double> mandalayFeeStream() {
    return deliverySettingsStream().map((s) => (s['baseFee'] as double?) ?? 3000.0);
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

    // Use a StreamController so we can emit an empty list on error
    // instead of letting the error terminate the stream silently.
    final ctrl = StreamController<List<PaymentModel>>();
    final sub = query.snapshots().listen(
      (snap) {
        try {
          ctrl.add(snap.docs
              .map((d) => PaymentModel.fromDoc(d as DocumentSnapshot))
              .toList());
        } catch (e) {
          debugPrint('[PaymentService] parse error: $e');
          ctrl.add(<PaymentModel>[]);
        }
      },
      onError: (Object e) {
        debugPrint('[PaymentService] admin stream error: $e');
        ctrl.add(<PaymentModel>[]); // emit empty list so UI shows empty state
        ctrl.close();
      },
      onDone: () => ctrl.close(),
    );
    ctrl.onCancel = () => sub.cancel();
    return ctrl.stream;
  }
}
