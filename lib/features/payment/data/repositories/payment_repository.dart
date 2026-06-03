import 'package:flutter/foundation.dart';
import 'package:three_seasons_project/features/payment/data/models/payment_model.dart';
import 'package:three_seasons_project/features/payment/domain/repositories/i_payment_repository.dart';
import 'package:three_seasons_project/services/payment_service.dart';

class PaymentRepository implements IPaymentRepository {
  final PaymentService _service;

  PaymentRepository({PaymentService? service})
      : _service = service ?? PaymentService();

  @override
  Future<PaymentModel> submitPayment({
    required Uint8List screenshotBytes,
    required String screenshotFilename,
    required double amount,
    required String paymentMethod,
    required String firebaseIdToken,
    String? orderId,
    String note = '',
  }) =>
      _service.submitPayment(
        screenshotBytes: screenshotBytes,
        screenshotFilename: screenshotFilename,
        amount: amount,
        paymentMethod: paymentMethod,
        firebaseIdToken: firebaseIdToken,
        orderId: orderId,
        note: note,
      );

  @override
  Future<void> approvePayment(
    String paymentId,
    String firebaseIdToken, {
    String adminNote = '',
  }) =>
      _service.approvePayment(paymentId, firebaseIdToken, adminNote: adminNote);

  @override
  Future<void> rejectPayment(
    String paymentId,
    String firebaseIdToken, {
    String adminNote = '',
  }) =>
      _service.rejectPayment(paymentId, firebaseIdToken, adminNote: adminNote);

  @override
  Stream<List<PaymentModel>> userPaymentsStream(String userId) =>
      _service.userPaymentsStream(userId);

  @override
  Stream<List<PaymentModel>> allPaymentsStream({String? status}) =>
      _service.allPaymentsStream(status: status);

  @override
  Stream<Map<String, String>> accountSettingsStream() =>
      _service.accountSettingsStream();

  @override
  Future<void> saveAccountSettings({
    required String kpayNumber,
    required String kpayName,
    required String waveNumber,
    required String waveName,
  }) =>
      _service.saveAccountSettings(
        kpayNumber: kpayNumber,
        kpayName: kpayName,
        waveNumber: waveNumber,
        waveName: waveName,
      );
}
