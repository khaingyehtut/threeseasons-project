import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:three_seasons_project/features/product/data/models/product_model.dart';
import 'package:three_seasons_project/features/product/data/models/category_model.dart';

abstract class IProductRepository {
  Future<Map<String, dynamic>> getProducts({
    String? categoryId,
    String? search,
    String sort,
    double? minPrice,
    double? maxPrice,
    DocumentSnapshot? lastDoc,
    int limit,
  });
  Future<List<ProductModel>> getFeaturedProducts();
  Future<ProductModel> getProduct(String id);
  Future<List<ProductModel>> getRelatedProducts(String productId, String categoryId);
  Future<void> addReview(String productId, double rating, String comment, String userId, String userName);
  Future<ProductModel> createProduct(Map<String, dynamic> data);
  Future<ProductModel> updateProduct(String id, Map<String, dynamic> data);
  Future<void> deleteProduct(String id);

  // Category operations
  Future<List<CategoryModel>> getCategories();
  Future<CategoryModel> createCategory(Map<String, dynamic> data);
  Future<CategoryModel> updateCategory(String id, Map<String, dynamic> data);
  Future<void> deleteCategory(String id);
}
