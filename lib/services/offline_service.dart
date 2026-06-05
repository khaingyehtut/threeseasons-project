import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineService extends GetxController {
  static OfflineService get to => Get.find();

  static const _kQueue = 'pos_offline_queue';

  final isOnline = true.obs;
  final pendingCount = 0.obs;
  final isSyncing = false.obs;

  StreamSubscription? _sub;

  @override
  void onInit() {
    super.onInit();
    if (!kIsWeb) _start();
    _loadPendingCount();
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }

  Future<void> _start() async {
    try {
      final initial = await Connectivity().checkConnectivity();
      isOnline.value = _connected(initial);
    } catch (_) {}

    _sub = Connectivity().onConnectivityChanged.listen((results) {
      final online = _connected(results);
      final wasOffline = !isOnline.value;
      isOnline.value = online;
      if (online && wasOffline && pendingCount.value > 0) {
        syncNow();
      }
    });
  }

  bool _connected(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  Future<void> _loadPendingCount() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueue);
    if (raw == null) return;
    try {
      pendingCount.value = (jsonDecode(raw) as List).length;
    } catch (_) {}
  }

  /// Saves an offline sale + stock ops to the local queue.
  Future<void> enqueue({
    required Map<String, dynamic> saleJson,
    required List<Map<String, dynamic>> stockOps,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueue) ?? '[]';
    final list = List<dynamic>.from(jsonDecode(raw));
    list.add({'sale': saleJson, 'ops': stockOps});
    await prefs.setString(_kQueue, jsonEncode(list));
    pendingCount.value = list.length;
  }

  /// Uploads all queued sales to Firestore. Called automatically on reconnect.
  Future<void> syncNow() async {
    if (kIsWeb || isSyncing.value) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kQueue);
    if (raw == null || raw == '[]') return;

    List<dynamic> list;
    try {
      list = jsonDecode(raw) as List;
    } catch (_) {
      return;
    }
    if (list.isEmpty) return;

    isSyncing.value = true;
    final db = FirebaseFirestore.instance;
    final failed = <dynamic>[];

    for (final entry in list) {
      try {
        final saleJson =
            Map<String, dynamic>.from(entry['sale'] as Map);
        final ops = List<Map<String, dynamic>>.from(
            (entry['ops'] as List)
                .map((e) => Map<String, dynamic>.from(e as Map)));

        final batch = db.batch();
        batch.set(
          db.collection('pos_sales').doc(saleJson['id'] as String),
          saleJson,
        );
        for (final op in ops) {
          batch.update(
            db.collection('products').doc(op['productId'] as String),
            {
              'stock': FieldValue.increment(-(op['qty'] as int)),
              'sold': FieldValue.increment(op['qty'] as int),
            },
          );
        }
        await batch.commit();
      } catch (_) {
        failed.add(entry);
      }
    }

    await prefs.setString(_kQueue, jsonEncode(failed));
    pendingCount.value = failed.length;
    isSyncing.value = false;
  }
}
