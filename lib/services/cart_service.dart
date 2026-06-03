import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cart_model.dart';
import '../models/product_model.dart';
import 'upload_service.dart';

class CartService {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Get Cart ─────────────────────────────────────────────────────────────────

  Future<CartModel> getCart(String userId) async {
    final docRef = _db.collection('carts').doc(userId);
    final doc = await docRef.get();

    if (!doc.exists) {
      // Create empty cart document on first access
      await docRef.set({'userId': userId, 'items': []});
      return CartModel(id: userId, userId: userId, items: []);
    }

    return await _buildCartModel(doc);
  }

  // ─── Add to Cart ──────────────────────────────────────────────────────────────

  Future<CartModel> addToCart(
    String userId,
    String productId,
    int quantity, {
    String? size,
    String? color,
  }) async {
    // Fetch product to get current price
    final productDoc = await _db.collection('products').doc(productId).get();
    if (!productDoc.exists) throw Exception('Product not found');

    final productData = Map<String, dynamic>.from(productDoc.data() as Map);
    final price = _parseDouble(productData['price']);
    final discount = _parseInt(productData['discount']);
    final effectivePrice =
        discount > 0 ? price - (price * discount / 100) : price;

    final docRef = _db.collection('carts').doc(userId);
    final doc = await docRef.get();

    List<Map<String, dynamic>> items = [];
    if (doc.exists) {
      final data = doc.data()!;
      items = List<Map<String, dynamic>>.from(
        (data['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i)),
      );
    }

    // Check if the same product+size+color combo already exists
    final existingIndex = items.indexWhere((item) =>
        item['productId'] == productId &&
        (item['size'] ?? '') == (size ?? '') &&
        (item['color'] ?? '') == (color ?? ''));

    if (existingIndex >= 0) {
      items[existingIndex]['quantity'] =
          (items[existingIndex]['quantity'] as int) + quantity;
    } else {
      items.add({
        'id': '${DateTime.now().millisecondsSinceEpoch}',
        'productId': productId,
        'quantity': quantity,
        'size': size ?? '',
        'color': color ?? '',
        'price': effectivePrice,
      });
    }

    await docRef.set({'userId': userId, 'items': items}, SetOptions(merge: true));

    final updatedDoc = await docRef.get();
    return await _buildCartModel(updatedDoc);
  }

  // ─── Update Cart Item Quantity ─────────────────────────────────────────────────

  Future<CartModel> updateCartItem(
    String userId,
    String itemId,
    int quantity,
  ) async {
    final docRef = _db.collection('carts').doc(userId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Cart not found');

    final data = doc.data()!;
    final items = List<Map<String, dynamic>>.from(
      (data['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i)),
    );

    final idx = items.indexWhere((item) => item['id'] == itemId);
    if (idx < 0) throw Exception('Cart item not found');

    if (quantity <= 0) {
      items.removeAt(idx);
    } else {
      items[idx]['quantity'] = quantity;
    }

    await docRef.update({'items': items});

    final updatedDoc = await docRef.get();
    return await _buildCartModel(updatedDoc);
  }

  // ─── Remove From Cart ─────────────────────────────────────────────────────────

  Future<CartModel> removeFromCart(String userId, String itemId) async {
    final docRef = _db.collection('carts').doc(userId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Cart not found');

    final data = doc.data()!;
    final items = List<Map<String, dynamic>>.from(
      (data['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i)),
    );

    items.removeWhere((item) => item['id'] == itemId);
    await docRef.update({'items': items});

    final updatedDoc = await docRef.get();
    return await _buildCartModel(updatedDoc);
  }

  // ─── Clear Cart ───────────────────────────────────────────────────────────────

  Future<void> clearCart(String userId) async {
    await _db.collection('carts').doc(userId).set(
      {'userId': userId, 'items': []},
      SetOptions(merge: true),
    );
  }

  // ─── Build CartModel (fetches full product docs) ──────────────────────────────

  Future<CartModel> _buildCartModel(DocumentSnapshot doc) async {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    final rawItems = List<Map<String, dynamic>>.from(
      (data['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i)),
    );

    if (rawItems.isEmpty) {
      return CartModel(id: doc.id, userId: doc.id, items: []);
    }

    // Batch-fetch all product docs
    final productIds =
        rawItems.map((i) => i['productId'].toString()).toSet().toList();

    final productDocs = await Future.wait(
      productIds.map((id) => _db.collection('products').doc(id).get()),
    );

    final productMap = <String, ProductModel>{};
    for (final pDoc in productDocs) {
      if (pDoc.exists) {
        productMap[pDoc.id] = _productFromDoc(pDoc);
      }
    }

    final cartItems = rawItems
        .where((item) => productMap.containsKey(item['productId']))
        .map((item) {
      final product = productMap[item['productId']]!;
      return CartItemModel(
        id: item['id']?.toString() ?? '',
        product: product,
        quantity: item['quantity'] is int ? item['quantity'] : 1,
        size: item['size']?.toString() ?? '',
        color: item['color']?.toString() ?? '',
        price: _parseDouble(item['price']),
      );
    }).toList();

    return CartModel(
      id: doc.id,
      userId: data['userId']?.toString() ?? doc.id,
      items: cartItems,
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────────

  double _parseDouble(dynamic v) {
    if (v == null) return 0.0;
    if (v is double) return v;
    if (v is int) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0.0;
    return 0.0;
  }

  int _parseInt(dynamic v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is double) return v.toInt();
    if (v is String) return int.tryParse(v) ?? 0;
    return 0;
  }

  ProductModel _productFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    return ProductModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: _parseDouble(data['price']),
      comparePrice: _parseDouble(data['comparePrice']),
      images: _parseStringList(data['images']).map(UploadService.fixUrl).toList(),
      thumbnail: UploadService.fixUrl(data['thumbnail'] ?? ''),
      stock: _parseInt(data['stock']),
      brand: data['brand'] ?? '',
      rating: _parseDouble(data['rating']),
      numReviews: _parseInt(data['numReviews']),
      isFeatured: data['isFeatured'] ?? false,
      discount: _parseInt(data['discount']),
      sizes: _parseStringList(data['sizes']),
      colors: _parseStringList(data['colors']),
      sold: _parseInt(data['sold']),
    );
  }

  List<String> _parseStringList(dynamic v) {
    if (v == null) return [];
    if (v is List) return v.map((e) => e.toString()).toList();
    return [];
  }
}
