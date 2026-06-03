import 'package:cloud_firestore/cloud_firestore.dart';

class AnnouncementModel {
  final String id;
  final String title;
  final String body;
  final String imageUrl;
  final String type; // 'new_product' | 'app_update' | 'promotion'
  final String productId;
  final bool isActive;
  final DateTime createdAt;

  const AnnouncementModel({
    required this.id,
    required this.title,
    required this.body,
    this.imageUrl = '',
    this.type = 'promotion',
    this.productId = '',
    this.isActive = true,
    required this.createdAt,
  });

  factory AnnouncementModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v is Timestamp) return v.toDate();
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return AnnouncementModel(
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      imageUrl: json['imageUrl']?.toString() ?? '',
      type: json['type']?.toString() ?? 'promotion',
      productId: json['productId']?.toString() ?? '',
      isActive: json['isActive'] as bool? ?? true,
      createdAt: parseDate(json['createdAt']),
    );
  }

  Map<String, dynamic> toJson() => {
        'title': title,
        'body': body,
        'imageUrl': imageUrl,
        'type': type,
        'productId': productId,
        'isActive': isActive,
      };

  AnnouncementModel copyWith({bool? isActive}) => AnnouncementModel(
        id: id,
        title: title,
        body: body,
        imageUrl: imageUrl,
        type: type,
        productId: productId,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}
