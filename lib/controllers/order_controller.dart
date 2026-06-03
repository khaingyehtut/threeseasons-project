import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/notification_model.dart';
import '../models/order_model.dart';
import '../models/cart_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/order_service.dart';

class OrderController extends GetxController {
  final _orderService = OrderService();

  final orders = <OrderModel>[].obs;
  final selectedOrder = Rxn<OrderModel>();
  final isLoading = false.obs;
  final error = Rxn<String>();

  StreamSubscription<List<OrderModel>>? _ordersSubscription;
  StreamSubscription<OrderModel?>? _orderSubscription;

  // ─── Real-time listeners ──────────────────────────────────────────────────────

  void listenToUserOrders(String userId) {
    _ordersSubscription?.cancel();
    isLoading.value = true;
    error.value = null;
    _ordersSubscription = _orderService.streamUserOrders(userId).listen(
      (data) {
        orders.value = data;
        isLoading.value = false;
      },
      onError: (e) {
        error.value = e.toString();
        isLoading.value = false;
      },
    );
  }

  void listenToOrder(String orderId) {
    _orderSubscription?.cancel();
    isLoading.value = true;
    error.value = null;
    selectedOrder.value = null;
    _orderSubscription = _orderService.streamOrder(orderId).listen(
      (order) {
        selectedOrder.value = order;
        isLoading.value = false;
      },
      onError: (e) {
        error.value = e.toString();
        isLoading.value = false;
      },
    );
  }

  void cancelOrderStream() {
    _orderSubscription?.cancel();
    _orderSubscription = null;
  }

  // ─── One-time fetches (kept for backwards compatibility) ──────────────────────

  Future<void> fetchUserOrders(String userId) async {
    isLoading.value = true;
    error.value = null;
    try {
      orders.value = await _orderService.getUserOrders(userId);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<OrderModel?> placeOrder(
    String userId,
    List<CartItemModel> cartItems,
    Map<String, dynamic> shippingAddress,
    String paymentMethod, {
    String? notes,
    double shippingPrice = 0.0,
  }) async {
    isLoading.value = true;
    error.value = null;
    try {
      final order = await _orderService.createOrder(
        userId,
        cartItems,
        shippingAddress,
        paymentMethod,
        notes: notes,
        shippingPrice: shippingPrice,
      );
      orders.insert(0, order);
      selectedOrder.value = order;
      _notifyAdminsNewOrder(order.id, order.orderNumber);
      return order;
    } catch (e) {
      error.value = e.toString();
      return null;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _notifyAdminsNewOrder(String orderId, String orderNumber) async {
    const title = 'New Order Received 🛍️';
    final body  = 'Order #$orderNumber has been placed.';
    try {
      // 1. FCM push to all admin devices
      final idToken = await AuthService().getIdToken();
      if (idToken != null) {
        await NotificationService().sendToAdmins(
          title: title,
          body:  body,
          firebaseIdToken: idToken,
          data: {'type': 'order_placed', 'orderId': orderId},
        );
      }
    } catch (e) {
      debugPrint('[Notification] FCM to admins failed: $e');
    }
    try {
      // 2. In-app notification for every admin (lights up the bell)
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'admin')
          .get();
      for (final doc in snap.docs) {
        await NotificationModel.save(
          userId: doc.id,
          title:  title,
          body:   body,
          type:   'order_placed',
          data:   {'orderId': orderId},
        );
      }
    } catch (e) {
      debugPrint('[Notification] in-app admin notify failed: $e');
    }
  }

  Future<void> fetchOrderById(String id) async {
    isLoading.value = true;
    error.value = null;
    selectedOrder.value = null;
    try {
      selectedOrder.value = await _orderService.getOrder(id);
    } catch (e) {
      error.value = e.toString();
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> cancelOrder(String id) async {
    isLoading.value = true;
    error.value = null;
    try {
      final updatedOrder = await _orderService.cancelOrder(id);
      final idx = orders.indexWhere((o) => o.id == id);
      if (idx >= 0) orders[idx] = updatedOrder;
      if (selectedOrder.value?.id == id) selectedOrder.value = updatedOrder;
      return true;
    } catch (e) {
      error.value = e.toString();
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  void resetOrders() {
    orders.clear();
    selectedOrder.value = null;
    error.value = null;
  }

  void clearError() => error.value = null;

  @override
  void onClose() {
    _ordersSubscription?.cancel();
    _orderSubscription?.cancel();
    super.onClose();
  }
}
