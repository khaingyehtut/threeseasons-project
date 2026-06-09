import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import 'upload_service.dart';

class ProductService {
  static final ProductService _instance = ProductService._internal();
  factory ProductService() => _instance;
  ProductService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Get Products (paginated, filtered, sorted) ───────────────────────────────

  Future<Map<String, dynamic>> getProducts({
    String? categoryId,
    String? search,
    String sort = 'newest',
    double? minPrice,
    double? maxPrice,
    String? gender,
    DocumentSnapshot? lastDoc,
    int limit = 12,
  }) async {
    Query query = _db.collection('products');

    final bool hasCategory = categoryId != null && categoryId.isNotEmpty;
    final bool hasSearch   = search != null && search.isNotEmpty;
    final bool hasGender   = gender != null && gender.isNotEmpty;

    if (hasCategory || hasSearch || hasGender) {
      // Category/gender filter or full-text search: fetch a large batch client-side.
      // Combining orderBy with where clauses needs composite indexes — keep it simple.
      if (hasCategory) {
        query = query.where('categoryId', isEqualTo: categoryId);
      }
      query = query.limit(500);
    } else {
      // No filter — server-side ordering + cursor pagination work fine.
      if (minPrice != null) {
        query = query.where('price', isGreaterThanOrEqualTo: minPrice);
      }
      if (maxPrice != null) {
        query = query.where('price', isLessThanOrEqualTo: maxPrice);
      }

      switch (sort) {
        case 'price_asc':
          query = query.orderBy('price', descending: false);
          break;
        case 'price_desc':
          query = query.orderBy('price', descending: true);
          break;
        case 'rating':
          query = query.orderBy('rating', descending: true);
          break;
        case 'popular':
          query = query.orderBy('sold', descending: true);
          break;
        case 'newest':
        default:
          query = query.orderBy('createdAt', descending: true);
          break;
      }

      if (lastDoc != null) {
        query = query.startAfterDocument(lastDoc);
      }

      query = query.limit(limit);
    }

    final snapshot = await query.get();
    List<ProductModel> products = snapshot.docs
        .map((doc) => _productFromDoc(doc))
        .where((p) => p.isActive)
        .toList();

    // Client-side search filter (Firestore has no native full-text search)
    if (search != null && search.isNotEmpty) {
      final lower = search.toLowerCase();
      products = products
          .where((p) =>
              p.name.toLowerCase().contains(lower) ||
              p.description.toLowerCase().contains(lower) ||
              p.brand.toLowerCase().contains(lower))
          .toList();
    }

    // Client-side gender filter
    if (hasGender) {
      products = products.where((p) => p.gender == gender).toList();
    }

    // When a category/gender is active, sort client-side to avoid composite indexes.
    if (hasCategory || hasGender) {
      switch (sort) {
        case 'price_asc':
          products.sort((a, b) => a.price.compareTo(b.price));
          break;
        case 'price_desc':
          products.sort((a, b) => b.price.compareTo(a.price));
          break;
        case 'rating':
          products.sort((a, b) => b.rating.compareTo(a.rating));
          break;
        case 'popular':
          products.sort((a, b) => b.sold.compareTo(a.sold));
          break;
        case 'newest':
        default:
          // Firestore docs without a createdAt sort by doc ID descending as fallback
          products = products.reversed.toList();
          break;
      }
    }

    // For category/gender-filtered results, pagination is client-side — return null lastDoc.
    final DocumentSnapshot? newLastDoc = (hasCategory || hasGender)
        ? null
        : (snapshot.docs.isNotEmpty ? snapshot.docs.last : null);

    return {
      'products': products,
      'lastDoc': newLastDoc,
    };
  }

  // ─── Featured Products ────────────────────────────────────────────────────────

  Future<List<ProductModel>> getFeaturedProducts() async {
    final snapshot = await _db
        .collection('products')
        .where('isFeatured', isEqualTo: true)
        .limit(20)
        .get();

    return snapshot.docs
        .map((doc) => _productFromDoc(doc))
        .where((p) => p.isActive)
        .take(10)
        .toList();
  }

  // ─── Single Product ───────────────────────────────────────────────────────────

  Future<ProductModel> getProduct(String id) async {
    final doc = await _db.collection('products').doc(id).get();
    if (!doc.exists) throw Exception('Product not found');
    return _productFromDoc(doc);
  }

  // ─── Related Products ─────────────────────────────────────────────────────────

  Future<List<ProductModel>> getRelatedProducts(
    String productId,
    String categoryId,
  ) async {
    final snapshot = await _db
        .collection('products')
        .where('categoryId', isEqualTo: categoryId)
        .limit(20)
        .get();

    return snapshot.docs
        .map((doc) => _productFromDoc(doc))
        .where((p) => p.isActive && p.id != productId)
        .take(6)
        .toList();
  }

