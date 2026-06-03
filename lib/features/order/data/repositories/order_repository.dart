import 'package:three_seasons_project/features/cart/data/models/cart_model.dart';
import 'package:three_seasons_project/features/order/data/models/order_model.dart';
import 'package:three_seasons_project/features/order/domain/repositories/i_order_repository.dart';
import 'package:three_seasons_project/services/order_service.dart';

class OrderRepository implements IOrderRepository {
  final OrderService _service;

  OrderRepository({OrderService? service})
      : _service = service ?? OrderService();

  @override
  Future<OrderModel> createOrder(
    String userId,
    List<CartItemModel> cartItems,
    Map<String, dynamic> shippingAddress,
    String paymentMethod, {
    String? notes,
  }) =>
      _service.createOrder(userId, cartItems, shippingAddress, paymentMethod,
          notes: notes);

  @override
  Future<List<OrderModel>> getUserOrders(String userId) =>
      _service.getUserOrders(userId);

  @override
  Stream<List<OrderModel>> streamUserOrders(String userId) =>
      _service.streamUserOrders(userId);

  @override
  Future<OrderModel> getOrder(String orderId) => _service.getOrder(orderId);

  @override
  Stream<OrderModel?> streamOrder(String orderId) =>
      _service.streamOrder(orderId);

  @override
  Future<OrderModel> cancelOrder(String orderId) =>
      _service.cancelOrder(orderId);

  @override
  Future<List<OrderModel>> getAllOrders({String? status}) =>
      _service.getAllOrders(status: status);

  @override
  Future<OrderModel> updateOrderStatus(String orderId, String status) =>
      _service.updateOrderStatus(orderId, status);
}
