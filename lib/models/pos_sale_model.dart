import 'product_model.dart';

class ReceiptSettings {
  final String storeName;
  final String storeAddress;
  final String footer;
  final bool showId;
  final bool showCashier;
  final bool showDate;

  const ReceiptSettings({
    this.storeName = '၅၄သုံးရာသီဖိနပ်ဆိုင်',
    this.storeAddress = '54 လမ်း, 115D လမ်းထောင့်',
    this.footer = '🙏အားပေးမှုကိုကျေးဇူးတင်ပါတယ်🙏',
    this.showId = true,
    this.showCashier = true,
    this.showDate = true,
  });

  static const kStoreName = 'receipt_store_name';
  static const kStoreAddress = 'receipt_store_address';
  static const kFooter = 'receipt_footer';
  static const kShowId = 'receipt_show_id';
  static const kShowCashier = 'receipt_show_cashier';
  static const kShowDate = 'receipt_show_date';
}

class PosCartItem {
  final ProductModel product;
  int qty;
  String? size;
  String? color;

  PosCartItem({required this.product, this.qty = 1, this.size, this.color});

  double get lineTotal => product.discountedPrice * qty;
}

class PosSaleModel {
  final String id;
  final List<Map<String, dynamic>> items;
  final double subtotal;
  final double discount;
  final double total;
  final String paymentMethod;
  final double cashGiven;
  final double change;
  final String cashierName;
  final DateTime createdAt;
  final String status; // 'completed' | 'refunded'
  final String type; // 'sale' | 'refund'
  final String originalSaleId; // set on refund records
  final double totalCost; // sum of originalPrice * qty for items that have cost
  final double
      totalProfit; // total - totalCost (only meaningful when totalCost > 0)
  final String staffName; // optional: who actually sold (separate from cashier)

  PosSaleModel({
    required this.id,
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.cashGiven,
    required this.change,
    required this.cashierName,
    required this.createdAt,
    this.status = 'completed',
    this.type = 'sale',
    this.originalSaleId = '',
    this.totalCost = 0.0,
    this.totalProfit = 0.0,
    this.staffName = '',
  });

  bool get hasProfitData => totalCost > 0;
  double get profitMarginPercent =>
      (hasProfitData && total > 0) ? (totalProfit / total * 100) : 0;

  bool get isRefundRecord => type == 'refund';
  bool get isRefunded => status == 'refunded';

  PosSaleModel copyWith({String? status, String? refundId}) => PosSaleModel(
        id: id,
        items: items,
        subtotal: subtotal,
        discount: discount,
        total: total,
        paymentMethod: paymentMethod,
        cashGiven: cashGiven,
        change: change,
        cashierName: cashierName,
        createdAt: createdAt,
        status: status ?? this.status,
        type: type,
        originalSaleId: originalSaleId,
        totalCost: totalCost,
        totalProfit: totalProfit,
        staffName: staffName,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'items': items,
        'subtotal': subtotal,
        'discount': discount,
        'total': total,
        'paymentMethod': paymentMethod,
        'cashGiven': cashGiven,
        'change': change,
        'cashierName': cashierName,
        'createdAt': createdAt.toIso8601String(),
        'status': status,
        'type': type,
        'originalSaleId': originalSaleId,
        'totalCost': totalCost,
        'totalProfit': totalProfit,
        'staffName': staffName,
      };

  factory PosSaleModel.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> parseItems(dynamic raw) {
      if (raw == null) return [];
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }

    return PosSaleModel(
      id: json['id'] ?? '',
      items: parseItems(json['items']),
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      discount: (json['discount'] as num?)?.toDouble() ?? 0,
      total: (json['total'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['paymentMethod'] ?? 'cash',
      cashGiven: (json['cashGiven'] as num?)?.toDouble() ?? 0,
      change: (json['change'] as num?)?.toDouble() ?? 0,
      cashierName: json['cashierName'] ?? '',
      createdAt: () {
        final raw = json['createdAt'];
        if (raw == null) return DateTime.now();
        if (raw is String) return DateTime.tryParse(raw) ?? DateTime.now();
        return DateTime.now();
      }(),
      status: json['status'] ?? 'completed',
      type: json['type'] ?? 'sale',
      originalSaleId: json['originalSaleId'] ?? '',
      totalCost: (json['totalCost'] as num?)?.toDouble() ?? 0,
      totalProfit: (json['totalProfit'] as num?)?.toDouble() ?? 0,
      staffName: json['staffName'] ?? '',
    );
  }
}
