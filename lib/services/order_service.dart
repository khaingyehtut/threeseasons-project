import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order_model.dart';
import '../models/cart_model.dart';
import 'cart_service.dart';
import 'upload_service.dart';

class OrderService {
  static final OrderService _instance = OrderService._internal();
  factory OrderService() => _instance;
  OrderService._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // ─── Create Order ─────────────────────────────────────────────────────────────

  Future<OrderModel> createOrder(
    String userId,
    List<CartItemModel> cartItems,
    Map<String, dynamic> shippingAddress,
    String paymentMethod, {
    String? notes,
    double shippingPrice = 0.0,
  }) async {
    if (cartItems.isEmpty) throw Exception('Cart is empty');

    // Calculate prices
    final itemsPrice = cartItems.fold<double>(
      0,
      (acc, item) => acc + item.subtotal,
    );
    const taxPrice = 0.0;
    final totalPrice = double.parse(
      (itemsPrice + shippingPrice).toStringAsFixed(2),
    );

    // Generate order number
    final ts = DateTime.now().millisecondsSinceEpoch;
    final rand = (ts % 10000).toString().padLeft(4, '0');
    final orderNumber = 'TS-$ts-$rand';

    // Build order items list
    final orderItems = cartItems.map((item) {
      return {
        'productId': item.product.id,
        'name': item.product.name,
        'image': item.product.firstImage,
        'price': item.price,
        'quantity': item.quantity,
        'size': item.size,
        'color': item.color,
      };
    }).toList();

    final orderData = <String, dynamic>{
      'orderNumber': orderNumber,
      'userId': userId,
      'items': orderItems,
      'shippingAddress': shippingAddress,
      'paymentMethod': paymentMethod,
      'paymentStatus': 'pending',
      'itemsPrice': itemsPrice,
      'shippingPrice': shippingPrice,
      'taxPrice': taxPrice,
      'totalPrice': totalPrice,
      'status': 'pending',
      'isPaid': false,
      'isDelivered': false,
      'trackingNumber': '',
      'createdAt': FieldValue.serverTimestamp(),
    };

    if (notes != null && notes.isNotEmpty) {
      orderData['notes'] = notes;
    }

    // Write order + decrement stock in a batch
    final batch = _db.batch();

    final orderRef = _db.collection('orders').doc();
    batch.set(orderRef, orderData);

    for (final item in cartItems) {
      final productRef = _db.collection('products').doc(item.product.id);
      batch.update(productRef, {
        'stock': FieldValue.increment(-item.quantity),
        'sold': FieldValue.increment(item.quantity),
      });
    }

    await batch.commit();

    // Clear cart after successful order
    await CartService().clearCart(userId);

    // Fetch and return the created order
    final doc = await orderRef.get();
    return _orderFromDoc(doc);
  }

  // ─── Get User Orders ──────────────────────────────────────────────────────────

  Future<List<OrderModel>> getUserOrders(String userId) async {
    final snapshot = await _db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .get();

    return snapshot.docs.map((doc) => _orderFromDoc(doc)).toList();
  }

  // ─── Stream User Orders (real-time) ──────────────────────────────────────────

  Stream<List<OrderModel>> streamUserOrders(String userId) {
    return _db
        .collection('orders')
        .where('userId', isEqualTo: userId)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((doc) => _orderFromDoc(doc)).toList();
          list.sort((a, b) =>
              (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
          return list;
        });
  }

  // ─── Get Single Order ─────────────────────────────────────────────────────────

  Future<OrderModel> getOrder(String orderId) async {
    final doc = await _db.collection('orders').doc(orderId).get();
    if (!doc.exists) throw Exception('Order not found');
    return _orderFromDoc(doc);
  }

  // ─── Stream Single Order (real-time) ─────────────────────────────────────────

  Stream<OrderModel?> streamOrder(String orderId) {
    return _db
        .collection('orders')
        .doc(orderId)
        .snapshots()
        .map((doc) => doc.exists ? _orderFromDoc(doc) : null);
  }

  // ─── Cancel Order ─────────────────────────────────────────────────────────────

