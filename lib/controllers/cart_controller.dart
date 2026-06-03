import 'package:get/get.dart';
import '../models/cart_model.dart';
import '../services/cart_service.dart';

class CartController extends GetxController {
  final _cartService = CartService();

  final cart = Rxn<CartModel>();
  final isLoading = false.obs;
  final error = Rxn<String>();

  List<CartItemModel> get items => cart.value?.items ?? [];
  double get totalPrice => cart.value?.totalPrice ?? 0.0;
  int get totalItems => cart.value?.totalItems ?? 0;
  bool get isEmpty => cart.value == null || (cart.value?.isEmpty ?? true);

  Future<void> fetchCart(String userId) async {
    isLoading.value = true;
    error.value = null;
    try {
      cart.value = await _cartService.getCart(userId);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> addToCart(
    String userId,
    String productId,
    int quantity, {
    String? size,
    String? color,
  }) async {
    isLoading.value = true;
    error.value = null;
    try {
      cart.value = await _cartService.addToCart(
        userId,
        productId,
        quantity,
        size: size,
        color: color,
      );
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> updateItem(String userId, String itemId, int quantity) async {
    isLoading.value = true;
    error.value = null;
    try {
      cart.value = await _cartService.updateCartItem(userId, itemId, quantity);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> removeItem(String userId, String itemId) async {
    isLoading.value = true;
    error.value = null;
    try {
      cart.value = await _cartService.removeFromCart(userId, itemId);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> clearCart(String userId) async {
    isLoading.value = true;
    error.value = null;
    try {
      await _cartService.clearCart(userId);
      cart.value = CartModel(id: userId, userId: userId, items: []);
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  bool isInCart(String productId) {
    if (cart.value == null) return false;
    return cart.value!.items.any((item) => item.product.id == productId);
  }

  void resetCart() {
    cart.value = null;
    error.value = null;
  }

  void clearError() => error.value = null;
}
