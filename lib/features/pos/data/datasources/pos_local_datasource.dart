import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../models/pos_sale_model.dart';

/// Manages the offline POS sale queue in SharedPreferences.
/// Each entry holds one sale + its stock deduction ops.
class PosLocalDataSource {
  static const _kQueue = 'pos_offline_queue';

  Future<List<PosQueueEntry>> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueue);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => PosQueueEntry.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> enqueue(PosSaleModel sale, List<Map<String, dynamic>> stockOps) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = await loadQueue();
    queue.add(PosQueueEntry(sale: sale, stockOps: stockOps));
    await prefs.setString(_kQueue, jsonEncode(queue.map((e) => e.toJson()).toList()));
  }

  Future<int> count() async {
    final queue = await loadQueue();
    return queue.length;
  }

  Future<void> saveQueue(List<PosQueueEntry> remaining) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kQueue, jsonEncode(remaining.map((e) => e.toJson()).toList()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kQueue);
  }
}

class PosQueueEntry {
  final PosSaleModel sale;
  final List<Map<String, dynamic>> stockOps;

  const PosQueueEntry({required this.sale, required this.stockOps});

  factory PosQueueEntry.fromJson(Map<String, dynamic> json) => PosQueueEntry(
        sale: PosSaleModel.fromJson(Map<String, dynamic>.from(json['sale'] as Map)),
        stockOps: List<Map<String, dynamic>>.from(
          (json['ops'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
        ),
      );

  Map<String, dynamic> toJson() => {
        'sale': sale.toJson(),
        'ops': stockOps,
      };
}
