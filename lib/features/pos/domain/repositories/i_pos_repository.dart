import '../../../../models/pos_sale_model.dart';

abstract class IPosRepository {
  /// Saves a completed sale. Writes to Firestore if online, queues locally if offline.
  /// Updates product stock in the same batch.
  Future<void> saveSale({
    required PosSaleModel sale,
    required List<PosCartItem> cartItems,
  });

  /// Saves a refund record and marks the original sale as refunded.
  /// Restores stock for the refunded items.
  Future<String> saveRefund({
    required PosSaleModel originalSale,
    required List<Map<String, dynamic>> refundItems,
  });

  /// Loads the most recent [limit] sales from Firestore.
  Future<List<PosSaleModel>> getSalesHistory({int limit = 50});

  /// Loads all sales (and refunds) for a specific calendar day.
  Future<List<PosSaleModel>> getSalesHistoryForDate(DateTime date);

  /// Number of sales waiting to be synced to Firestore.
  int get pendingCount;

  /// Whether the device currently has network connectivity.
  bool get isOnline;

  /// Uploads all queued offline sales to Firestore.
  /// Returns how many items failed.
  Future<int> syncPending();
}
