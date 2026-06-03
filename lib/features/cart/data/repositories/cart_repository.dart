import 'package:three_seasons_project/features/cart/data/models/cart_model.dart';
import 'package:three_seasons_project/features/cart/domain/repositories/i_cart_repository.dart';
import 'package:three_seasons_project/services/cart_service.dart';

class CartRepository implements ICartRepository {
  final CartService _service;

  CartRepository({CartService? service}) : _service = service ?? CartService();

  @override
  Future<CartModel> getCart(String userId) => _service.getCart(userId);

  @override
  Future<CartModel> addToCart(
    String userId,
    String productId,
    int quantity, {
    String? size,
    String? color,
  }) =>
      _service.addToCart(userId, productId, quantity, size: size, color: color);

  @override
  Future<CartModel> updateCartItem(String userId, String itemId, int quantity) =>
      _service.updateCartItem(userId, itemId, quantity);

  @override
  Future<CartModel> removeFromCart(String userId, String itemId) =>
      _service.removeFromCart(userId, itemId);

  @override
  Future<void> clearCart(String userId) => _service.clearCart(userId);
}
