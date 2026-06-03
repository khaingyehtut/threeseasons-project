class UserModel {
  final String id;
  final String name;
  final String email;
  final String role;
  final String avatar;
  final String phone;
  final Map<String, dynamic>? address;
  final bool isOnline;
  final DateTime? lastSeen;
  final List<String> wishlist;

  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.avatar = '',
    this.phone = '',
    this.address,
    this.isOnline = false,
    this.lastSeen,
    this.wishlist = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] ?? json['_id'] ?? '',
        name: json['name'] ?? '',
        email: json['email'] ?? '',
        role: json['role'] ?? 'user',
        avatar: json['avatar'] ?? '',
        phone: json['phone'] ?? '',
        address: json['address'] != null
            ? Map<String, dynamic>.from(json['address'])
            : null,
        isOnline: json['isOnline'] ?? false,
        lastSeen: json['lastSeen'] != null
            ? (json['lastSeen'] is String
                ? DateTime.tryParse(json['lastSeen'])
                : null)
            : null,
        wishlist: List<String>.from(json['wishlist'] ?? []),
      );

  Map<String, dynamic> toJson() => {
        '_id': id,
        'name': name,
        'email': email,
        'role': role,
        'avatar': avatar,
        'phone': phone,
      };

  bool get isAdmin => role == 'admin';

  UserModel copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? avatar,
    String? phone,
    Map<String, dynamic>? address,
    bool? isOnline,
    DateTime? lastSeen,
    List<String>? wishlist,
  }) {
    return UserModel(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      avatar: avatar ?? this.avatar,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      wishlist: wishlist ?? this.wishlist,
    );
  }
}
