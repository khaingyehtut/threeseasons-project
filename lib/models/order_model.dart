import 'package:flutter/material.dart';

class OrderItemModel {
  final String productId;
  final String name;
  final String image;
  final double price;
  final int quantity;
  final String size;
  final String color;

  const OrderItemModel({
    required this.productId,
    required this.name,
    this.image = '',
    required this.price,
    required this.quantity,
    this.size = '',
    this.color = '',
  });

  double get subtotal => price * quantity;

  factory OrderItemModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic value) {
      if (value == null) return 0;
      if (value is int) return value;
      if (value is double) return value.toInt();
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

    return OrderItemModel(
      productId: json['productId']?.toString() ??
          (json['product'] is Map
              ? (json['product']['_id'] ?? json['product']['id'] ?? '')
              : (json['product']?.toString() ?? '')),
      name: json['name'] ?? '',
      image: json['image'] ?? '',
      price: parseDouble(json['price']),
      quantity: parseInt(json['quantity']),
      size: json['size'] ?? '',
      color: json['color'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'product': productId,
        'name': name,
        'image': image,
        'price': price,
        'quantity': quantity,
        'size': size,
        'color': color,
      };
}

class OrderModel {
  final String id;
  final String orderNumber;
  final String userId;
  final List<OrderItemModel> items;
  final Map<String, dynamic> shippingAddress;
  final String paymentMethod;
  final String paymentStatus;
  final double itemsPrice;
  final double shippingPrice;
  final double taxPrice;
  final double totalPrice;
  final String status;
  final bool isPaid;
  final bool isDelivered;
  final String trackingNumber;
  final DateTime? createdAt;

  const OrderModel({
    required this.id,
    this.orderNumber = '',
    required this.userId,
    required this.items,
    required this.shippingAddress,
    this.paymentMethod = '',
    this.paymentStatus = 'pending',
    this.itemsPrice = 0.0,
    this.shippingPrice = 0.0,
    this.taxPrice = 0.0,
    required this.totalPrice,
    this.status = 'pending',
    this.isPaid = false,
    this.isDelivered = false,
    this.trackingNumber = '',
    this.createdAt,
  });

  Color get statusColor {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'processing':
        return const Color(0xFF3B82F6);
      case 'shipped':
        return const Color(0xFF8B5CF6);
      case 'delivered':
        return const Color(0xFF10B981);
      case 'cancelled':
        return const Color(0xFFEF4444);
      case 'refunded':
        return const Color(0xFF6B7280);
      default:
        return const Color(0xFF6B7280);
    }
  }

  String get statusLabel {
    switch (status.toLowerCase()) {
      case 'pending':
        return 'Pending';
      case 'processing':
        return 'Processing';
      case 'shipped':
        return 'Shipped';
      case 'delivered':
        return 'Delivered';
      case 'cancelled':
        return 'Cancelled';
      case 'refunded':
        return 'Refunded';
      default:
        return status;
    }
  }

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final rawItems = json['orderItems'] ?? json['items'];
    List<OrderItemModel> parsedItems = [];
    if (rawItems is List) {
      parsedItems = rawItems
          .map((item) =>
              OrderItemModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    Map<String, dynamic> shippingAddr = {};
    final rawAddr = json['shippingAddress'];
    if (rawAddr is Map) shippingAddr = Map<String, dynamic>.from(rawAddr);

    return OrderModel(
      id: json['id'] ?? json['_id'] ?? '',
      orderNumber: json['orderNumber'] ?? '',
      userId: json['userId']?.toString() ??
          (json['user'] is Map
              ? (json['user']['_id'] ?? json['user']['id'] ?? '')
              : (json['user']?.toString() ?? '')),
      items: parsedItems,
      shippingAddress: shippingAddr,
      paymentMethod: json['paymentMethod'] ?? '',
      paymentStatus: json['paymentStatus'] ?? 'pending',
      itemsPrice: parseDouble(json['itemsPrice']),
      shippingPrice: parseDouble(json['shippingPrice']),
      taxPrice: parseDouble(json['taxPrice']),
      totalPrice: parseDouble(json['totalPrice']),
      status: json['status'] ?? 'pending',
      isPaid: json['isPaid'] ?? false,
      isDelivered: json['isDelivered'] ?? false,
      trackingNumber: json['trackingNumber'] ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'orderNumber': orderNumber,
        'user': userId,
        'orderItems': items.map((item) => item.toJson()).toList(),
        'shippingAddress': shippingAddress,
        'paymentMethod': paymentMethod,
        'paymentStatus': paymentStatus,
        'itemsPrice': itemsPrice,
        'shippingPrice': shippingPrice,
        'taxPrice': taxPrice,
        'totalPrice': totalPrice,
        'status': status,
        'isPaid': isPaid,
        'isDelivered': isDelivered,
        'trackingNumber': trackingNumber,
        'createdAt': createdAt?.toIso8601String(),
      };

  OrderModel copyWith({
    String? id,
    String? orderNumber,
    String? userId,
    List<OrderItemModel>? items,
    Map<String, dynamic>? shippingAddress,
    String? paymentMethod,
    String? paymentStatus,
    double? itemsPrice,
    double? shippingPrice,
    double? taxPrice,
    double? totalPrice,
    String? status,
    bool? isPaid,
    bool? isDelivered,
    String? trackingNumber,
    DateTime? createdAt,
  }) {
    return OrderModel(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      userId: userId ?? this.userId,
      items: items ?? this.items,
      shippingAddress: shippingAddress ?? this.shippingAddress,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      itemsPrice: itemsPrice ?? this.itemsPrice,
      shippingPrice: shippingPrice ?? this.shippingPrice,
      taxPrice: taxPrice ?? this.taxPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      status: status ?? this.status,
      isPaid: isPaid ?? this.isPaid,
      isDelivered: isDelivered ?? this.isDelivered,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
