import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/category_model.dart';
import 'upload_service.dart';

class CategoryService {
  static final CategoryService _instance = CategoryService._internal();
  factory CategoryService() => _instance;
  CategoryService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Get All Categories ───────────────────────────────────────────────────────

  Future<List<CategoryModel>> getCategories() async {
    final snapshot = await _db.collection('categories').get();
    final list = snapshot.docs
        .map((doc) => _categoryFromDoc(doc))
        .where((c) => c.isActive)
        .toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  // ─── Admin CRUD ───────────────────────────────────────────────────────────────

  Future<CategoryModel> createCategory(Map<String, dynamic> data) async {
    data['isActive'] = data['isActive'] ?? true;
    data['productCount'] = data['productCount'] ?? 0;
    data['createdAt'] = FieldValue.serverTimestamp();

    final docRef = await _db.collection('categories').add(data);
    final doc = await docRef.get();
    return _categoryFromDoc(doc);
  }

  Future<CategoryModel> updateCategory(
    String id,
    Map<String, dynamic> data,
  ) async {
    data['updatedAt'] = FieldValue.serverTimestamp();
    await _db.collection('categories').doc(id).update(data);
    final doc = await _db.collection('categories').doc(id).get();
    return _categoryFromDoc(doc);
  }

  Future<void> deleteCategory(String id) async {
    await _db.collection('categories').doc(id).delete();
  }

  // ─── Helper ───────────────────────────────────────────────────────────────────

  CategoryModel _categoryFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);
    return CategoryModel(
      id: doc.id,
      name: data['name'] ?? '',
      slug: data['slug'] ?? '',
      description: data['description'] ?? '',
      image: UploadService.fixUrl(data['image'] ?? ''),
      icon: data['icon'] ?? '🛍️',
      color: data['color'] ?? '#6C63FF',
      productCount: data['productCount'] is int ? data['productCount'] : 0,
      isActive: data['isActive'] ?? true,
    );
  }
}
