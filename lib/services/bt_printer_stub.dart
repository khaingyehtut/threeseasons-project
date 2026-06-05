// Web stub — Bluetooth not available in the browser
import 'dart:typed_data';
import 'bt_printer_service.dart';
import '../models/pos_sale_model.dart';

class BtNative {
  static Future<List<BtDevice>> getBondedDevices() async => [];
  static Future<void> connect(BtDevice device) async {}
  static Future<void> disconnect() async {}
  static Future<bool> get isConnected async => false;
  static Future<void> printImage(Uint8List bytes) async {}
  static Future<void> testPrint() async {}
  static Future<void> printReceipt(PosSaleModel sale, int charsPerLine, ReceiptSettings settings) async {}
}
