import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/pos_sale_model.dart';

import 'bt_printer_stub.dart'
    if (dart.library.io) 'bt_printer_native.dart';

class BtPrinterService extends GetxController {
  static BtPrinterService get to => Get.find();

  final devices = <BtDevice>[].obs;
  final connectedDevice = Rxn<BtDevice>();
  final isScanning = false.obs;
  final isConnecting = false.obs;
  final isConnected = false.obs;

  static const _keyAddress = 'pos_bt_address';
  static const _keyName = 'pos_bt_name';

  @override
  void onInit() {
    super.onInit();
    _restoreLastDevice();
  }

  Future<void> _restoreLastDevice() async {
    if (kIsWeb) return;
    final prefs = await SharedPreferences.getInstance();
    final addr = prefs.getString(_keyAddress) ?? '';
    final name = prefs.getString(_keyName) ?? '';
    if (addr.isNotEmpty) {
      final device = BtDevice(name: name, address: addr);
      connectedDevice.value = device;
      // Reconnect automatically so isConnected reflects reality
      try {
        await BtNative.connect(device);
        isConnected.value = await BtNative.isConnected;
      } catch (_) {
        isConnected.value = false;
      }
    }
  }

  Future<bool> _requestPermissions() async {
    if (kIsWeb) return false;
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.location, // required by plugin on Android < 12
    ].request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  Future<void> loadPairedDevices() async {
    if (kIsWeb) return;
    await _requestPermissions();
    isScanning.value = true;
    try {
      devices.value = await BtNative.getBondedDevices();
    } catch (e) {
      _showError('Failed to load devices', e.toString());
    } finally {
      isScanning.value = false;
    }
  }

  Future<void> connect(BtDevice device) async {
    if (kIsWeb) return;
    isConnecting.value = true;
    try {
      // Ensure permissions are granted before connecting
      final granted = await _requestPermissions();
      if (!granted) {
        _showError('Permission denied',
            'Bluetooth and location permissions are required.');
        return;
      }
      // Disconnect any stale connection first so the plugin THREAD is clear
      try {
        await BtNative.disconnect();
      } catch (_) {}
      await BtNative.connect(device);
      connectedDevice.value = device;
      isConnected.value = true;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAddress, device.address);
      await prefs.setString(_keyName, device.name);
    } catch (e) {
      isConnected.value = false;
      final raw = e.toString();
      // Extract a readable message from PlatformException
      final msg = raw.contains('connect_error')
          ? raw.split('connect_error')[1].replaceAll(RegExp(r'[()"\[\]]'), '').trim()
          : raw;
      _showError('Connection failed', msg.isNotEmpty ? msg : 'Could not connect. Make sure the printer is on and paired.');
    } finally {
      isConnecting.value = false;
    }
  }

  void _showError(String title, String message) {
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (Get.overlayContext != null) {
        Get.snackbar(title, message,
            snackPosition: SnackPosition.BOTTOM,
            duration: const Duration(seconds: 4));
      }
    });
  }

  Future<void> disconnect() async {
    if (kIsWeb) return;
    await BtNative.disconnect();
    isConnected.value = false;
    connectedDevice.value = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAddress);
    await prefs.remove(_keyName);
  }

  Future<bool> testPrint() async {
    if (kIsWeb || !isConnected.value) return false;
    try {
      await BtNative.testPrint();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printImage(Uint8List bytes) async {
    if (kIsWeb || !isConnected.value) return false;
    try {
      await BtNative.printImage(bytes);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> printReceipt(PosSaleModel sale, {int paperWidth = 80}) async {
    if (kIsWeb || !isConnected.value) return false;
    try {
      final charsPerLine = paperWidth == 58 ? 32 : 48;
      final prefs = await SharedPreferences.getInstance();
      final settings = ReceiptSettings(
        storeName:    prefs.getString(ReceiptSettings.kStoreName)    ?? 'TSfootwear',
        storeAddress: prefs.getString(ReceiptSettings.kStoreAddress) ?? '54 St, 115D Corner',
        footer:       prefs.getString(ReceiptSettings.kFooter)       ?? 'Thank you!',
        showId:       prefs.getBool(ReceiptSettings.kShowId)         ?? true,
        showCashier:  prefs.getBool(ReceiptSettings.kShowCashier)    ?? true,
        showDate:     prefs.getBool(ReceiptSettings.kShowDate)       ?? true,
      );
      await BtNative.printReceipt(sale, charsPerLine, settings);
      return true;
    } catch (_) {
      return false;
    }
  }

}

/// Platform-neutral Bluetooth device record
class BtDevice {
  final String name;
  final String address;
  const BtDevice({required this.name, required this.address});
}
