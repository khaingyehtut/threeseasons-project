import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import '../models/pos_sale_model.dart';
import '../models/product_model.dart';
import '../services/offline_service.dart';

class PosController extends GetxController {
  final _db = FirebaseFirestore.instance;

  final cartItems = <PosCartItem>[].obs;
  final paymentMethod = 'cash'.obs;
  final cashGiven = 0.0.obs;
  final orderDiscount = 0.0.obs;
  final orderDiscountType = 'amount'.obs; // 'amount' | 'percent'
  final isProcessing = false.obs;
  final heldOrders = <PosSaleModel>[].obs;
  // Local stock reservations for sales made while offline (productId → qty)
  final reservedStock = <String, int>{}.obs;
  final lastSale = Rxn<PosSaleModel>();
  final salesHistory = <PosSaleModel>[].obs;
  final isLoadingHistory = false.obs;
  final lastError = Rxn<String>();

  // ── Computed ───────────────────────────────────────────────────────────────

  double get subtotal => cartItems.fold(0.0, (acc, i) => acc + i.lineTotal);

  double get discountValue {
    if (orderDiscountType.value == 'percent') {
      return (subtotal * orderDiscount.value / 100).clamp(0, subtotal);
    }
    return orderDiscount.value.clamp(0, subtotal);
  }

  double get total => (subtotal - discountValue).clamp(0, double.infinity);

  double get change =>
      paymentMethod.value == 'cash' ? (cashGiven.value - total).clamp(0, double.infinity) : 0;

  bool get canCharge =>
      total > 0 &&
      (paymentMethod.value == 'card' || cashGiven.value >= total);

  int get cartCount => cartItems.fold(0, (acc, i) => acc + i.qty);

  // ── Cart Operations ───────────────────────────────────────────────────────

  void addToCart(ProductModel product, {String? size, String? color}) {
    final idx = cartItems.indexWhere(
      (i) => i.product.id == product.id && i.size == size && i.color == color,
    );
    if (idx >= 0) {
      cartItems[idx].qty++;
      cartItems.refresh();
    } else {
      cartItems.add(PosCartItem(product: product, qty: 1, size: size, color: color));
    }
  }

  void removeFromCart(int index) => cartItems.removeAt(index);

  void updateQty(int index, int qty) {
    if (qty <= 0) {
      cartItems.removeAt(index);
    } else {
      cartItems[index].qty = qty;
      cartItems.refresh();
    }
  }

  void clearCart() {
    cartItems.clear();
    cashGiven.value = 0;
    orderDiscount.value = 0;
    orderDiscountType.value = 'amount';
    paymentMethod.value = 'cash';
  }

  // ── Hold / Resume ─────────────────────────────────────────────────────────

  void holdOrder(String cashierName) {
    if (cartItems.isEmpty) return;
    final held = PosSaleModel(
      id: 'HELD-${DateTime.now().millisecondsSinceEpoch}',
      items: _cartToItems(),
      subtotal: subtotal,
      discount: discountValue,
      total: total,
      paymentMethod: paymentMethod.value,
      cashGiven: cashGiven.value,
      change: change,
      cashierName: cashierName,
      createdAt: DateTime.now(),
    );
    heldOrders.add(held);
    clearCart();
  }

  String resumeHeldOrder(int index) {
    final held = heldOrders[index];
    heldOrders.removeAt(index);
    clearCart();

    for (final item in held.items) {
      final product = ProductModel(
        id: (item['productId'] as String?) ?? '',
        name: (item['name'] as String?) ?? '',
        price: (item['price'] as num?)?.toDouble() ?? 0,
        thumbnail: (item['thumbnail'] as String?) ?? '',
      );
      final rawSize = (item['size'] as String?) ?? '';
      final rawColor = (item['color'] as String?) ?? '';
      cartItems.add(PosCartItem(
        product: product,
        qty: (item['qty'] as num?)?.toInt() ?? 1,
        size: rawSize.isEmpty ? null : rawSize,
        color: rawColor.isEmpty ? null : rawColor,
      ));
    }

    orderDiscount.value = held.discount;
    orderDiscountType.value = 'amount';
    paymentMethod.value = held.paymentMethod;
    cashGiven.value = held.cashGiven;
    return held.id;
  }

  // ── Process Payment ───────────────────────────────────────────────────────

