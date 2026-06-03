import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:three_seasons_project/features/product/data/models/category_model.dart';
import 'package:three_seasons_project/features/product/data/models/product_model.dart';
import 'package:three_seasons_project/features/product/domain/repositories/i_product_repository.dart';
import 'package:three_seasons_project/services/category_service.dart';
import 'package:three_seasons_project/services/product_service.dart';

class ProductRepository implements IProductRepository {
  final ProductService _productService;
  final CategoryService _categoryService;

  ProductRepository({
    ProductService? productService,
    CategoryService? categoryService,
  })  : _productService = productService ?? ProductService(),
        _categoryService = categoryService ?? CategoryService();

  @override
  Future<Map<String, dynamic>> getProducts({
    String? categoryId,
    String? search,
    String sort = 'newest',
    double? minPrice,
    double? maxPrice,
    DocumentSnapshot? lastDoc,
    int limit = 12,
  }) =>
      _productService.getProducts(
        categoryId: categoryId,
        search: search,
        sort: sort,
        minPrice: minPrice,
        maxPrice: maxPrice,
        lastDoc: lastDoc,
        limit: limit,
      );

  @override
  Future<List<ProductModel>> getFeaturedProducts() =>
      _productService.getFeaturedProducts();

  @override
  Future<ProductModel> getProduct(String id) => _productService.getProduct(id);

  @override
  Future<List<ProductModel>> getRelatedProducts(
          String productId, String categoryId) =>
      _productService.getRelatedProducts(productId, categoryId);

  @override
  Future<void> addReview(
    String productId,
    double rating,
    String comment,
    String userId,
    String userName,
  ) =>
      _productService.addReview(productId, rating, comment, userId, userName);

  @override
  Future<ProductModel> createProduct(Map<String, dynamic> data) =>
      _productService.createProduct(data);

  @override
  Future<ProductModel> updateProduct(String id, Map<String, dynamic> data) =>
      _productService.updateProduct(id, data);

  @override
  Future<void> deleteProduct(String id) => _productService.deleteProduct(id);

  @override
  Future<List<CategoryModel>> getCategories() =>
      _categoryService.getCategories();

  @override
  Future<CategoryModel> createCategory(Map<String, dynamic> data) =>
      _categoryService.createCategory(data);

  @override
  Future<CategoryModel> updateCategory(String id, Map<String, dynamic> data) =>
      _categoryService.updateCategory(id, data);

  @override
  Future<void> deleteCategory(String id) =>
      _categoryService.deleteCategory(id);
}
