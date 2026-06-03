import 'product_model.dart';

class CartItemModel {
  final String id;
  final ProductModel product;
  final int quantity;
  final String size;
  final String color;
  final double price;

  const CartItemModel({
    required this.id,
    required this.product,
    required this.quantity,
    this.size = '',
    this.color = '',
    required this.price,
  });

  double get subtotal => price * quantity;

  factory CartItemModel.fromJson(Map<String, dynamic> json) {
    double parseDouble(dynamic value) {
      if (value == null) return 0.0;
      if (value is double) return value;
      if (value is int) return value.toDouble();
      if (value is String) return double.tryParse(value) ?? 0.0;
      return 0.0;
    }

    final rawProduct = json['product'];
    ProductModel parsedProduct;
    if (rawProduct is Map<String, dynamic>) {
      parsedProduct = ProductModel.fromJson(rawProduct);
    } else {
      parsedProduct = ProductModel(
        id: rawProduct?.toString() ?? '',
        name: '',
        price: 0.0,
      );
    }

    return CartItemModel(
      id: json['id'] ?? json['_id'] ?? '',
      product: parsedProduct,
      quantity: json['quantity'] ?? 1,
      size: json['size'] ?? '',
      color: json['color'] ?? '',
      price: parseDouble(json['price']),
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'product': product.toJson(),
        'quantity': quantity,
        'size': size,
        'color': color,
        'price': price,
      };

  CartItemModel copyWith({
    String? id,
    ProductModel? product,
    int? quantity,
    String? size,
    String? color,
    double? price,
  }) {
    return CartItemModel(
      id: id ?? this.id,
      product: product ?? this.product,
      quantity: quantity ?? this.quantity,
      size: size ?? this.size,
      color: color ?? this.color,
      price: price ?? this.price,
    );
  }
}

class CartModel {
  final String id;
  final String userId;
  final List<CartItemModel> items;

  const CartModel({
    required this.id,
    required this.userId,
    required this.items,
  });

  double get totalPrice => items.fold(0.0, (sum, item) => sum + item.subtotal);
  int get totalItems => items.fold(0, (sum, item) => sum + item.quantity);
  bool get isEmpty => items.isEmpty;

  factory CartModel.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    List<CartItemModel> parsedItems = [];
    if (rawItems is List) {
      parsedItems = rawItems
          .map((item) =>
              CartItemModel.fromJson(Map<String, dynamic>.from(item)))
          .toList();
    }

    return CartModel(
      id: json['id'] ?? json['_id'] ?? '',
      userId: json['userId']?.toString() ??
          (json['user'] is Map
              ? (json['user']['_id'] ?? json['user']['id'] ?? '')
              : (json['user']?.toString() ?? '')),
      items: parsedItems,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'user': userId,
        'items': items.map((item) => item.toJson()).toList(),
      };

  CartModel copyWith({
    String? id,
    String? userId,
    List<CartItemModel>? items,
  }) {
    return CartModel(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      items: items ?? this.items,
    );
  }
}
