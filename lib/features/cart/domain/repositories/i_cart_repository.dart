import 'package:three_seasons_project/features/cart/data/models/cart_model.dart';

abstract class ICartRepository {
  Future<CartModel> getCart(String userId);
  Future<CartModel> addToCart(String userId, String productId, int quantity, {String? size, String? color});
  Future<CartModel> updateCartItem(String userId, String itemId, int quantity);
  Future<CartModel> removeFromCart(String userId, String itemId);
  Future<void> clearCart(String userId);
}
