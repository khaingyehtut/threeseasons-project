import 'package:cloud_firestore/cloud_firestore.dart';

class BannerModel {
  final String id;
  final String imageUrl;
  final String title;
  final String subtitle;
  final bool isActive;
  final int order;
  final DateTime? createdAt;

  const BannerModel({
    required this.id,
    required this.imageUrl,
    this.title = '',
    this.subtitle = '',
    this.isActive = true,
    this.order = 0,
    this.createdAt,
  });

  factory BannerModel.fromDoc(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>? ?? {};
    return BannerModel(
      id: doc.id,
      imageUrl: d['imageUrl'] ?? '',
      title: d['title'] ?? '',
      subtitle: d['subtitle'] ?? '',
      isActive: d['isActive'] ?? true,
      order: d['order'] is int ? d['order'] : 0,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'imageUrl': imageUrl,
        'title': title,
        'subtitle': subtitle,
        'isActive': isActive,
        'order': order,
      };
}
