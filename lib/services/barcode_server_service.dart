import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BarcodeScannerService extends GetxController {
  static BarcodeScannerService get to => Get.find();

  static const _kPort      = 'barcode_server_port';
  static const defaultPort = 8888;

  final isRunning        = false.obs;
  final port             = defaultPort.obs;
  final connectedClients = 0.obs;
  final ipAddress        = ''.obs;
  final lastBarcode      = ''.obs;
  final startError       = ''.obs;

  void Function(String barcode)? onBarcodeReceived;

  ServerSocket?    _server;
  final _sockets = <Socket>[];
  Timer?           _ipTimer;

  @override
  void onInit() {
    super.onInit();
    if (!kIsWeb) {
      _loadPort().then((_) async {
        await _resolveIp();
        await start();
        _startIpRefresh();
      });
    }
  }

  @override
  void onClose() {
    _ipTimer?.cancel();
    _stopInternal();
    super.onClose();
  }

  // Periodically re-resolve the WiFi IP. If the device switches networks the
  // displayed address updates automatically and the server restarts so the new
  // IP is the one shown to the scanner app.
  void _startIpRefresh() {
    _ipTimer?.cancel();
    _ipTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      final prev = ipAddress.value;
      await _resolveIp();
      if (ipAddress.value != prev && ipAddress.value.isNotEmpty) {
        // WiFi network changed — restart so socket is clean on the new interface
        await restart();
      }
    });
  }

  Future<void> _loadPort() async {
    final prefs = await SharedPreferences.getInstance();
    port.value = prefs.getInt(_kPort) ?? defaultPort;
  }

  Future<void> savePort(int p) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kPort, p);
    port.value = p;
    await restart();
  }

  Future<void> _resolveIp() async {
    try {
      final interfaces = await NetworkInterface.list(
          type: InternetAddressType.IPv4, includeLinkLocal: false);
      for (final iface in interfaces) {
        for (final addr in iface.addresses) {
          if (!addr.isLoopback) { ipAddress.value = addr.address; return; }
        }
      }
    } catch (_) {}
  }

  Future<void> start() async {
    if (kIsWeb || isRunning.value) return;
    startError.value = '';
    try {
      // Bind to all interfaces (0.0.0.0) so WiFi IP changes don't abort the socket
      _server = await ServerSocket.bind(
          InternetAddress.anyIPv4, port.value, shared: true);
      isRunning.value = true;
      _server!.listen(
        _onClient,
        onError: (e) {
          startError.value = e.toString();
          // Auto-restart on socket abort (e.g. WiFi reconnect, errno=103)
          isRunning.value = false;
          Future.delayed(const Duration(seconds: 2), () async {
            await _resolveIp();
            await start();
          });
        },
        cancelOnError: false,
      );
    } catch (e) {
      startError.value = 'Cannot start server: $e';
      isRunning.value = false;
    }
  }

  Future<void> stop()    async => _stopInternal();
  Future<void> restart() async { await _stopInternal(); await _resolveIp(); await start(); }

  Future<void> _stopInternal() async {
    for (final s in List.of(_sockets)) { try { s.destroy(); } catch (_) {} }
    _sockets.clear();
    connectedClients.value = 0;
    try { await _server?.close(); } catch (_) {}
    _server = null;
    isRunning.value = false;
  }

  void _onClient(Socket socket) {
    _sockets.add(socket);
    connectedClients.value = _sockets.length;
    try { socket.add(utf8.encode('READY\n')); } catch (_) {}
    final buf = StringBuffer();
    socket.listen(
      (data) {
        buf.write(utf8.decode(data, allowMalformed: true));
        final str   = buf.toString();
        final lines = str.split('\n');
        buf.clear();
        if (!str.endsWith('\n')) buf.write(lines.last);
        final complete = str.endsWith('\n') ? lines : lines.sublist(0, lines.length - 1);
        for (final line in complete) {
          final barcode = line.trim();
          if (barcode.isNotEmpty) {
            lastBarcode.value = barcode;
            onBarcodeReceived?.call(barcode);
            try { socket.add(utf8.encode('OK:$barcode\n')); } catch (_) {}
          }
        }
      },
      onDone:  () => _removeSocket(socket),
      onError: (_) => _removeSocket(socket),
      cancelOnError: true,
    );
  }

  void _removeSocket(Socket socket) {
    _sockets.remove(socket);
    connectedClients.value = _sockets.length;
    try { socket.destroy(); } catch (_) {}
  }

  String get connectionString =>
      ipAddress.value.isNotEmpty ? '${ipAddress.value}:${port.value}' : '';
}
