import 'package:three_seasons_project/features/order/data/models/order_model.dart';
import 'package:three_seasons_project/features/cart/data/models/cart_model.dart';

abstract class IOrderRepository {
  Future<OrderModel> createOrder(
    String userId,
    List<CartItemModel> cartItems,
    Map<String, dynamic> shippingAddress,
    String paymentMethod, {
    String? notes,
  });
  Future<List<OrderModel>> getUserOrders(String userId);
  Stream<List<OrderModel>> streamUserOrders(String userId);
  Future<OrderModel> getOrder(String orderId);
  Stream<OrderModel?> streamOrder(String orderId);
  Future<OrderModel> cancelOrder(String orderId);
  Future<List<OrderModel>> getAllOrders({String? status});
  Future<OrderModel> updateOrderStatus(String orderId, String status);
}
