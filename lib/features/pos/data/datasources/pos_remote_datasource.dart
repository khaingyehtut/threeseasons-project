import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../models/pos_sale_model.dart';

/// Handles all Firestore reads and writes for the POS feature.
class PosRemoteDataSource {
  final FirebaseFirestore _db;

  PosRemoteDataSource({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  Future<void> saveSale(PosSaleModel sale, List<PosCartItem> cartItems) async {
    final batch = _db.batch();
    batch.set(_db.collection('pos_sales').doc(sale.id), sale.toJson());
    for (final item in cartItems) {
      if (item.product.id.startsWith('CUSTOM-')) continue;
      batch.update(_db.collection('products').doc(item.product.id), {
        'stock': FieldValue.increment(-item.qty),
        'sold': FieldValue.increment(item.qty),
      });
    }
    await batch.commit();
  }

  Future<String> saveRefund(
    PosSaleModel originalSale,
    List<Map<String, dynamic>> refundItems,
  ) async {
    final refundId = 'REF-${DateTime.now().millisecondsSinceEpoch}';
    final refundTotal = refundItems.fold<double>(
        0, (acc, i) => acc + ((i['lineTotal'] as num?)?.toDouble() ?? 0));

    double refundProfit = 0;
    for (final item in refundItems) {
      final price = (item['price'] as num?)?.toDouble() ?? 0;
      final originalPrice = (item['originalPrice'] as num?)?.toDouble();
      final qty = (item['qty'] as num?)?.toDouble() ?? 0;
      if (originalPrice != null) {
        refundProfit += (price - originalPrice) * qty;
      }
    }

    final batch = _db.batch();
    batch.set(_db.collection('pos_sales').doc(refundId), {
      'id': refundId,
      'originalSaleId': originalSale.id,
      'type': 'refund',
      'items': refundItems,
      'total': refundTotal,
      'totalProfit': refundProfit,
      'cashierName': originalSale.cashierName,
      'createdAt': DateTime.now().toIso8601String(),
    });
    batch.update(_db.collection('pos_sales').doc(originalSale.id), {
      'refundId': refundId,
      'status': 'refunded',
    });
    for (final item in refundItems) {
      final pid = item['productId'] as String?;
      final qty = (item['qty'] as num?)?.toInt() ?? 0;
      if (pid != null && pid.isNotEmpty && !pid.startsWith('CUSTOM-') && qty > 0) {
        batch.update(_db.collection('products').doc(pid), {
          'stock': FieldValue.increment(qty),
          'sold': FieldValue.increment(-qty),
        });
      }
    }
    await batch.commit();
    return refundId;
  }

  Future<List<PosSaleModel>> getSalesHistory({int limit = 50}) async {
    final snap = await _db
        .collection('pos_sales')
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .get();
    return snap.docs
        .map((d) => PosSaleModel.fromJson({...d.data(), 'id': d.id}))
        .toList();
  }

  /// Syncs a single queued entry — used by the repository during reconnection.
  Future<void> syncEntry({
    required PosSaleModel sale,
    required List<Map<String, dynamic>> stockOps,
  }) async {
    final batch = _db.batch();
    batch.set(_db.collection('pos_sales').doc(sale.id), sale.toJson());
    for (final op in stockOps) {
      final pid = op['productId'] as String;
      if (pid.startsWith('CUSTOM-')) continue;
      batch.update(_db.collection('products').doc(pid), {
        'stock': FieldValue.increment(-(op['qty'] as int)),
        'sold': FieldValue.increment(op['qty'] as int),
      });
    }
    await batch.commit();
  }
}
