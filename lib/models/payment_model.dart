import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/upload_service.dart';

class PaymentModel {
  final String id;
  final String userId;
  final String? orderId;
  final double amount;
  final String paymentMethod;
  final String screenshotUrl;
  final String status;
  final String adminNote;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const PaymentModel({
    required this.id,
    required this.userId,
    this.orderId,
    required this.amount,
    required this.paymentMethod,
    required this.screenshotUrl,
    required this.status,
    this.adminNote = '',
    this.note = '',
    this.createdAt,
    this.updatedAt,
  });

  factory PaymentModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return PaymentModel(
      id:            doc.id,
      userId:        d['userId'] ?? '',
      orderId:       d['orderId'] as String?,
      amount:        (d['amount'] ?? 0).toDouble(),
      paymentMethod: d['paymentMethod'] ?? '',
      screenshotUrl: UploadService.fixUrl(d['screenshotUrl'] ?? ''),
      status:        d['status'] ?? 'pending',
      adminNote:     d['adminNote'] ?? '',
      note:          d['note'] ?? '',
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate(),
      updatedAt:     (d['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  bool get isPending  => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
