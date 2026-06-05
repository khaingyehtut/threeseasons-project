import 'dart:typed_data';
import 'package:blue_thermal_printer/blue_thermal_printer.dart' as btp;
import 'package:intl/intl.dart';

import '../core/constants.dart';
import '../models/pos_sale_model.dart';
import 'bt_printer_service.dart';


class BtNative {
  static final _bt = btp.BlueThermalPrinter.instance;

  static Future<List<BtDevice>> getBondedDevices() async {
    final list = await _bt.getBondedDevices();
    return list
        .where((d) => d.address?.isNotEmpty == true)
        .map((d) => BtDevice(
              name: d.name?.isNotEmpty == true ? d.name! : d.address!,
              address: d.address!,
            ))
        .toList();
  }

  static Future<void> connect(BtDevice device) async {
    final target = btp.BluetoothDevice(device.name, device.address);
    await _bt.connect(target);
  }

  static Future<void> disconnect() async => _bt.disconnect();

  static Future<bool> get isConnected async =>
      (await _bt.isConnected) ?? false;

  static Future<void> printImage(Uint8List bytes) async =>
      _bt.printImageBytes(bytes);

  static Future<void> testPrint() async {
    await _bt.printNewLine();
    await _bt.printCustom('*** TEST PRINT ***', 2, 1);
    await _bt.printNewLine();
    await _bt.printCustom('Printer is working!', 1, 1);
    await _bt.printCustom(
        DateFormat('dd/MM/yyyy HH:mm').format(DateTime.now()), 1, 1);
    await _bt.printNewLine();
    await _bt.printNewLine();
    await _bt.printNewLine();
  }

  static Future<void> printReceipt(PosSaleModel sale, int charsPerLine, ReceiptSettings settings) async {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    // Header
    await _bt.printNewLine();
    await _bt.printCustom(settings.storeName, 2, 1);
    if (settings.storeAddress.isNotEmpty) {
      await _bt.printCustom(settings.storeAddress, 1, 1);
    }
    await _bt.printCustom('-' * charsPerLine, 1, 0);

    // Sale info
    if (settings.showId)      await _bt.printCustom('Receipt: ${sale.id}', 1, 0);
    if (settings.showDate)    await _bt.printCustom('Date   : ${fmt.format(sale.createdAt)}', 1, 0);
    if (settings.showCashier) await _bt.printCustom('Cashier: ${sale.cashierName}', 1, 0);
    await _bt.printCustom('-' * charsPerLine, 1, 0);

    // Items
    for (final item in sale.items) {
      final name  = item['name'] ?? '';
      final qty   = item['qty']  ?? 1;
      final total = fmtPrice((item['lineTotal'] as num?)?.toDouble());
      await _bt.printCustom('$name  x$qty', 1, 0);
      final size = (item['size'] ?? '').toString();
      if (size.isNotEmpty) {
        await _bt.printCustom('  Sz:$size', 0, 0);
      }
      await _bt.printLeftRight('', total, 1);
    }

    await _bt.printCustom('-' * charsPerLine, 1, 0);

    // Totals
    if (sale.discount > 0) {
      await _bt.printLeftRight(
          'Discount', '-${fmtPrice(sale.discount)}', 1);
    }
    await _bt.printLeftRight('TOTAL', fmtPrice(sale.total), 2); // large

    if (sale.paymentMethod == 'cash') {
      await _bt.printLeftRight('Cash', fmtPrice(sale.cashGiven), 1);
      await _bt.printLeftRight('Change', fmtPrice(sale.change), 1);
    } else {
      await _bt.printLeftRight('Payment', 'Card', 1);
    }

    await _bt.printCustom('-' * charsPerLine, 1, 0);
    if (settings.footer.isNotEmpty) await _bt.printCustom(settings.footer, 1, 1);
    await _bt.printNewLine();
    await _bt.printNewLine();
    await _bt.printNewLine();
    await _bt.paperCut();
  }
}