  Future<OrderModel> cancelOrder(String orderId) async {
    final docRef = _db.collection('orders').doc(orderId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Order not found');

    final data = doc.data()!;
    final currentStatus = data['status'] ?? '';
    if (currentStatus == 'delivered' || currentStatus == 'shipped') {
      throw Exception('Cannot cancel an order that has already been $currentStatus');
    }

    final batch = _db.batch();
    batch.update(docRef, {'status': 'cancelled'});

    // Restore stock for each item
    final rawItems = List<Map<String, dynamic>>.from(
      (data['items'] as List? ?? []).map((i) => Map<String, dynamic>.from(i)),
    );
    for (final item in rawItems) {
      final productId = item['productId']?.toString() ?? '';
      final qty = item['quantity'] is int ? item['quantity'] as int : 1;
      if (productId.isNotEmpty) {
        final productRef = _db.collection('products').doc(productId);
        batch.update(productRef, {
          'stock': FieldValue.increment(qty),
          'sold': FieldValue.increment(-qty),
        });
      }
    }

    await batch.commit();

    final updatedDoc = await docRef.get();
    return _orderFromDoc(updatedDoc);
  }

  // ─── Admin: Get All Orders ────────────────────────────────────────────────────

  Future<List<OrderModel>> getAllOrders({String? status}) async {
    Query query = _db
        .collection('orders')
        .orderBy('createdAt', descending: true);

    if (status != null && status.isNotEmpty) {
      query = query.where('status', isEqualTo: status);
    }

    final snapshot = await query.get();
    return snapshot.docs.map((doc) => _orderFromDoc(doc)).toList();
  }

  // ─── Admin: Update Order Status ────────────────────────────────────────────────

  Future<OrderModel> updateOrderStatus(String orderId, String status) async {
    final update = <String, dynamic>{'status': status};

    if (status == 'delivered') {
      update['isDelivered'] = true;
    }
    if (status == 'paid') {
      update['isPaid'] = true;
      update['paymentStatus'] = 'paid';
    }

    await _db.collection('orders').doc(orderId).update(update);
    final doc = await _db.collection('orders').doc(orderId).get();
    return _orderFromDoc(doc);
  }

  // ─── Helper ───────────────────────────────────────────────────────────────────

  OrderModel _orderFromDoc(DocumentSnapshot doc) {
    final data = Map<String, dynamic>.from(doc.data() as Map);

    double parseDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is double) return v;
      if (v is int) return v.toDouble();
      if (v is String) return double.tryParse(v) ?? 0.0;
      return 0.0;
    }

    final rawItems = data['items'] ?? data['orderItems'];
    final items = rawItems is List
        ? rawItems.map((i) {
            final m = Map<String, dynamic>.from(i);
            if (m['image'] is String) {
              m['image'] = UploadService.fixUrl(m['image'] as String);
            }
            return OrderItemModel.fromJson(m);
          }).toList()
        : <OrderItemModel>[];

    Map<String, dynamic> shippingAddress = {};
    final rawAddr = data['shippingAddress'];
    if (rawAddr is Map) {
      shippingAddress = Map<String, dynamic>.from(rawAddr);
    }

    DateTime? createdAt;
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    }

    return OrderModel(
      id: doc.id,
      orderNumber: data['orderNumber'] ?? '',
      userId: data['userId'] ?? '',
      items: items,
      shippingAddress: shippingAddress,
      paymentMethod: data['paymentMethod'] ?? '',
      paymentStatus: data['paymentStatus'] ?? 'pending',
      itemsPrice: parseDouble(data['itemsPrice']),
      shippingPrice: parseDouble(data['shippingPrice']),
      taxPrice: parseDouble(data['taxPrice']),
      totalPrice: parseDouble(data['totalPrice']),
      status: data['status'] ?? 'pending',
      isPaid: data['isPaid'] ?? false,
      isDelivered: data['isDelivered'] ?? false,
      trackingNumber: data['trackingNumber'] ?? '',
      createdAt: createdAt,
    );
  }
}
