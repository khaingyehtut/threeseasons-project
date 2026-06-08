import 'category_model.dart';
import '../core/constants.dart';

class ProductModel {
  final String id;
  final String name;
  final String description;
  final double price;
  final double comparePrice;
  final List<String> images;
  final String thumbnail;
  final CategoryModel? category;
  final List<String> tags;
  final int stock;
  final String brand;
  final double rating;
  final int numReviews;
  final bool isFeatured;
  final int discount;
  final List<String> sizes;
  final List<String> colors;
  final int sold;
  final bool isActive;
  final String barcode;
  final double? originalPrice; // cost / purchase price (optional)

  const ProductModel({
    required this.id,
    required this.name,
    this.description = '',
    required this.price,
    this.comparePrice = 0.0,
    this.images = const [],
    this.thumbnail = '',
    this.category,
    this.tags = const [],
    this.stock = 0,
    this.brand = '',
    this.rating = 0.0,
    this.numReviews = 0,
    this.isFeatured = false,
    this.discount = 0,
    this.sizes = const [],
    this.colors = const [],
    this.sold = 0,
    this.isActive = true,
    this.barcode = '',
    this.originalPrice,
  });

  double get discountedPrice {
    if (discount <= 0) return price;
    return price - (price * discount / 100);
  }

  bool get hasDiscount => discount > 0;
  bool get isInStock => stock > 0;
  bool get hasCostPrice => originalPrice != null && originalPrice! > 0;
  double? get profitPerUnit =>
      hasCostPrice ? (discountedPrice - originalPrice!) : null;
  double? get profitMarginPercent =>
      (hasCostPrice && discountedPrice > 0)
          ? ((discountedPrice - originalPrice!) / discountedPrice * 100)
          : null;

  String get firstImage {
    final raw = thumbnail.isNotEmpty ? thumbnail : (images.isNotEmpty ? images.first : '');
    return AppConstants.fixImageUrl(raw);
  }

  factory ProductModel.fromJson(Map<String, dynamic> json) {
    CategoryModel? parsedCategory;
    final rawCategory = json['category'];
    if (rawCategory is Map<String, dynamic>) {
      parsedCategory = CategoryModel.fromJson(rawCategory);
    } else if (rawCategory is String && rawCategory.isNotEmpty) {
      parsedCategory = CategoryModel(id: rawCategory, name: '', slug: '');
    }

    List<String> parseStringList(dynamic value) {
      if (value == null) return [];
      if (value is List) return value.map((e) => e.toString()).toList();
      return [];
    }

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

    return ProductModel(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      price: parseDouble(json['price']),
      comparePrice: parseDouble(json['comparePrice']),
      images: parseStringList(json['images']),
      thumbnail: json['thumbnail'] ?? '',
      category: parsedCategory,
      tags: parseStringList(json['tags']),
      stock: parseInt(json['stock']),
      brand: json['brand'] ?? '',
      rating: parseDouble(json['rating']),
      numReviews: parseInt(json['numReviews']),
      isFeatured: json['isFeatured'] ?? false,
      discount: parseInt(json['discount']),
      sizes: parseStringList(json['sizes']),
      colors: parseStringList(json['colors']),
      sold: parseInt(json['sold']),
      isActive: json['isActive'] ?? true,
      barcode: json['barcode'] ?? '',
      originalPrice: json['originalPrice'] != null
          ? parseDouble(json['originalPrice'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'description': description,
        'price': price,
        'comparePrice': comparePrice,
        'images': images,
        'thumbnail': thumbnail,
        'category': category?.toJson(),
        'tags': tags,
        'stock': stock,
        'brand': brand,
        'rating': rating,
        'numReviews': numReviews,
        'isFeatured': isFeatured,
        'discount': discount,
        'sizes': sizes,
        'colors': colors,
        'sold': sold,
        'isActive': isActive,
        'barcode': barcode,
        if (originalPrice != null) 'originalPrice': originalPrice,
      };

  ProductModel copyWith({
    String? id,
    String? name,
    String? description,
    double? price,
    double? comparePrice,
    List<String>? images,
    String? thumbnail,
    CategoryModel? category,
    List<String>? tags,
    int? stock,
    String? brand,
    double? rating,
    int? numReviews,
    bool? isFeatured,
    int? discount,
    List<String>? sizes,
    List<String>? colors,
    int? sold,
    bool? isActive,
    String? barcode,
    double? originalPrice,
  }) {
    return ProductModel(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      price: price ?? this.price,
      comparePrice: comparePrice ?? this.comparePrice,
      images: images ?? this.images,
      thumbnail: thumbnail ?? this.thumbnail,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      stock: stock ?? this.stock,
      brand: brand ?? this.brand,
      rating: rating ?? this.rating,
      numReviews: numReviews ?? this.numReviews,
      isFeatured: isFeatured ?? this.isFeatured,
      discount: discount ?? this.discount,
      sizes: sizes ?? this.sizes,
      colors: colors ?? this.colors,
      sold: sold ?? this.sold,
      isActive: isActive ?? this.isActive,
      barcode: barcode ?? this.barcode,
      originalPrice: originalPrice ?? this.originalPrice,
    );
  }
}
