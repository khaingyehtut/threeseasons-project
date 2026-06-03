import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../services/product_service.dart';
import '../services/category_service.dart';

class ProductController extends GetxController {
  final _productService = ProductService();
  final _categoryService = CategoryService();

  final products = <ProductModel>[].obs;
  final featuredProducts = <ProductModel>[].obs;
  final categories = <CategoryModel>[].obs;
  final selectedProduct = Rxn<ProductModel>();
  final isLoading = false.obs;
  final isCategoriesLoading = false.obs;
  final error = Rxn<String>();
  final selectedCategory = ''.obs;
  final searchQuery = ''.obs;
  final sortBy = 'newest'.obs;
  final hasMore = true.obs;

  DocumentSnapshot? _lastDoc;

  Future<void> fetchProducts({bool reset = false}) async {
    if (reset) {
      _lastDoc = null;
      products.clear();
      hasMore.value = true;
    }
    if (!hasMore.value && !reset) return;

    isLoading.value = true;
    error.value = null;

    try {
      final result = await _productService.getProducts(
        categoryId: selectedCategory.value.isNotEmpty ? selectedCategory.value : null,
        search: searchQuery.value.isNotEmpty ? searchQuery.value : null,
        sort: sortBy.value,
        lastDoc: _lastDoc,
      );
      final newProducts = result['products'] as List<ProductModel>;
      _lastDoc = result['lastDoc'] as DocumentSnapshot?;
      // When filtering by category, lastDoc is null and all results are returned at once.
      hasMore.value = _lastDoc != null && newProducts.length >= 12;
      if (reset) {
        products.value = newProducts;
      } else {
        products.addAll(newProducts);
      }
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchFeaturedProducts() async {
    isLoading.value = true;
    error.value = null;
    try {
      featuredProducts.value = await _productService.getFeaturedProducts();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> fetchCategories() async {
    isCategoriesLoading.value = true;
    error.value = null;
    try {
      categories.value = await _categoryService.getCategories();
    } catch (e) {
      error.value = e.toString();
    } finally {
      isCategoriesLoading.value = false;
    }
  }

  Future<void> fetchProductById(String id) async {
    isLoading.value = true;
    error.value = null;
    selectedProduct.value = null;
    try {
      selectedProduct.value = await _productService.getProduct(id);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  void setCategory(String categoryId) {
    if (selectedCategory.value == categoryId) return;
    selectedCategory.value = categoryId;
    fetchProducts(reset: true);
  }

  void setSearch(String query) {
    if (searchQuery.value == query) return;
    searchQuery.value = query;
    fetchProducts(reset: true);
  }

  void setSort(String sort) {
    if (sortBy.value == sort) return;
    sortBy.value = sort;
    fetchProducts(reset: true);
  }

  void clearFilters() {
    selectedCategory.value = '';
    searchQuery.value = '';
    sortBy.value = 'newest';
    fetchProducts(reset: true);
  }

  Future<bool> addReview(
    String productId,
    double rating,
    String comment,
    String userId,
    String userName,
  ) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _productService.addReview(productId, rating, comment, userId, userName);
      await fetchProductById(productId);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void clearError() => error.value = null;
}
