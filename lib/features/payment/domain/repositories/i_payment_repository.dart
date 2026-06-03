import 'package:flutter/foundation.dart';
import 'package:three_seasons_project/features/payment/data/models/payment_model.dart';

abstract class IPaymentRepository {
  Future<PaymentModel> submitPayment({
    required Uint8List screenshotBytes,
    required String screenshotFilename,
    required double amount,
    required String paymentMethod,
    required String firebaseIdToken,
    String? orderId,
    String note,
  });
  Future<void> approvePayment(String paymentId, String firebaseIdToken, {String adminNote});
  Future<void> rejectPayment(String paymentId, String firebaseIdToken, {String adminNote});
  Stream<List<PaymentModel>> userPaymentsStream(String userId);
  Stream<List<PaymentModel>> allPaymentsStream({String? status});
  Stream<Map<String, String>> accountSettingsStream();
  Future<void> saveAccountSettings({
    required String kpayNumber,
    required String kpayName,
    required String waveNumber,
    required String waveName,
  });
}
