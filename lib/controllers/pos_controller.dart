import 'dart:async';

import 'package:get/get.dart';

import '../features/pos/data/repositories/pos_repository.dart';
import '../models/pos_sale_model.dart';
import '../models/product_model.dart';

class PosController extends GetxController {
  final _repo = PosRepository.to;

  final cartItems = <PosCartItem>[].obs;
  final paymentMethod = 'cash'.obs;
  final cashGiven = 0.0.obs;
  final orderDiscount = 0.0.obs;
  final orderDiscountType = 'amount'.obs; // 'amount' | 'percent'
  final isProcessing = false.obs;
  final heldOrders = <PosSaleModel>[].obs;
  final lastSale = Rxn<PosSaleModel>();
  final salesHistory = <PosSaleModel>[].obs;
  final isLoadingHistory = false.obs;
  final lastError = Rxn<String>();

  // Local stock reservations for sales made while offline (productId → qty)
  final reservedStock = <String, int>{}.obs;

  StreamSubscription<void>? _syncSub;

  @override
  void onInit() {
    super.onInit();
    // Refresh sales history whenever the offline queue finishes syncing
    _syncSub = _repo.onSyncComplete.stream.listen((_) => fetchSalesHistory());
  }

  @override
  void onClose() {
    _syncSub?.cancel();
    super.onClose();
  }

  // ── Computed ───────────────────────────────────────────────────────────────

  double get subtotal => cartItems.fold(0.0, (acc, i) => acc + i.lineTotal);

  double get discountValue {
    if (orderDiscountType.value == 'percent') {
      return (subtotal * orderDiscount.value / 100).clamp(0, subtotal);
    }
    return orderDiscount.value.clamp(0, subtotal);
  }

  double get total => (subtotal - discountValue).clamp(0, double.infinity);

  double get change => paymentMethod.value == 'cash'
      ? (cashGiven.value - total).clamp(0, double.infinity)
      : 0;

  bool get canCharge =>
      total > 0 && (paymentMethod.value != 'cash' || cashGiven.value >= total);

  int get cartCount => cartItems.fold(0, (acc, i) => acc + i.qty);

  // ── Cart ───────────────────────────────────────────────────────────────────

  void addToCart(ProductModel product, {String? size, String? color}) {
    final idx = cartItems.indexWhere(
      (i) => i.product.id == product.id && i.size == size && i.color == color,
    );
    if (idx >= 0) {
      cartItems[idx].qty++;
      cartItems.refresh();
    } else {
      cartItems
          .add(PosCartItem(product: product, qty: 1, size: size, color: color));
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

  // ── Hold / Resume ──────────────────────────────────────────────────────────

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

  // ── Payment ────────────────────────────────────────────────────────────────

  Future<PosSaleModel?> processPayment(
    String cashierName, {
    String staffName = '',
  }) async {
    if (!canCharge || cartItems.isEmpty) return null;
    isProcessing.value = true;

    final snapshot = cartItems.toList();
    _reserveStock(snapshot);

    try {
      final saleId = 'POS-${DateTime.now().millisecondsSinceEpoch}';
      final costTotal = _calcTotalCost(snapshot);
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
        totalCost: costTotal,
        totalProfit: costTotal > 0 ? total - costTotal : 0,
        staffName: staffName,
      );

      await _repo.saveSale(sale: sale, cartItems: snapshot);
      _releaseReserved(snapshot);
      lastSale.value = sale;
      clearCart();
      return sale;
    } catch (e) {
      _releaseReserved(snapshot);
      lastError.value = 'Payment failed: $e';
      return null;
    } finally {
      isProcessing.value = false;
    }
  }

  // ── Refund ─────────────────────────────────────────────────────────────────

  /// Fire-and-forget refund: optimistically marks the sale in the local list,
  /// writes to Firestore in the background, then reconciles from the server.
  void queueRefund(
    PosSaleModel sale,
    List<Map<String, dynamic>> refundItems,
  ) {
    // Optimistic update: mark as refunded immediately
    final idx = salesHistory.indexWhere((s) => s.id == sale.id);
    if (idx >= 0) {
      salesHistory[idx] = salesHistory[idx].copyWith(status: 'refunded');
      salesHistory.refresh();
    }
    _repo
        .saveRefund(originalSale: sale, refundItems: refundItems)
        .then((_) => fetchSalesHistory())
        .catchError((e) {
      lastError.value = 'Refund failed: $e';
      fetchSalesHistory(); // revert optimistic update
    });
  }

  // ── Sales History ──────────────────────────────────────────────────────────

  Future<void> fetchSalesHistory({DateTime? date}) async {
    isLoadingHistory.value = true;
    try {
      final day = date ?? DateTime.now();
      salesHistory.value = await _repo.getSalesHistoryForDate(day);
    } catch (_) {
    } finally {
      isLoadingHistory.value = false;
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _reserveStock(List<PosCartItem> items) {
    for (final item in items) {
      if (item.product.id.startsWith('CUSTOM-')) continue;
      reservedStock[item.product.id] =
          (reservedStock[item.product.id] ?? 0) + item.qty;
    }
  }

  void _releaseReserved(List<PosCartItem> items) {
    for (final item in items) {
      if (item.product.id.startsWith('CUSTOM-')) continue;
      final next = (reservedStock[item.product.id] ?? 0) - item.qty;
      if (next <= 0) {
        reservedStock.remove(item.product.id);
      } else {
        reservedStock[item.product.id] = next;
      }
    }
  }

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
            if (i.product.originalPrice != null)
              'originalPrice': i.product.originalPrice,
            if (i.product.originalPrice != null)
              'itemProfit':
                  (i.product.discountedPrice - i.product.originalPrice!) *
                      i.qty,
          })
      .toList();

  double _calcTotalCost(List<PosCartItem> items) => items.fold(0.0, (acc, i) {
        final op = i.product.originalPrice;
        return acc + (op != null ? op * i.qty : 0.0);
      });
}
