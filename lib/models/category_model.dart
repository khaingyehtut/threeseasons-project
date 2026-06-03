class CategoryModel {
  final String id;
  final String name;
  final String slug;
  final String description;
  final String image;
  final String icon;
  final String color;
  final int productCount;
  final bool isActive;

  const CategoryModel({
    required this.id,
    required this.name,
    required this.slug,
    this.description = '',
    this.image = '',
    this.icon = '🛍️',
    this.color = '#6C63FF',
    this.productCount = 0,
    this.isActive = true,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) => CategoryModel(
        id: json['id'] ?? json['_id'] ?? '',
        name: json['name'] ?? '',
        slug: json['slug'] ?? '',
        description: json['description'] ?? '',
        image: json['image'] ?? '',
        icon: json['icon'] ?? '🛍️',
        color: json['color'] ?? '#6C63FF',
        productCount: json['productCount'] ?? 0,
        isActive: json['isActive'] ?? true,
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'slug': slug,
        'description': description,
        'image': image,
        'icon': icon,
        'color': color,
        'productCount': productCount,
      };

  CategoryModel copyWith({
    String? id,
    String? name,
    String? slug,
    String? description,
    String? image,
    String? icon,
    String? color,
    int? productCount,
  }) {
    return CategoryModel(
      id: id ?? this.id,
      name: name ?? this.name,
      slug: slug ?? this.slug,
      description: description ?? this.description,
      image: image ?? this.image,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      productCount: productCount ?? this.productCount,
    );
  }
}