  // ─── Reviews Stream ───────────────────────────────────────────────────────────

  Stream<List<Map<String, dynamic>>> reviewsStream(String productId) {
    return _db.collection('products').doc(productId).snapshots().map((snap) {
      if (!snap.exists) return [];
      final data = snap.data()!;
      final raw = data['reviews'] as List? ?? [];
      return raw
          .map((r) => Map<String, dynamic>.from(r as Map))
          .toList()
          .reversed
          .toList();
    });
  }

  // ─── Add Review ───────────────────────────────────────────────────────────────

  Future<void> addReview(
    String productId,
    double rating,
    String comment,
    String userId,
    String userName,
  ) async {
    final docRef = _db.collection('products').doc(productId);

    final review = {
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    };

    await _db.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception('Product not found');

      final data = snapshot.data()!;
      final reviews = List<Map<String, dynamic>>.from(
        (data['reviews'] as List? ?? []).map((r) => Map<String, dynamic>.from(r)),
      );
      reviews.add(review);

      final numReviews = reviews.length;
      final avgRating = reviews.fold<double>(
            0,
            (acc, r) {
              final r2 = r['rating'];
              if (r2 is num) return acc + r2.toDouble();
              return acc;
            },
          ) /
          numReviews;

      transaction.update(docRef, {
        'reviews': reviews,
        'numReviews': numReviews,
        'rating': double.parse(avgRating.toStringAsFixed(1)),
      });
    });
  }

  // ─── Admin CRUD ───────────────────────────────────────────────────────────────

  Future<ProductModel> createProduct(Map<String, dynamic> data) async {
    data['createdAt'] = FieldValue.serverTimestamp();
    data['isActive'] = data['isActive'] ?? true;
    data['sold'] = data['sold'] ?? 0;
    data['rating'] = data['rating'] ?? 0.0;
    data['numReviews'] = data['numReviews'] ?? 0;
    data['reviews'] = data['reviews'] ?? [];

    final docRef = await _db.collection('products').add(data);
    final doc = await docRef.get();
    return _productFromDoc(doc);
  }

  Future<ProductModel> updateProduct(
    String id,
    Map<String, dynamic> data,
  ) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('products').doc(id).update(data);
    final doc = await _db.collection('products').doc(id).get();
    return _productFromDoc(doc);
  }

  Future<void> deleteProduct(String id) async {
    await _db.collection('products').doc(id).delete();
  }

  // ─── Helper ───────────────────────────────────────────────────────────────────

  ProductModel _productFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);

    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    int parseInt(dynamic v) {
      if (v == null) return 0;
      if (v is int) return v;
      if (v is double) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    List<String> parseStringList(dynamic v) {
      if (v == null) return [];
      if (v is List) return v.map((e) => e.toString()).toList();
      return [];
    }

    // Category: stored either as a map or a categoryId string
    CategoryModel? category;
    final rawCategory = data['category'];
    final categoryId = data['categoryId']?.toString() ?? '';
    if (rawCategory is Map<String, dynamic>) {
      category = CategoryModel(
        id: rawCategory['id'] ?? rawCategory['_id'] ?? categoryId,
        name: rawCategory['name'] ?? '',
        slug: rawCategory['slug'] ?? '',
        icon: rawCategory['icon'] ?? '🛍️',
        color: rawCategory['color'] ?? '#6C63FF',
        image: rawCategory['image'] ?? '',
        description: rawCategory['description'] ?? '',
      );
    } else if (categoryId.isNotEmpty) {
      category = CategoryModel(id: categoryId, name: '', slug: '');
    }

    return ProductModel(
      id: doc.id,
      name: data['name'] ?? '',
      description: data['description'] ?? '',
      price: parseDouble(data['price']),
      comparePrice: parseDouble(data['comparePrice']),
      images: parseStringList(data['images']).map(UploadService.fixUrl).toList(),
      thumbnail: UploadService.fixUrl(data['thumbnail'] ?? ''),
      category: category,
      tags: parseStringList(data['tags']),
      stock: parseInt(data['stock']),
      brand: data['brand'] ?? '',
      rating: parseDouble(data['rating']),
      numReviews: parseInt(data['numReviews']),
      isFeatured: data['isFeatured'] ?? false,
      discount: parseInt(data['discount']),
      sizes: parseStringList(data['sizes']),
      colors: parseStringList(data['colors']),
      sold: parseInt(data['sold']),
      isActive: data['isActive'] ?? true,
      gender: data['gender'] ?? '',
    );
  }
}