  Future<PosSaleModel?> processPayment(String cashierName) async {
    if (!canCharge || cartItems.isEmpty) return null;
    isProcessing.value = true;

    // Snapshot items before clearing the cart
    final snapshot = cartItems.toList();

    // Reserve stock locally so product panel shows correct qty immediately
    for (final item in snapshot) {
      reservedStock[item.product.id] =
          (reservedStock[item.product.id] ?? 0) + item.qty;
    }

    try {
      final saleId = 'POS-${DateTime.now().millisecondsSinceEpoch}';
      final sale = PosSaleModel(
        id: saleId,
        items: _cartToItems(),
        subtotal: subtotal,
        discount: discountValue,
        total: total,
        paymentMethod: paymentMethod.value,
        cashGiven: paymentMethod.value == 'cash' ? cashGiven.value : total,
        change: paymentMethod.value == 'cash' ? change : 0,
        cashierName: cashierName,
        createdAt: DateTime.now(),
      );

      final isOnline = !kIsWeb &&
              Get.isRegistered<OfflineService>()
          ? OfflineService.to.isOnline.value
          : true;

      if (isOnline) {
        // ── Online: write directly to Firestore ──────────────────────────
        final batch = _db.batch();
        batch.set(_db.collection('pos_sales').doc(saleId), sale.toJson());
        for (final item in snapshot) {
          batch.update(_db.collection('products').doc(item.product.id), {
            'stock': FieldValue.increment(-item.qty),
            'sold': FieldValue.increment(item.qty),
          });
        }
        await batch.commit();
        // Release reservations — Firestore stream will reflect real stock
        _releaseReserved(snapshot);
      } else {
        // ── Offline: save to queue, keep reservations until synced ───────
        final ops = snapshot
            .map((i) => {'productId': i.product.id, 'qty': i.qty})
            .toList();
        await OfflineService.to.enqueue(saleJson: sale.toJson(), stockOps: ops);
      }

      lastSale.value = sale;
      clearCart();
      return sale;
    } catch (e) {
      // Revert reservations so stock display is correct
      _releaseReserved(snapshot);
      lastError.value = 'Payment failed: $e';
      return null;
    } finally {
      isProcessing.value = false;
    }
  }

  void _releaseReserved(List<PosCartItem> items) {
    for (final item in items) {
      final curr = reservedStock[item.product.id] ?? 0;
      final next = curr - item.qty;
      if (next <= 0) {
        reservedStock.remove(item.product.id);
      } else {
        reservedStock[item.product.id] = next;
      }
    }
  }

  // ── Refund ────────────────────────────────────────────────────────────────

  /// Refunds selected items from a completed sale.
  /// [refundItems] maps productId -> qty to refund.
  Future<String?> processRefund(
      PosSaleModel sale, List<Map<String, dynamic>> refundItems) async {
    isProcessing.value = true;
    try {
      final refundTotal = refundItems.fold<double>(
          0, (acc, i) => acc + ((i['lineTotal'] as num?)?.toDouble() ?? 0));

      final refundId = 'REF-${DateTime.now().millisecondsSinceEpoch}';
      final batch = _db.batch();

      batch.set(_db.collection('pos_sales').doc(refundId), {
        'id': refundId,
        'originalSaleId': sale.id,
        'type': 'refund',
        'items': refundItems,
        'total': refundTotal,
        'cashierName': sale.cashierName,
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Mark original sale as refunded
      batch.update(_db.collection('pos_sales').doc(sale.id), {
        'refundId': refundId,
        'status': 'refunded',
      });

      // Restore stock
      for (final item in refundItems) {
        final pid = item['productId'] as String?;
        final qty = (item['qty'] as num?)?.toInt() ?? 0;
        if (pid != null && pid.isNotEmpty && qty > 0) {
          batch.update(_db.collection('products').doc(pid), {
            'stock': FieldValue.increment(qty),
            'sold': FieldValue.increment(-qty),
          });
        }
      }

      await batch.commit();
      await fetchSalesHistory();
      return refundId;
    } catch (e) {
      lastError.value = 'Refund failed: $e';
      return null;
    } finally {
      isProcessing.value = false;
    }
  }

  // ── Sales History ─────────────────────────────────────────────────────────

  Future<void> fetchSalesHistory() async {
    isLoadingHistory.value = true;
    try {
      final snap = await _db
          .collection('pos_sales')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get();
      salesHistory.value = snap.docs
          .map((d) => PosSaleModel.fromJson({...d.data(), 'id': d.id}))
          .toList();
    } catch (_) {
    } finally {
      isLoadingHistory.value = false;
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _cartToItems() => cartItems
      .map((i) => {
            'productId': i.product.id,
            'name': i.product.name,
            'thumbnail': i.product.firstImage,
            'price': i.product.discountedPrice,
            'qty': i.qty,
            'size': i.size ?? '',
            'color': i.color ?? '',
            'lineTotal': i.lineTotal,
          })
      .toList();
}
