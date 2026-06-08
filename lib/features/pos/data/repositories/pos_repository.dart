import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../../../../models/pos_sale_model.dart';
import '../../domain/repositories/i_pos_repository.dart';
import '../datasources/pos_local_datasource.dart';
import '../datasources/pos_remote_datasource.dart';

class PosRepository extends GetxController implements IPosRepository {
  static PosRepository get to => Get.find();

  final PosLocalDataSource _local;
  final PosRemoteDataSource _remote;

  PosRepository({
    PosLocalDataSource? local,
    PosRemoteDataSource? remote,
  })  : _local = local ?? PosLocalDataSource(),
        _remote = remote ?? PosRemoteDataSource();

  final isOnlinObs = true.obs;
  final pendingCountObs = 0.obs;
  final isSyncing = false.obs;

  /// Fires after a successful sync so listeners (e.g. PosController) can refresh.
  final onSyncComplete = StreamController<void>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _connectSub;

  @override
  void onInit() {
    super.onInit();
    if (!kIsWeb) _startConnectivityWatch();
    _refreshPendingCount();
  }

  @override
  void onClose() {
    _connectSub?.cancel();
    onSyncComplete.close();
    super.onClose();
  }

  // ── Connectivity ───────────────────────────────────────────────────────────

  Future<void> _startConnectivityWatch() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      isOnlinObs.value = _hasConnection(initial);
    } catch (_) {}

    _connectSub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _hasConnection(results);
      final wasOffline = !isOnlinObs.value;
      isOnlinObs.value = online;
      if (online && wasOffline && pendingCountObs.value > 0) {
        syncPending();
      }
    });
  }

  bool _hasConnection(List<ConnectivityResult> r) =>
      r.any((c) => c != ConnectivityResult.none);

  // ── IPosRepository ─────────────────────────────────────────────────────────

  @override
  bool get isOnline => isOnlinObs.value;

  @override
  int get pendingCount => pendingCountObs.value;

  @override
  Future<void> saveSale({
    required PosSaleModel sale,
    required List<PosCartItem> cartItems,
  }) async {
    if (isOnline && !kIsWeb) {
      await _remote.saveSale(sale, cartItems);
    } else {
      final stockOps = cartItems
          .where((i) => !i.product.id.startsWith('CUSTOM-'))
          .map((i) => {'productId': i.product.id, 'qty': i.qty})
          .toList();
      await _local.enqueue(sale, stockOps);
      pendingCountObs.value = await _local.count();
    }
  }

  @override
  Future<String> saveRefund({
    required PosSaleModel originalSale,
    required List<Map<String, dynamic>> refundItems,
  }) async {
    return _remote.saveRefund(originalSale, refundItems);
  }

  @override
  Future<List<PosSaleModel>> getSalesHistory({int limit = 50}) =>
      _remote.getSalesHistory(limit: limit);

  @override
  Future<int> syncPending() async {
    if (kIsWeb || isSyncing.value || !isOnline) return pendingCountObs.value;

    isSyncing.value = true;
    final queue = await _local.loadQueue();
    if (queue.isEmpty) {
      isSyncing.value = false;
      return 0;
    }

    final failed = <PosQueueEntry>[];
    for (final entry in queue) {
      try {
        await _remote.syncEntry(sale: entry.sale, stockOps: entry.stockOps);
      } catch (_) {
        failed.add(entry);
      }
    }

    await _local.saveQueue(failed);
    pendingCountObs.value = failed.length;
    isSyncing.value = false;

    if (failed.length < queue.length) {
      // At least one item synced — notify listeners to refresh
      onSyncComplete.add(null);
    }

    return failed.length;
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Future<void> _refreshPendingCount() async {
    pendingCountObs.value = await _local.count();
  }
}
