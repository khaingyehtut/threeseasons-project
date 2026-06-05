import 'dart:async';
import 'dart:math' show max;
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:shared_preferences/shared_preferences.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/pos_controller.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../models/pos_sale_model.dart';
import '../../models/product_model.dart';
import '../../models/category_model.dart';
import '../../services/barcode_server_service.dart';
import '../../services/bt_printer_service.dart';
import '../../services/offline_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// POS Screen
// ─────────────────────────────────────────────────────────────────────────────

class PosScreen extends StatefulWidget {
  const PosScreen({super.key});

  @override
  State<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends State<PosScreen>
    with SingleTickerProviderStateMixin {
  late final PosController _pos;
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _pos = Get.put(PosController());
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1) _pos.fetchSalesHistory();
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Offline / pending-sync banner
        if (!kIsWeb)
          Obx(() {
            final svc =
                Get.isRegistered<OfflineService>() ? OfflineService.to : null;
            if (svc == null) return const SizedBox.shrink();
            final offline = !svc.isOnline.value;
            final pending = svc.pendingCount.value;
            final syncing = svc.isSyncing.value;
            if (!offline && pending == 0) return const SizedBox.shrink();
            final bgColor =
                offline ? const Color(0xFFE65100) : const Color(0xFF2E7D32);
            return Container(
              color: bgColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              child: Row(children: [
                Icon(
                  offline
                      ? Icons.wifi_off_rounded
                      : (syncing
                          ? Icons.sync_rounded
                          : Icons.cloud_done_rounded),
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    offline
                        ? 'Offline — sales saved locally${pending > 0 ? ' ($pending pending)' : ''}'
                        : syncing
                            ? 'Syncing $pending sale${pending == 1 ? '' : 's'}...'
                            : '$pending sale${pending == 1 ? '' : 's'} synced ✓',
                    style: GoogleFonts.poppins(
                        fontSize: 11,
                        color: Colors.white,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                if (!offline && pending > 0 && !syncing)
                  GestureDetector(
                    onTap: () => OfflineService.to.syncNow(),
                    child: Text('Sync now',
                        style: GoogleFonts.poppins(
                            fontSize: 11,
                            color: Colors.white,
                            decoration: TextDecoration.underline,
                            decorationColor: Colors.white)),
                  ),
              ]),
            );
          }),

        // Tab bar header
        Container(
          color: AppColors.card,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMedium,
            indicatorColor: AppColors.primary,
            labelStyle:
                GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: const [
              Tab(icon: Icon(Icons.point_of_sale_rounded), text: 'POS'),
              Tab(icon: Icon(Icons.history_rounded), text: 'Sales History'),
              Tab(icon: Icon(Icons.dashboard_rounded), text: 'Dashboard'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              _PosTab(pos: _pos),
              _SalesHistoryTab(pos: _pos),
              _PosDashboardTab(pos: _pos),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POS Tab (main selling screen)
// ─────────────────────────────────────────────────────────────────────────────

class _PosTab extends StatefulWidget {
  final PosController pos;
  const _PosTab({required this.pos});

  @override
  State<_PosTab> createState() => _PosTabState();
}

class _PosTabState extends State<_PosTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final w = MediaQuery.of(context).size.width;
    if (w >= 800) {
      return Row(
        children: [
          Expanded(flex: 6, child: _ProductPanel(pos: widget.pos)),
          Container(width: 1, color: AppColors.border),
          SizedBox(width: 340, child: _CartPanel(pos: widget.pos)),
        ],
      );
    }
    // Mobile: product panel + floating cart FAB
    return Stack(
      children: [
        _ProductPanel(pos: widget.pos),
        Positioned(
          bottom: 16,
          right: 16,
          child: Obx(() => FloatingActionButton.extended(
                backgroundColor: AppColors.primary,
                onPressed: () => _showMobileCart(context, widget.pos),
                icon: const Icon(Icons.shopping_cart_rounded,
                    color: Colors.white),
                label: Text(
                  'Cart (${widget.pos.cartCount})',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w600),
                ),
              )),
        ),
      ],
    );
  }

  void _showMobileCart(BuildContext context, PosController pos) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.85,
        child: _CartPanel(pos: pos),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Panel (left side)
// ─────────────────────────────────────────────────────────────────────────────

class _ProductPanel extends StatefulWidget {
  final PosController pos;
  const _ProductPanel({required this.pos});

  @override
  State<_ProductPanel> createState() => _ProductPanelState();
}

class _ProductPanelState extends State<_ProductPanel> {
  final _searchCtrl = TextEditingController();
  final _scanFocus = FocusNode();
  final _searchFocus = FocusNode();
  final _beep  = AudioPlayer();
  final _error = AudioPlayer();
  String _query = '';
  String _categoryId = '';
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;
  Timer? _debounce;
  StreamSubscription? _productSub;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _subscribeProducts();
    // Rebuild when offline stock reservations change
    ever(widget.pos.reservedStock, (_) {
      if (mounted) setState(() {});
    });
    // Receive barcodes from companion app over WiFi
    if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
      BarcodeScannerService.to.onBarcodeReceived = (barcode) {
        if (mounted) _onBarcodeSubmit(barcode);
      };
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _scanFocus.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    _productSub?.cancel();
    if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
      BarcodeScannerService.to.onBarcodeReceived = null;
    }
    _beep.dispose();
    _error.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('categories').get();
      if (mounted) {
        setState(() {
          _categories = snap.docs
              .map((d) =>
                  CategoryModel.fromJson({...d.data() as Map, 'id': d.id}))
              .toList();
        });
      }
    } catch (_) {}
  }

  void _subscribeProducts() {
    setState(() => _loading = true);
    _productSub?.cancel();
    _productSub = FirebaseFirestore.instance
        .collection('products')
        .where('isActive', isEqualTo: true)
        .snapshots()
        .listen((snap) {
      if (mounted) {
        setState(() {
          _products = snap.docs
              .map((d) =>
                  ProductModel.fromJson({...d.data() as Map, 'id': d.id}))
              .toList();
          _loading = false;
        });
      }
    }, onError: (_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  List<ProductModel> get _filtered {
    var list = _products;

    // Subtract offline-reserved qty so stock is accurate while offline
    final reserved = widget.pos.reservedStock;
    if (reserved.isNotEmpty) {
      list = list.map((p) {
        final r = reserved[p.id] ?? 0;
        return r > 0 ? p.copyWith(stock: (p.stock - r).clamp(0, p.stock)) : p;
      }).toList();
    }

    if (_categoryId.isNotEmpty) {
      list = list.where((p) => p.category?.id == _categoryId).toList();
    }
    if (_query.isNotEmpty) {
      final q = _query.toLowerCase();
      list = list
          .where((p) =>
              p.name.toLowerCase().contains(q) ||
              p.barcode.contains(q) ||
              p.brand.toLowerCase().contains(q))
          .toList();
    }
    return list;
  }

  void _onBarcodeSubmit(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    _debounce?.cancel();

    // Step 1: show barcode in search bar
    _searchCtrl.text = trimmed;
    setState(() => _query = '');

    // Step 2: after short delay — match, add or error
    Future.delayed(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      final exact = _products
          .where((p) => p.barcode.trim() == trimmed)
          .toList();
      if (exact.isNotEmpty) {
        // Match — add to cart + beep + clear bar
        _addProductToCart(exact.first);
        _searchCtrl.clear();
      } else {
        // No match — error sound, keep barcode in bar
        _error.play(AssetSource('sounds/error.mp3'));
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _addProductToCart(ProductModel product) {
    widget.pos.addToCart(product);
    _beep.play(AssetSource('sounds/beeb.mp3'));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // ── Search / Scan bar ──────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(12),
          color: AppColors.card,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _scanFocus,
                  onSubmitted: _onBarcodeSubmit,
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Scan barcode or search product...',
                    prefixIcon:
                        const Icon(Icons.qr_code_scanner_rounded, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                              _scanFocus.requestFocus();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: AppColors.bg,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _subscribeProducts,
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'Reload products',
                color: AppColors.textMedium,
              ),
            ],
          ),
        ),

        // ── Category chips ─────────────────────────────────────────────────
        if (_categories.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: [
                _CatChip(
                  label: 'All',
                  selected: _categoryId.isEmpty,
                  onTap: () => setState(() => _categoryId = ''),
                ),
                ...(_categories.map((c) => _CatChip(
                      label: c.name,
                      selected: _categoryId == c.id,
                      onTap: () => setState(() => _categoryId = c.id),
                    ))),
              ],
            ),
          ),

        // ── Product grid ───────────────────────────────────────────────────
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded,
                              size: 48, color: AppColors.textLight),
                          const SizedBox(height: 8),
                          Text('No products found',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textMedium)),
                        ],
                      ),
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: 180,
                        mainAxisExtent: 200,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _ProductCard(
                        product: _filtered[i],
                        onTap: () => _addProductToCart(_filtered[i]),
                      ),
                    ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Chip
// ─────────────────────────────────────────────────────────────────────────────

class _CatChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _CatChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: selected ? Colors.white : AppColors.textMedium,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final outOfStock = product.stock <= 0;
    return GestureDetector(
      onTap: outOfStock ? null : onTap,
      child: Opacity(
        opacity: outOfStock ? 0.45 : 1.0,
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image
              Expanded(
                child: ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(12)),
                  child: product.firstImage.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: product.firstImage,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          placeholder: (_, __) =>
                              Container(color: AppColors.bg),
                          errorWidget: (_, __, ___) => Container(
                              color: AppColors.bg,
                              child: const Icon(Icons.image_outlined)),
                        )
                      : Container(
                          color: AppColors.bg,
                          child: const Center(
                              child: Icon(Icons.image_outlined, size: 32)),
                        ),
                ),
              ),
              // Info
              Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          fmtPrice(product.discountedPrice),
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: outOfStock
                                ? AppColors.textLight.withValues(alpha: 0.2)
                                : AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            outOfStock ? 'Out' : '${product.stock}',
                            style: GoogleFonts.poppins(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: outOfStock
                                  ? AppColors.textLight
                                  : AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart Panel (right side)
// ─────────────────────────────────────────────────────────────────────────────

class _CartPanel extends StatefulWidget {
  final PosController pos;
  const _CartPanel({required this.pos});

  @override
  State<_CartPanel> createState() => _CartPanelState();
}

class _CartPanelState extends State<_CartPanel> {
  final _cashCtrl = TextEditingController();
  final _discountCtrl = TextEditingController();
  bool _showNumpad = false;

  PosController get pos => widget.pos;

  @override
  void dispose() {
    _cashCtrl.dispose();
    _discountCtrl.dispose();
    super.dispose();
  }

  String get _cashierName =>
      Get.find<AuthController>().user.value?.name ?? 'Admin';

  // ── Helper: cart items list ───────────────────────────────────────────────

  Widget _buildCartList() {
    if (pos.cartItems.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.shopping_cart_outlined,
              size: 52, color: AppColors.textLight),
          const SizedBox(height: 10),
          Text('Cart is empty',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 14)),
          const SizedBox(height: 4),
          Text('Scan or tap a product to add',
              style: GoogleFonts.poppins(
                  color: AppColors.textLight, fontSize: 12)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: pos.cartItems.length,
      itemBuilder: (_, i) => _CartItemTile(
        item: pos.cartItems[i],
        onRemove: () => pos.removeFromCart(i),
        onQtyChange: (q) => pos.updateQty(i, q),
      ),
    );
  }

  // ── Helper: payment area (replaces cart list) ─────────────────────────────

  Widget _buildPaymentArea() {
    final isCash = pos.paymentMethod.value == 'cash';
    return Column(
      children: [
        // Payment method toggle
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            _PaymentBtn(
              label: 'Cash',
              icon: Icons.payments_rounded,
              selected: isCash,
              onTap: () => pos.paymentMethod.value = 'cash',
            ),
            const SizedBox(width: 8),
            _PaymentBtn(
              label: 'Card',
              icon: Icons.credit_card_rounded,
              selected: !isCash,
              onTap: () => pos.paymentMethod.value = 'card',
            ),
          ]),
        ),
        const SizedBox(height: 12),

        // Cash numpad (fills remaining space)
        if (isCash)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _CashNumpad(
                value: pos.cashGiven.value,
                total: pos.total,
                onChanged: (v) {
                  pos.cashGiven.value = v;
                  _cashCtrl.text = v > 0 ? v.toStringAsFixed(0) : '';
                },
              ),
            ),
          ),

        // Card view
        if (!isCash)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.credit_card_rounded,
                      size: 48, color: AppColors.primary),
                ),
                const SizedBox(height: 16),
                Text('Card Payment',
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(fmtPrice(pos.total),
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: 8),
                Text('Press CHARGE to confirm',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textMedium)),
              ]),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() => Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.card,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  // Back arrow when payment is open
                  if (_showNumpad)
                    GestureDetector(
                      onTap: () => setState(() => _showNumpad = false),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(Icons.arrow_back_ios_rounded,
                            size: 18, color: AppColors.primary),
                      ),
                    ),
                  Icon(
                    _showNumpad
                        ? Icons.payment_rounded
                        : Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _showNumpad ? 'Payment' : 'Current Sale',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (pos.heldOrders.isNotEmpty && !_showNumpad)
                    TextButton.icon(
                      onPressed: () => _showHeldOrders(context),
                      icon: const Icon(Icons.pause_circle_outline, size: 16),
                      label: Text('${pos.heldOrders.length} held',
                          style: GoogleFonts.poppins(fontSize: 11)),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.secondary),
                    ),
                  IconButton(
                    onPressed: pos.cartItems.isEmpty
                        ? null
                        : () => _confirmClear(context),
                    icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                    tooltip: 'Clear cart',
                    color: AppColors.textMedium,
                  ),
                ],
              ),
            ),

            // ── Main area: cart items OR payment overlay ───────────────────
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, anim) => SlideTransition(
                  position: Tween(
                    begin: child.key == const ValueKey('payment')
                        ? const Offset(0, 1)
                        : const Offset(0, -1),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
                child: _showNumpad
                    ? KeyedSubtree(
                        key: const ValueKey('payment'),
                        child: _buildPaymentArea(),
                      )
                    : KeyedSubtree(
                        key: const ValueKey('cart'),
                        child: _buildCartList(),
                      ),
              ),
            ),

            // ── Footer: always pinned at bottom when cart has items ─────────
            if (pos.cartItems.isNotEmpty)
              Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.border)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 12,
                      offset: const Offset(0, -3),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Totals summary (compact)
                    if (!_showNumpad) ...[
                      _TotalRow('Subtotal', fmtPrice(pos.subtotal)),
                      Row(children: [
                        Text('Discount',
                            style: GoogleFonts.poppins(
                                fontSize: 13, color: AppColors.textMedium)),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showDiscountDialog(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              pos.orderDiscount.value > 0
                                  ? (pos.orderDiscountType.value == 'percent'
                                      ? '${pos.orderDiscount.value.toStringAsFixed(0)}%'
                                      : fmtPrice(pos.orderDiscount.value))
                                  : 'Add',
                              style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary),
                            ),
                          ),
                        ),
                      ]),
                      const Divider(height: 16),
                    ],
                    // TOTAL row (always shown)
                    Row(children: [
                      Text('TOTAL',
                          style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary)),
                      const Spacer(),
                      Text(fmtPrice(pos.total),
                          style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ]),
                    const SizedBox(height: 12),

                    // Action buttons
                    if (!_showNumpad)
                      // Normal mode: Hold + PAY
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () {
                              pos.holdOrder(_cashierName);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Order held',
                                      style: GoogleFonts.poppins()),
                                  backgroundColor: AppColors.textMedium,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.pause_rounded, size: 16),
                            label: Text('Hold',
                                style: GoogleFonts.poppins(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textMedium,
                              side: BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: () => setState(() => _showNumpad = true),
                            icon: const Icon(Icons.payment_rounded, size: 18),
                            label: Text('PAY',
                                style: GoogleFonts.poppins(
                                    fontSize: 15, fontWeight: FontWeight.w700)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ])
                    else
                      // Payment mode: Cancel + CHARGE
                      Row(children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                setState(() => _showNumpad = false),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: Text('Cancel',
                                style: GoogleFonts.poppins(fontSize: 13)),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textMedium,
                              side: BorderSide(color: AppColors.border),
                              padding: const EdgeInsets.symmetric(vertical: 13),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: pos.isProcessing.value
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton.icon(
                                  onPressed: pos.canCharge
                                      ? () => _processPayment(context)
                                      : null,
                                  icon: const Icon(Icons.check_circle_rounded,
                                      size: 18),
                                  label: Text('CHARGE',
                                      style: GoogleFonts.poppins(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.white,
                                    disabledBackgroundColor: AppColors.textLight
                                        .withValues(alpha: 0.3),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 13),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(12)),
                                  ),
                                ),
                        ),
                      ]),
                  ],
                ),
              ),
          ],
        ));
  }

  Future<void> _processPayment(BuildContext context) async {
    final sale = await pos.processPayment(_cashierName);
    if (sale == null) return;
    // Cart is now cleared — hide payment view so the (empty) cart shows
    _cashCtrl.clear();
    _discountCtrl.clear();
    if (mounted) setState(() => _showNumpad = false);
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (_) => _ReceiptDialog(sale: sale),
      );
    }
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Clear Cart',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text('Remove all items from cart?',
            style: GoogleFonts.poppins(color: AppColors.textMedium)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              pos.clearCart();
              _cashCtrl.clear();
              _discountCtrl.clear();
              setState(() => _showNumpad = false);
              Navigator.pop(context);
            },
            style:
                ElevatedButton.styleFrom(backgroundColor: AppColors.secondary),
            child:
                Text('Clear', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showDiscountDialog(BuildContext context) {
    final ctrl = TextEditingController(
      text: pos.orderDiscount.value > 0
          ? pos.orderDiscount.value.toStringAsFixed(0)
          : '',
    );
    String type = pos.orderDiscountType.value;
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          backgroundColor: AppColors.card,
          title: Text('Order Discount',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _DiscTypeBtn(
                      label: 'Amount (Ks)',
                      selected: type == 'amount',
                      onTap: () => setS(() => type = 'amount')),
                  const SizedBox(width: 8),
                  _DiscTypeBtn(
                      label: 'Percent (%)',
                      selected: type == 'percent',
                      onTap: () => setS(() => type = 'percent')),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: GoogleFonts.poppins(color: AppColors.textPrimary),
                decoration: InputDecoration(
                  hintText: type == 'percent' ? 'e.g. 10' : 'e.g. 5000',
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                pos.orderDiscount.value = 0;
                Navigator.pop(ctx);
              },
              child: Text('Remove',
                  style: GoogleFonts.poppins(color: AppColors.secondary)),
            ),
            ElevatedButton(
              onPressed: () {
                pos.orderDiscount.value = double.tryParse(ctrl.text) ?? 0;
                pos.orderDiscountType.value = type;
                Navigator.pop(ctx);
              },
              style:
                  ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text('Apply',
                  style: GoogleFonts.poppins(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showHeldOrders(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Obx(() => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Held Orders (${pos.heldOrders.length})',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: AppColors.textPrimary)),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: pos.heldOrders.length,
                  itemBuilder: (_, i) {
                    final o = pos.heldOrders[i];
                    return ListTile(
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.pause_circle_outline,
                            color: AppColors.primary),
                      ),
                      title: Text(o.id,
                          style: GoogleFonts.poppins(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      subtitle: Text(
                          '${o.items.length} items • ${fmtPrice(o.total)}',
                          style: GoogleFonts.poppins(fontSize: 12)),
                      trailing: TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          final id = pos.resumeHeldOrder(i);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Resumed: $id',
                                style: GoogleFonts.poppins()),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ));
                        },
                        child: Text('Resume',
                            style:
                                GoogleFonts.poppins(color: AppColors.primary)),
                      ),
                    );
                  },
                ),
              ),
            ],
          )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cart Item Tile
// ─────────────────────────────────────────────────────────────────────────────

class _CartItemTile extends StatelessWidget {
  final PosCartItem item;
  final VoidCallback onRemove;
  final ValueChanged<int> onQtyChange;

  const _CartItemTile({
    required this.item,
    required this.onRemove,
    required this.onQtyChange,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: item.product.firstImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: item.product.firstImage,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 44,
                    height: 44,
                    color: AppColors.border,
                    child: const Icon(Icons.image_outlined, size: 20),
                  ),
          ),
          const SizedBox(width: 10),
          // Name + size/color
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                if (item.size != null || item.color != null)
                  Text(
                    [
                      if (item.size != null) 'Size: ${item.size}',
                      if (item.color != null) item.color!
                    ].join(' • '),
                    style: GoogleFonts.poppins(
                        fontSize: 10, color: AppColors.textMedium),
                  ),
                Text(
                  fmtPrice(item.lineTotal),
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary),
                ),
              ],
            ),
          ),
          // Qty controls
          Row(
            children: [
              _QtyBtn(
                icon: Icons.remove,
                onTap: () => onQtyChange(item.qty - 1),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${item.qty}',
                  style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                ),
              ),
              _QtyBtn(
                icon: Icons.add,
                onTap: () => onQtyChange(item.qty + 1),
              ),
            ],
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close, size: 16),
            color: AppColors.textLight,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, size: 14, color: AppColors.primary),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptDialog extends StatefulWidget {
  final PosSaleModel sale;
  const _ReceiptDialog({required this.sale});

  @override
  State<_ReceiptDialog> createState() => _ReceiptDialogState();
}

class _ReceiptDialogState extends State<_ReceiptDialog> {
  final _repaintKey = GlobalKey();
  bool _printing = false;
  ReceiptSettings _settings = const ReceiptSettings();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _settings = ReceiptSettings(
        storeName: prefs.getString(ReceiptSettings.kStoreName) ?? 'TSfootwear',
        storeAddress: prefs.getString(ReceiptSettings.kStoreAddress) ??
            '54 St, 115D Corner',
        footer: prefs.getString(ReceiptSettings.kFooter) ?? 'Thank you!',
        showId: prefs.getBool(ReceiptSettings.kShowId) ?? true,
        showCashier: prefs.getBool(ReceiptSettings.kShowCashier) ?? true,
        showDate: prefs.getBool(ReceiptSettings.kShowDate) ?? true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 10),
                  Text('Payment Successful',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            // Receipt body (scrollable) — wrapped for image capture
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: RepaintBoundary(
                  key: _repaintKey,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: _ReceiptBody(sale: widget.sale, settings: _settings),
                  ),
                ),
              ),
            ),
            // Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 16),
                          label: Text('Close',
                              style: GoogleFonts.poppins(fontSize: 13)),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textMedium,
                              side: BorderSide(color: AppColors.border)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed:
                              _printing ? null : () => _printAsPhoto(context),
                          icon: _printing
                              ? const SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.photo_camera_rounded,
                                  size: 16),
                          label: Text('Print Photo',
                              style: GoogleFonts.poppins(
                                  fontSize: 13, fontWeight: FontWeight.w600)),
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _printing ? null : () => _printText(context),
                      icon: const Icon(Icons.text_fields_rounded, size: 16),
                      label: Text('Print Text (English only)',
                          style: GoogleFonts.poppins(fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textMedium,
                          side: BorderSide(color: AppColors.border)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _printAsPhoto(BuildContext context) async {
    final bt = BtPrinterService.to;
    final messenger = ScaffoldMessenger.of(context);
    if (kIsWeb || !bt.isConnected.value) {
      messenger.showSnackBar(SnackBar(
        content: Text('Connect a Bluetooth printer first',
            style: GoogleFonts.poppins()),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _printing = true);
    try {
      final boundary = _repaintKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) return;

      // Read paper size to know target pixel width
      final prefs = await SharedPreferences.getInstance();
      final paperMm = prefs.getInt('pos_paper_width') ?? 80;
      // ESC/POS printable widths at 203 DPI: 58mm→384px, 80mm→576px
      final targetPx = paperMm == 58 ? 384 : 576;

      // Capture at 3× so we always downscale to printer width (sharp text)
      final src = await boundary.toImage(pixelRatio: 3.0);
      final bytes = await _scaleToWidth(src, targetPx);
      await bt.printImage(bytes);
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('Print failed: $e', style: GoogleFonts.poppins()),
        backgroundColor: AppColors.secondary,
        behavior: SnackBarBehavior.floating,
      ));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<Uint8List> _scaleToWidth(ui.Image src, int targetPx) async {
    final scale = targetPx / src.width;
    final targetH = (src.height * scale).round();
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
      recorder,
      ui.Rect.fromLTWH(0, 0, targetPx.toDouble(), targetH.toDouble()),
    );
    canvas.drawImageRect(
      src,
      ui.Rect.fromLTWH(0, 0, src.width.toDouble(), src.height.toDouble()),
      ui.Rect.fromLTWH(0, 0, targetPx.toDouble(), targetH.toDouble()),
      ui.Paint()..filterQuality = ui.FilterQuality.high,
    );
    final pic = recorder.endRecording();
    final img = await pic.toImage(targetPx, targetH);
    final bd = await img.toByteData(format: ui.ImageByteFormat.png);
    return bd!.buffer.asUint8List();
  }

  Future<void> _printText(BuildContext context) async {
    final bt = BtPrinterService.to;
    if (!kIsWeb && bt.isConnected.value) {
      final prefs = await SharedPreferences.getInstance();
      final paperWidth = prefs.getInt('pos_paper_width') ?? 80;
      final ok = await bt.printReceipt(widget.sale, paperWidth: paperWidth);
      if (ok) return;
    }
    await _printPdf(widget.sale);
  }

  Future<void> _printPdf(PosSaleModel sale) async {
    await Printing.layoutPdf(
      onLayout: (_) => _buildReceiptPdf(sale),
      name: 'Receipt-${sale.id}',
    );
  }

  Future<Uint8List> _buildReceiptPdf(PosSaleModel sale) async {
    final doc = pw.Document();
    doc.addPage(
      pw.Page(
        pageFormat: const PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
            marginAll: 4 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Column(children: [
                pw.Text('TSfootwear',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
                pw.Text('54 St, 115D Corner',
                    style: const pw.TextStyle(fontSize: 9)),
              ]),
            ),
            pw.Divider(),
            pw.Text('Receipt: ${sale.id}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text(
                'Date: ${DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt)}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Text('Cashier: ${sale.cashierName}',
                style: const pw.TextStyle(fontSize: 9)),
            pw.Divider(),
            // Items
            ...sale.items.map((item) {
              final size = (item['size'] ?? '').toString();
              final detail = size.isNotEmpty ? 'Sz:$size' : '';
              return pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('${item['name']} x${item['qty']}',
                            style: pw.TextStyle(
                                fontSize: 10, fontWeight: pw.FontWeight.bold)),
                        if (detail.isNotEmpty)
                          pw.Text(detail,
                              style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ),
                  pw.Text(fmtPrice((item['lineTotal'] as num?)?.toDouble()),
                      style: const pw.TextStyle(fontSize: 10)),
                ],
              );
            }),
            pw.Divider(),
            if (sale.discount > 0)
              _pdfRow('Discount', '-${fmtPrice(sale.discount)}'),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('TOTAL',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(fmtPrice(sale.total),
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 4),
            if (sale.paymentMethod == 'cash') ...[
              _pdfRow('Cash', fmtPrice(sale.cashGiven)),
              _pdfRow('Change', fmtPrice(sale.change)),
            ] else
              _pdfRow('Payment', 'Card'),
            pw.Divider(),
            pw.Center(
              child: pw.Text('Thank you! / Kyay Zu Tin Bar Tae',
                  style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      ),
    );
    return Uint8List.fromList(await doc.save());
  }

  pw.Widget _pdfRow(String label, String value) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 10)),
          pw.Text(value, style: const pw.TextStyle(fontSize: 10)),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Body widget (shown in dialog and used for print layout)
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptBody extends StatelessWidget {
  final PosSaleModel sale;
  final ReceiptSettings settings;
  const _ReceiptBody({
    required this.sale,
    this.settings = const ReceiptSettings(),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Store info
        Center(
          child: Column(
            children: [
              Text(settings.storeName,
                  style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              if (settings.storeAddress.isNotEmpty)
                Text(settings.storeAddress,
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textMedium)),
            ],
          ),
        ),
        const _ReceiptDash(),
        if (settings.showId) _ReceiptRow('Receipt', sale.id, small: true),
        if (settings.showDate)
          _ReceiptRow(
              'Date', DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt),
              small: true),
        if (settings.showCashier)
          _ReceiptRow('Cashier', sale.cashierName, small: true),
        const _ReceiptDash(),
        // Items
        ...sale.items.map((item) {
          final size = (item['size'] ?? '').toString();
          final sub = size.isNotEmpty ? 'Size: $size' : '';
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item['name'] ?? '',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary)),
                      if (sub.isNotEmpty)
                        Text(sub,
                            style: GoogleFonts.poppins(
                                fontSize: 10, color: AppColors.textMedium)),
                    ],
                  ),
                ),
                Text('×${item['qty']}',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.textMedium)),
                const SizedBox(width: 12),
                Text(fmtPrice((item['lineTotal'] as num?)?.toDouble()),
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary)),
              ],
            ),
          );
        }),
        const _ReceiptDash(),
        if (sale.discount > 0)
          _ReceiptRow('Discount', '-${fmtPrice(sale.discount)}'),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('စုစုပေါင်း',
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary)),
            Text(fmtPrice(sale.total),
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppColors.textPrimary)),
          ],
        ),
        const SizedBox(height: 6),
        if (sale.paymentMethod == 'cash') ...[
          _ReceiptRow('ပေးငွေ', fmtPrice(sale.cashGiven)),
          _ReceiptRow('ပြန်အမ်းငွေ', fmtPrice(sale.change)),
        ] else
          _ReceiptRow('ငွေပေးချေမှု', 'Card'),
        const _ReceiptDash(),
        if (settings.footer.isNotEmpty)
          Center(
            child: Text(settings.footer,
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textMedium)),
          ),
      ],
    );
  }
}

class _ReceiptDash extends StatelessWidget {
  const _ReceiptDash();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          '- ' * 22,
          style: TextStyle(
              fontSize: 11,
              color: AppColors.textMedium,
              letterSpacing: 0),
        ),
      );
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool small;
  const _ReceiptRow(this.label, this.value, {this.small = false});

  @override
  Widget build(BuildContext context) {
    final size = small ? 11.0 : 13.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: size, color: AppColors.textMedium)),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: size,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helper widgets
// ─────────────────────────────────────────────────────────────────────────────

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  const _TotalRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textMedium)),
            Text(value,
                style: GoogleFonts.poppins(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary)),
          ],
        ),
      );
}

class _PaymentBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _PaymentBtn(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 16,
                  color: selected ? Colors.white : AppColors.textMedium),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? Colors.white : AppColors.textMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscTypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _DiscTypeBtn(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: selected ? AppColors.primary : AppColors.border),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textMedium),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales History Tab
// ─────────────────────────────────────────────────────────────────────────────

class _SalesHistoryTab extends StatefulWidget {
  final PosController pos;
  const _SalesHistoryTab({required this.pos});

  @override
  State<_SalesHistoryTab> createState() => _SalesHistoryTabState();
}

class _SalesHistoryTabState extends State<_SalesHistoryTab> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<PosSaleModel> _filtered(List<PosSaleModel> all) {
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((sale) {
      if (sale.id.toLowerCase().contains(q)) return true;
      if (sale.cashierName.toLowerCase().contains(q)) return true;
      if (sale.paymentMethod.toLowerCase().contains(q)) return true;
      if (DateFormat('dd MMM yyyy')
          .format(sale.createdAt)
          .toLowerCase()
          .contains(q)) return true;
      return sale.items.any(
          (item) => (item['name'] as String? ?? '').toLowerCase().contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: AppColors.card,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style:
                GoogleFonts.poppins(fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search by ID, cashier, product...',
              prefixIcon: const Icon(Icons.search_rounded, size: 20),
              suffixIcon: _query.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.bg,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(
          child: Obx(() {
            if (widget.pos.isLoadingHistory.value) {
              return const Center(child: CircularProgressIndicator());
            }
            if (widget.pos.salesHistory.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined,
                        size: 56, color: AppColors.textLight),
                    const SizedBox(height: 12),
                    Text('No sales yet',
                        style: GoogleFonts.poppins(
                            fontSize: 16, color: AppColors.textMedium)),
                  ],
                ),
              );
            }
            final list = _filtered(widget.pos.salesHistory);
            if (list.isEmpty) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search_off_rounded,
                        size: 56, color: AppColors.textLight),
                    const SizedBox(height: 12),
                    Text('No results for "$_query"',
                        style: GoogleFonts.poppins(
                            fontSize: 14, color: AppColors.textMedium)),
                  ],
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final sale = list[i];
                final isRefund = sale.isRefundRecord;
                final isRefunded = sale.isRefunded;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  color: AppColors.card,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        // Icon
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isRefund
                                ? AppColors.secondary.withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isRefund
                                ? Icons.undo_rounded
                                : Icons.receipt_rounded,
                            color: isRefund
                                ? AppColors.secondary
                                : AppColors.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Info
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: Text(sale.id,
                                      style: GoogleFonts.poppins(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                if (isRefunded)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondary
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('REFUNDED',
                                        style: GoogleFonts.poppins(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.secondary)),
                                  ),
                              ]),
                              Text(
                                '${sale.items.length} items • ${sale.paymentMethod.toUpperCase()} • ${sale.cashierName}',
                                style: GoogleFonts.poppins(
                                    fontSize: 11, color: AppColors.textMedium),
                              ),
                              Text(
                                DateFormat('dd MMM yyyy, HH:mm')
                                    .format(sale.createdAt),
                                style: GoogleFonts.poppins(
                                    fontSize: 10, color: AppColors.textLight),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Amount + actions
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              fmtPrice(sale.total),
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isRefund
                                      ? AppColors.secondary
                                      : AppColors.primary),
                            ),
                            const SizedBox(height: 6),
                            Row(children: [
                              // Receipt
                              _HistoryActionBtn(
                                icon: Icons.print_rounded,
                                color: AppColors.primary,
                                tooltip: 'View receipt',
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => _ReceiptDialog(sale: sale),
                                ),
                              ),
                              // Refund (only for completed sales, not refunds)
                              if (!isRefund && !isRefunded) ...[
                                const SizedBox(width: 6),
                                _HistoryActionBtn(
                                  icon: Icons.undo_rounded,
                                  color: AppColors.secondary,
                                  tooltip: 'Refund',
                                  onTap: () => showDialog(
                                    context: context,
                                    builder: (_) => _RefundDialog(
                                      sale: sale,
                                      pos: widget.pos,
                                    ),
                                  ),
                                ),
                              ],
                            ]),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          }),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cash Numpad
// ─────────────────────────────────────────────────────────────────────────────

class _CashNumpad extends StatefulWidget {
  final double value;
  final double total;
  final ValueChanged<double> onChanged;

  const _CashNumpad({
    required this.value,
    required this.total,
    required this.onChanged,
  });

  @override
  State<_CashNumpad> createState() => _CashNumpadState();
}

class _CashNumpadState extends State<_CashNumpad> {
  String _input = '';

  @override
  void initState() {
    super.initState();
    _input = widget.value > 0 ? widget.value.toStringAsFixed(0) : '';
  }

  void _press(String key) {
    String next = _input;
    if (key == '⌫') {
      if (next.isNotEmpty) next = next.substring(0, next.length - 1);
    } else if (key == 'C') {
      next = '';
    } else {
      if (next.length >= 10) return;
      next += key;
    }
    setState(() => _input = next);
    widget.onChanged(double.tryParse(next) ?? 0);
  }

  void _quickSet(double amount) {
    final s = amount.toStringAsFixed(0);
    setState(() => _input = s);
    widget.onChanged(amount);
  }

  @override
  Widget build(BuildContext context) {
    final entered = double.tryParse(_input) ?? 0;
    final change = entered - widget.total;

    return Column(
      children: [
        // Display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: entered >= widget.total && entered > 0
                  ? Colors.green
                  : AppColors.border,
              width: entered >= widget.total && entered > 0 ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.money_rounded, size: 18, color: Colors.green),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _input.isEmpty ? 'Cash given (Ks)' : 'Ks $_input',
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight:
                        _input.isEmpty ? FontWeight.w400 : FontWeight.w700,
                    color: _input.isEmpty
                        ? AppColors.textLight
                        : AppColors.textPrimary,
                  ),
                ),
              ),
              if (_input.isNotEmpty)
                GestureDetector(
                  onTap: () => _press('C'),
                  child:
                      Icon(Icons.close, size: 16, color: AppColors.textLight),
                ),
            ],
          ),
        ),

        // Quick amount buttons
        const SizedBox(height: 8),
        Row(
          children: [
            _QuickBtn(label: 'Exact', onTap: () => _quickSet(widget.total)),
            const SizedBox(width: 6),
            _QuickBtn(label: '5K', onTap: () => _quickSet(5000)),
            const SizedBox(width: 6),
            _QuickBtn(label: '10K', onTap: () => _quickSet(10000)),
            const SizedBox(width: 6),
            _QuickBtn(label: '20K', onTap: () => _quickSet(20000)),
            const SizedBox(width: 6),
            _QuickBtn(label: '50K', onTap: () => _quickSet(50000)),
          ],
        ),

        // Numpad grid
        const SizedBox(height: 2),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 6,
          crossAxisSpacing: 6,
          childAspectRatio: 2.2,
          children: [
            '7',
            '8',
            '9',
            '4',
            '5',
            '6',
            '1',
            '2',
            '3',
            'C',
            '0',
            '⌫',
          ].map((k) => _NumKey(label: k, onTap: () => _press(k))).toList(),
        ),

        // Change display
        if (entered >= widget.total && widget.total > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Change',
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.green.shade700)),
                Text(
                  fmtPrice(change),
                  style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ] else if (entered > 0 && entered < widget.total) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Still needed',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: AppColors.secondary)),
                Text(
                  fmtPrice(widget.total - entered),
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.secondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _NumKey extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _NumKey({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isAction = label == '⌫' || label == 'C';
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isAction
              ? AppColors.secondary.withValues(alpha: 0.10)
              : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        alignment: Alignment.center,
        child: label == '⌫'
            ? Icon(Icons.backspace_outlined,
                size: 18, color: AppColors.secondary)
            : Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: label == 'C' ? 13 : 16,
                  fontWeight: FontWeight.w700,
                  color: label == 'C'
                      ? AppColors.secondary
                      : AppColors.textPrimary,
                ),
              ),
      ),
    );
  }
}

class _QuickBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _QuickBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History Action Button
// ─────────────────────────────────────────────────────────────────────────────

class _HistoryActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _HistoryActionBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Refund Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _RefundDialog extends StatefulWidget {
  final PosSaleModel sale;
  final PosController pos;
  const _RefundDialog({required this.sale, required this.pos});

  @override
  State<_RefundDialog> createState() => _RefundDialogState();
}

class _RefundDialogState extends State<_RefundDialog> {
  // item index -> refund qty
  late final List<int> _refundQtys;

  @override
  void initState() {
    super.initState();
    _refundQtys =
        widget.sale.items.map((i) => (i['qty'] as num?)?.toInt() ?? 0).toList();
  }

  double get _refundTotal {
    double total = 0;
    for (int i = 0; i < widget.sale.items.length; i++) {
      final price = (widget.sale.items[i]['price'] as num?)?.toDouble() ?? 0;
      total += price * _refundQtys[i];
    }
    return total;
  }

  bool get _hasSelection => _refundQtys.any((q) => q > 0);

  Future<void> _confirm(BuildContext context) async {
    final refundItems = <Map<String, dynamic>>[];
    for (int i = 0; i < widget.sale.items.length; i++) {
      if (_refundQtys[i] > 0) {
        refundItems.add({
          ...widget.sale.items[i],
          'qty': _refundQtys[i],
          'lineTotal': (_refundQtys[i]) *
              ((widget.sale.items[i]['price'] as num?)?.toDouble() ?? 0),
        });
      }
    }
    final id = await widget.pos.processRefund(widget.sale, refundItems);
    if (!context.mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
        id != null ? 'Refund $id processed' : 'Refund failed',
        style: GoogleFonts.poppins(),
      ),
      backgroundColor: id != null ? Colors.green : AppColors.secondary,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Refund',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
          Text(widget.sale.id,
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textMedium)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select items and quantities to refund',
                style: GoogleFonts.poppins(
                    fontSize: 12, color: AppColors.textMedium)),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: List.generate(widget.sale.items.length, (i) {
                    final item = widget.sale.items[i];
                    final maxQty = (item['qty'] as num?)?.toInt() ?? 1;
                    final name = item['name'] ?? '';
                    final size = (item['size'] ?? '').toString();
                    final color = (item['color'] ?? '').toString();
                    final price = (item['price'] as num?)?.toDouble() ?? 0;
                    final detail = [
                      if (size.isNotEmpty) 'Size: $size',
                      if (color.isNotEmpty) color,
                    ].join(' • ');

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _refundQtys[i] > 0
                            ? AppColors.secondary.withValues(alpha: 0.06)
                            : AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _refundQtys[i] > 0
                              ? AppColors.secondary.withValues(alpha: 0.4)
                              : AppColors.border,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name,
                                    style: GoogleFonts.poppins(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary)),
                                if (detail.isNotEmpty)
                                  Text(detail,
                                      style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color: AppColors.textMedium)),
                                Text(fmtPrice(price),
                                    style: GoogleFonts.poppins(
                                        fontSize: 11,
                                        color: AppColors.primary)),
                              ],
                            ),
                          ),
                          // Qty stepper
                          Row(children: [
                            _SmallQtyBtn(
                              icon: Icons.remove,
                              onTap: _refundQtys[i] > 0
                                  ? () => setState(() => _refundQtys[i]--)
                                  : null,
                            ),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 10),
                              child: Text('${_refundQtys[i]}/$maxQty',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary)),
                            ),
                            _SmallQtyBtn(
                              icon: Icons.add,
                              onTap: _refundQtys[i] < maxQty
                                  ? () => setState(() => _refundQtys[i]++)
                                  : null,
                            ),
                          ]),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ),
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Refund Total',
                    style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                Text(fmtPrice(_refundTotal),
                    style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.secondary)),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: GoogleFonts.poppins(color: AppColors.textMedium)),
        ),
        Obx(() => ElevatedButton.icon(
              onPressed: (_hasSelection && !widget.pos.isProcessing.value)
                  ? () => _confirm(context)
                  : null,
              icon: widget.pos.isProcessing.value
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.undo_rounded, size: 16),
              label: Text('Confirm Refund',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.secondary,
                foregroundColor: Colors.white,
                disabledBackgroundColor:
                    AppColors.textLight.withValues(alpha: 0.3),
              ),
            )),
      ],
    );
  }
}

class _SmallQtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _SmallQtyBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.primary.withValues(alpha: 0.1)
              : AppColors.border.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 14,
            color: onTap != null ? AppColors.primary : AppColors.textLight),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POS Dashboard Tab
// ─────────────────────────────────────────────────────────────────────────────

class _PosDashboardTab extends StatefulWidget {
  final PosController pos;
  const _PosDashboardTab({required this.pos});

  @override
  State<_PosDashboardTab> createState() => _PosDashboardTabState();
}

class _PosDashboardTabState extends State<_PosDashboardTab> {
  late DateTime _from;
  late DateTime _to;
  Map<DateTime, double> _chartData = {};
  bool _chartLoading = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 6));
    _fetchChart();
  }

  Future<void> _fetchChart() async {
    setState(() => _chartLoading = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pos_sales')
          .get();

      final Map<DateTime, double> map = {};
      final days = _to.difference(_from).inDays;
      for (int i = 0; i <= days; i++) {
        map[_from.add(Duration(days: i))] = 0;
      }

      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['type'] as String? ?? 'sale') == 'refund') continue;
        final raw = d['createdAt'];
        DateTime? dt;
        if (raw is String) dt = DateTime.tryParse(raw);
        if (dt == null) continue;
        final day = DateTime(dt.year, dt.month, dt.day);
        if (map.containsKey(day)) {
          map[day] = (map[day] ?? 0) + ((d['total'] as num?)?.toDouble() ?? 0);
        }
      }

      if (mounted) setState(() { _chartData = map; _chartLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _from, end: _to),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _from = DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      _fetchChart();
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _DashCardData(
        icon: Icons.inventory_2_rounded,
        title: 'Low Stock',
        subtitle: 'Items running low',
        colorA: const Color(0xFFFF8C00),
        colorB: const Color(0xFFE65100),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _LowStockPage())),
      ),
      _DashCardData(
        icon: Icons.devices_rounded,
        title: 'Hardware',
        subtitle: 'Scanner & printer',
        colorA: const Color(0xFF1976D2),
        colorB: const Color(0xFF0D47A1),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _HardwarePage())),
      ),
      _DashCardData(
        icon: Icons.receipt_long_rounded,
        title: 'Receipt',
        subtitle: 'Customize voucher',
        colorA: const Color(0xFF2E7D32),
        colorB: const Color(0xFF1B5E20),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _ReceiptManagementPage())),
      ),
      _DashCardData(
        icon: Icons.bar_chart_rounded,
        title: 'Quick Stats',
        subtitle: "Today's summary",
        colorA: const Color(0xFF7B1FA2),
        colorB: const Color(0xFF4A148C),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => _QuickStatsPage(pos: widget.pos))),
      ),
      _DashCardData(
        icon: Icons.print_rounded,
        title: 'Test Print',
        subtitle: 'Verify printer output',
        colorA: const Color(0xFFC62828),
        colorB: const Color(0xFFB71C1C),
        onTap: () {
          final bt = BtPrinterService.to;
          if (!bt.isConnected.value) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('No printer connected. Go to Hardware → Connect.',
                  style: GoogleFonts.poppins(fontSize: 12)),
              backgroundColor: AppColors.secondary,
              behavior: SnackBarBehavior.floating,
            ));
            return;
          }
          bt.testPrint().then((ok) {
            if (Get.overlayContext != null) {
              Get.snackbar(
                ok ? 'Test print sent' : 'Print failed',
                ok ? 'Check your printer for the test page.'
                   : 'Printer may have disconnected.',
                snackPosition: SnackPosition.BOTTOM,
                backgroundColor:
                    ok ? const Color(0xFF2E7D32) : AppColors.secondary,
                colorText: Colors.white,
              );
            }
          });
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = constraints.maxWidth >= 600;
        final cols = isTablet ? 5 : 2;
        final ratio = isTablet ? 0.85 : 0.92;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('POS Dashboard',
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('Tap a section to manage',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: AppColors.textMedium)),
              const SizedBox(height: 20),
              GridView.count(
                crossAxisCount: cols,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: ratio,
                children: items.map((d) => _DashCard(data: d)).toList(),
              ),
              const SizedBox(height: 24),
              _SalesTrendCard(
                data: _chartData,
                loading: _chartLoading,
                from: _from,
                to: _to,
                onPickRange: _pickRange,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DashCardData {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color colorA;
  final Color colorB;
  final VoidCallback onTap;
  const _DashCardData({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorA,
    required this.colorB,
    required this.onTap,
  });
}

class _DashCard extends StatelessWidget {
  final _DashCardData data;
  const _DashCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Material(
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      elevation: 3,
      shadowColor: data.colorA.withValues(alpha: 0.4),
      child: InkWell(
        onTap: data.onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [data.colorA, data.colorB],
            ),
          ),
          child: Stack(
            children: [
              // Decorative background icon
              Positioned(
                right: -14,
                bottom: -14,
                child: Icon(data.icon,
                    size: 100, color: Colors.white.withValues(alpha: 0.1)),
              ),
              // Foreground content
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(data.icon, color: Colors.white, size: 24),
                    ),
                    const Spacer(),
                    Text(data.title,
                        style: GoogleFonts.poppins(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Expanded(
                          child: Text(data.subtitle,
                              style: GoogleFonts.poppins(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.75))),
                        ),
                        Icon(Icons.arrow_forward_ios_rounded,
                            size: 12,
                            color: Colors.white.withValues(alpha: 0.6)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sales Trend Chart Card
// ─────────────────────────────────────────────────────────────────────────────

class _SalesTrendCard extends StatelessWidget {
  final Map<DateTime, double> data;
  final bool loading;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickRange;

  const _SalesTrendCard({
    required this.data,
    required this.loading,
    required this.from,
    required this.to,
    required this.onPickRange,
  });

  String _fmtK(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final sortedDays = data.keys.toList()..sort();
    final maxVal = data.values.fold(0.0, max);
    final yMax = maxVal <= 0 ? 1000.0 : maxVal * 1.25;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Daily Sales',
                      style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(
                    '${DateFormat('dd MMM').format(from)} – ${DateFormat('dd MMM yyyy').format(to)}',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textMedium),
                  ),
                ],
              ),
            ),
            // Date range picker button
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_rounded, size: 15),
              label: Text('Range',
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ]),
          const SizedBox(height: 16),

          // ── Chart ────────────────────────────────────────────────────────
          SizedBox(
            height: 200,
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : sortedDays.isEmpty
                    ? Center(
                        child: Text('No sales in this range',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: AppColors.textMedium)))
                    : BarChart(
                        BarChartData(
                          maxY: yMax,
                          minY: 0,
                          barGroups: sortedDays.asMap().entries.map((e) {
                            final revenue = data[e.value] ?? 0;
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: revenue,
                                  width: (260 / sortedDays.length)
                                      .clamp(6.0, 22.0),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(5)),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary
                                          .withValues(alpha: 0.55),
                                    ],
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                  ),
                                ),
                              ],
                            );
                          }).toList(),
                          titlesData: FlTitlesData(
                            topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false)),
                            leftTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 46,
                                interval: yMax / 4,
                                getTitlesWidget: (v, _) {
                                  if (v == 0) return const SizedBox.shrink();
                                  return Text(_fmtK(v),
                                      style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          color: AppColors.textMedium));
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 24,
                                getTitlesWidget: (v, _) {
                                  final i = v.toInt();
                                  if (i >= sortedDays.length) {
                                    return const SizedBox.shrink();
                                  }
                                  final step = sortedDays.length <= 7
                                      ? 1
                                      : sortedDays.length <= 14
                                          ? 2
                                          : 7;
                                  if (i % step != 0) {
                                    return const SizedBox.shrink();
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      DateFormat('dd/MM')
                                          .format(sortedDays[i]),
                                      style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          color: AppColors.textMedium),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                          gridData: FlGridData(
                            drawVerticalLine: false,
                            horizontalInterval: yMax / 4,
                            getDrawingHorizontalLine: (_) => FlLine(
                              color: AppColors.border.withValues(alpha: 0.5),
                              strokeWidth: 0.5,
                            ),
                          ),
                          borderData: FlBorderData(show: false),
                          barTouchData: BarTouchData(
                            touchTooltipData: BarTouchTooltipData(
                              getTooltipColor: (_) => AppColors.textPrimary,
                              tooltipRoundedRadius: 8,
                              getTooltipItem: (group, _, rod, __) {
                                final day = sortedDays[group.x];
                                return BarTooltipItem(
                                  '${DateFormat('dd MMM').format(day)}\n${fmtPrice(rod.toY)}',
                                  GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
          ),

          // ── Summary row ──────────────────────────────────────────────────
          if (!loading && data.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 10),
            Row(children: [
              _ChartStat(
                label: 'Total',
                value: fmtPrice(
                    data.values.fold<double>(0.0, (a, b) => a + b)),
                icon: Icons.attach_money_rounded,
                color: AppColors.primary,
              ),
              const SizedBox(width: 16),
              _ChartStat(
                label: 'Days',
                value: data.values
                    .where((v) => v > 0)
                    .length
                    .toString(),
                icon: Icons.calendar_today_rounded,
                color: const Color(0xFF2E7D32),
              ),
              const SizedBox(width: 16),
              _ChartStat(
                label: 'Best Day',
                value: fmtPrice(maxVal),
                icon: Icons.trending_up_rounded,
                color: const Color(0xFF7B1FA2),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

class _ChartStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _ChartStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 5),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              Text(label,
                  style: GoogleFonts.poppins(
                      fontSize: 10, color: AppColors.textMedium)),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Low Stock Page
// ─────────────────────────────────────────────────────────────────────────────

class _LowStockPage extends StatefulWidget {
  const _LowStockPage();

  @override
  State<_LowStockPage> createState() => _LowStockPageState();
}

class _LowStockPageState extends State<_LowStockPage> {
  static const _kThreshold = 'low_stock_threshold';
  int _threshold = 10;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadThreshold().then((_) => _fetch());
  }

  Future<void> _loadThreshold() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) setState(() => _threshold = p.getInt(_kThreshold) ?? 10);
  }

  Future<void> _saveThreshold(int v) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kThreshold, v);
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('products').get();
      if (mounted) {
        final all = snap.docs.map((d) => {...d.data(), 'id': d.id}).toList();
        final filtered = all.where((item) {
          final active = item['isActive'] as bool? ?? true;
          final stock = (item['stock'] as num?)?.toInt() ?? 0;
          return active && stock <= _threshold;
        }).toList()
          ..sort((a, b) => ((a['stock'] as num?)?.toInt() ?? 0)
              .compareTo((b['stock'] as num?)?.toInt() ?? 0));
        setState(() {
          _items = filtered;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Low Stock',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body: Column(
        children: [
          // Threshold picker
          Container(
            color: AppColors.card,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Row(
              children: [
                Text('Alert threshold: ',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textMedium)),
                Expanded(
                  child: Slider(
                    value: _threshold.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    activeColor: const Color(0xFFF39C12),
                    label: _threshold.toString(),
                    onChanged: (v) => setState(() => _threshold = v.toInt()),
                    onChangeEnd: (v) {
                      _saveThreshold(v.toInt());
                      _fetch();
                    },
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF39C12).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('≤ $_threshold',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFF39C12))),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.check_circle_outline_rounded,
                                size: 56, color: const Color(0xFF27AE60)),
                            const SizedBox(height: 12),
                            Text('All products are well-stocked',
                                style: GoogleFonts.poppins(
                                    fontSize: 15, color: AppColors.textMedium)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length,
                        itemBuilder: (_, i) {
                          final item = _items[i];
                          final stock = (item['stock'] as num?)?.toInt() ?? 0;
                          final isOut = stock == 0;
                          final color = isOut
                              ? AppColors.secondary
                              : const Color(0xFFF39C12);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: AppColors.card,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            child: ListTile(
                              leading: _LowStockThumb(
                                item: item,
                                color: color,
                                isOut: isOut,
                              ),
                              title: Text(item['name'] ?? '',
                                  style: GoogleFonts.poppins(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              subtitle: Text(
                                  item['brand'] != null &&
                                          (item['brand'] as String).isNotEmpty
                                      ? item['brand'] as String
                                      : 'No brand',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: AppColors.textMedium)),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  isOut ? 'OUT' : 'Qty: $stock',
                                  style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: color),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _LowStockThumb extends StatelessWidget {
  final Map<String, dynamic> item;
  final Color color;
  final bool isOut;
  const _LowStockThumb({
    required this.item,
    required this.color,
    required this.isOut,
  });

  @override
  Widget build(BuildContext context) {
    final raw = (item['thumbnail'] as String? ?? '').isNotEmpty
        ? item['thumbnail'] as String
        : ((item['images'] as List?)?.isNotEmpty == true
            ? (item['images'] as List).first as String
            : '');
    final url = AppConstants.fixImageUrl(raw);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 48,
        height: 48,
        child: url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: color.withValues(alpha: 0.12),
                  child: Icon(Icons.image_outlined, color: color, size: 20),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: color.withValues(alpha: 0.12),
                  child: Icon(
                    isOut
                        ? Icons.remove_shopping_cart_rounded
                        : Icons.warning_amber_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
              )
            : Container(
                color: color.withValues(alpha: 0.12),
                child: Icon(
                  isOut
                      ? Icons.remove_shopping_cart_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 20,
                ),
              ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hardware Page
// ─────────────────────────────────────────────────────────────────────────────

class _HardwarePage extends StatefulWidget {
  const _HardwarePage();

  @override
  State<_HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<_HardwarePage> {
  static const _kPaperWidth = 'pos_paper_width';
  int _paperWidth = 80;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _paperWidth = p.getInt(_kPaperWidth) ?? 80);
    });
  }

  Future<void> _setPaper(int w) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_kPaperWidth, w);
    if (mounted) setState(() => _paperWidth = w);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Hardware',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Receipt Paper Size ──────────────────────────────────────────
          _SectionCard(
            icon: Icons.print_rounded,
            iconColor: const Color(0xFF2980B9),
            title: 'Receipt Paper Size',
            child: Column(
              children: [58, 80].map((w) {
                final selected = _paperWidth == w;
                return RadioListTile<int>(
                  value: w,
                  groupValue: _paperWidth,
                  onChanged: (v) => _setPaper(v!),
                  fillColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected)
                          ? AppColors.primary
                          : null),
                  title: Text('${w}mm',
                      style: GoogleFonts.poppins(
                          fontSize: 14,
                          fontWeight:
                              selected ? FontWeight.w600 : FontWeight.w400,
                          color: AppColors.textPrimary)),
                  subtitle: Text(
                    w == 58 ? '32 chars per line' : '48 chars per line',
                    style: GoogleFonts.poppins(
                        fontSize: 11, color: AppColors.textMedium),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 14),

          // ── Bluetooth Printer ───────────────────────────────────────────
          Obx(() {
            final bt = BtPrinterService.to;
            final connected = bt.isConnected.value;
            final deviceName = bt.connectedDevice.value?.name ?? '';
            return _SectionCard(
              icon: Icons.bluetooth_rounded,
              iconColor: const Color(0xFF2980B9),
              title: 'Bluetooth Printer',
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  connected ? 'Connected: $deviceName' : 'Not connected',
                  style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: connected
                          ? const Color(0xFF27AE60)
                          : AppColors.textMedium),
                ),
                trailing: TextButton(
                  onPressed: () => _showBtDialog(context),
                  child: Text(connected ? 'Manage' : 'Connect',
                      style: GoogleFonts.poppins(color: AppColors.primary)),
                ),
              ),
            );
          }),
          const SizedBox(height: 14),

          // ── Barcode Scanner ─────────────────────────────────────────────
          _SectionCard(
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFF27AE60),
            title: 'Barcode Scanner (BT HID)',
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StepRow(
                      step: '1',
                      text:
                          'Install "Barcode to PC" on the scanner phone (Android/iOS)'),
                  _StepRow(
                      step: '2',
                      text:
                          'Pair the scanner phone to this device via Bluetooth settings'),
                  _StepRow(
                      step: '3',
                      text: 'In the app, connect as Bluetooth Keyboard (HID)'),
                  _StepRow(
                      step: '4',
                      text:
                          'Open POS tab — the scan field auto-focuses, ready to receive barcodes'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'The scanned barcode is typed + Enter, and the product is added to cart automatically.',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: AppColors.textMedium),
                        ),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),

          // ── Network Barcode Scanner ──────────────────────────────────────
          if (!kIsWeb && Get.isRegistered<BarcodeScannerService>())
            Obx(() {
              final svc = BarcodeScannerService.to;
              final running = svc.isRunning.value;
              final clients = svc.connectedClients.value;
              final ip = svc.ipAddress.value;
              final p = svc.port.value;
              final err = svc.startError.value;
              final last = svc.lastBarcode.value;
              return _SectionCard(
                icon: Icons.wifi_rounded,
                iconColor: const Color(0xFF00897B),
                title: 'Network Barcode (WiFi)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status row
                    Row(children: [
                      Container(
                        width: 8, height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: running
                              ? const Color(0xFF27AE60)
                              : AppColors.secondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        running
                            ? '$clients client${clients == 1 ? '' : 's'} connected'
                            : 'Server stopped',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textMedium),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: running ? svc.stop : svc.restart,
                        child: Text(running ? 'Stop' : 'Start',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: running
                                    ? AppColors.secondary
                                    : AppColors.primary)),
                      ),
                    ]),

                    // Error message
                    if (err.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(children: [
                          Icon(Icons.error_outline_rounded,
                              size: 14, color: AppColors.secondary),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(err,
                                style: GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: AppColors.secondary)),
                          ),
                        ]),
                      ),
                    ],

                    // IP + Port boxes (large, easy to read)
                    if (running && ip.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          flex: 3,
                          child: _ConnInfoBox(
                              label: 'IP Address', value: ip),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 1,
                          child: _ConnInfoBox(
                              label: 'Port',
                              value: p.toString(),
                              highlight: true),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final conn = '$ip:$p';
                            Clipboard.setData(ClipboardData(text: conn));
                            if (Get.overlayContext != null) {
                              Get.snackbar('Copied', conn,
                                  snackPosition: SnackPosition.BOTTOM,
                                  duration: const Duration(seconds: 2));
                            }
                          },
                          icon: const Icon(Icons.copy_rounded, size: 15),
                          label: Text('Copy $ip:$p',
                              style: GoogleFonts.poppins(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00897B),
                            side: const BorderSide(
                                color: Color(0xFF00897B)),
                          ),
                        ),
                      ),
                    ],

                    if (last.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(children: [
                        Icon(Icons.qr_code_rounded,
                            size: 14, color: AppColors.textLight),
                        const SizedBox(width: 6),
                        Text('Last received: $last',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textMedium)),
                      ]),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  void _showBtDialog(BuildContext context) {
    final bt = BtPrinterService.to;
    if (!kIsWeb) bt.loadPairedDevices();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Bluetooth Printer',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: SizedBox(
          width: 320,
          child: Obx(() {
            final devices = bt.devices;
            final isScanning = bt.isScanning.value;
            if (isScanning) {
              return const SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator()));
            }
            if (devices.isEmpty) {
              return Column(mainAxisSize: MainAxisSize.min, children: [
                Text('No paired devices found.',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textMedium)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: bt.loadPairedDevices,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Scan again'),
                ),
              ]);
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: devices.length,
              itemBuilder: (_, i) {
                final d = devices[i];
                final isThis = bt.connectedDevice.value?.address == d.address &&
                    bt.isConnected.value;
                return ListTile(
                  leading: Icon(
                      isThis
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_rounded,
                      color: isThis
                          ? const Color(0xFF27AE60)
                          : AppColors.textMedium),
                  title: Text(d.name, style: GoogleFonts.poppins(fontSize: 13)),
                  subtitle: Text(d.address,
                      style: GoogleFonts.poppins(
                          fontSize: 11, color: AppColors.textMedium)),
                  trailing: isThis
                      ? TextButton(
                          onPressed: bt.disconnect,
                          child: Text('Disconnect',
                              style: GoogleFonts.poppins(
                                  color: AppColors.secondary)))
                      : Obx(() => bt.isConnecting.value
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : TextButton(
                              onPressed: () => bt.connect(d),
                              child: Text('Connect',
                                  style: GoogleFonts.poppins(
                                      color: AppColors.primary)))),
                );
              },
            );
          }),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'))
        ],
      ),
    );
  }
}

class _ConnInfoBox extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _ConnInfoBox({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: highlight
            ? const Color(0xFF00897B).withValues(alpha: 0.08)
            : AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: highlight
              ? const Color(0xFF00897B).withValues(alpha: 0.5)
              : AppColors.border,
          width: highlight ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: AppColors.textMedium)),
          const SizedBox(height: 2),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: highlight ? 20 : 14,
                  fontWeight: FontWeight.w800,
                  color: highlight
                      ? const Color(0xFF00897B)
                      : AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;
  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textPrimary)),
        ),
      ]),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget child;
  const _SectionCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: GoogleFonts.poppins(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Receipt Management Page
// ─────────────────────────────────────────────────────────────────────────────

class _ReceiptManagementPage extends StatefulWidget {
  const _ReceiptManagementPage();

  @override
  State<_ReceiptManagementPage> createState() => _ReceiptManagementPageState();
}

class _ReceiptManagementPageState extends State<_ReceiptManagementPage> {
  final _nameCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _footerCtrl = TextEditingController();
  bool _showId = true;
  bool _showCashier = true;
  bool _showDate = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _addressCtrl.dispose();
    _footerCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _nameCtrl.text = p.getString(ReceiptSettings.kStoreName) ?? 'TSfootwear';
      _addressCtrl.text =
          p.getString(ReceiptSettings.kStoreAddress) ?? '54 St, 115D Corner';
      _footerCtrl.text = p.getString(ReceiptSettings.kFooter) ?? 'Thank you!';
      _showId = p.getBool(ReceiptSettings.kShowId) ?? true;
      _showCashier = p.getBool(ReceiptSettings.kShowCashier) ?? true;
      _showDate = p.getBool(ReceiptSettings.kShowDate) ?? true;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final p = await SharedPreferences.getInstance();
    await p.setString(ReceiptSettings.kStoreName, _nameCtrl.text.trim());
    await p.setString(ReceiptSettings.kStoreAddress, _addressCtrl.text.trim());
    await p.setString(ReceiptSettings.kFooter, _footerCtrl.text.trim());
    await p.setBool(ReceiptSettings.kShowId, _showId);
    await p.setBool(ReceiptSettings.kShowCashier, _showCashier);
    await p.setBool(ReceiptSettings.kShowDate, _showDate);
    if (mounted) {
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Receipt settings saved', style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Receipt Management',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
              : TextButton(
                  onPressed: _save,
                  child: Text('Save',
                      style: GoogleFonts.poppins(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Store Info ──────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.store_rounded,
            iconColor: const Color(0xFF27AE60),
            title: 'Store Info',
            child: Column(children: [
              _LabeledField(
                label: 'Store Name',
                controller: _nameCtrl,
                hint: 'e.g. TSfootwear',
              ),
              const SizedBox(height: 12),
              _LabeledField(
                label: 'Store Address',
                controller: _addressCtrl,
                hint: 'e.g. 54 St, 115D Corner',
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Footer ──────────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.format_quote_rounded,
            iconColor: const Color(0xFF8E44AD),
            title: 'Footer Message',
            child: _LabeledField(
              label: 'Footer Text',
              controller: _footerCtrl,
              hint: 'e.g. Thank you! Come again.',
            ),
          ),
          const SizedBox(height: 14),

          // ── Show / Hide Fields ──────────────────────────────────────────
          _SectionCard(
            icon: Icons.visibility_rounded,
            iconColor: const Color(0xFF2980B9),
            title: 'Show on Receipt',
            child: Column(children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Receipt ID',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textPrimary)),
                value: _showId,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _showId = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Date & Time',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textPrimary)),
                value: _showDate,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _showDate = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Cashier Name',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textPrimary)),
                value: _showCashier,
                activeThumbColor: AppColors.primary,
                onChanged: (v) => setState(() => _showCashier = v),
              ),
            ]),
          ),
          const SizedBox(height: 14),

          // ── Preview ─────────────────────────────────────────────────────
          _SectionCard(
            icon: Icons.preview_rounded,
            iconColor: const Color(0xFFF39C12),
            title: 'Receipt Preview',
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DefaultTextStyle(
                style: const TextStyle(
                    fontFamily: 'Courier', fontSize: 11, color: Colors.black),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_nameCtrl.text.isEmpty ? 'Store Name' : _nameCtrl.text,
                        style: const TextStyle(
                            fontFamily: 'Courier',
                            fontSize: 14,
                            fontWeight: FontWeight.bold)),
                    if (_addressCtrl.text.isNotEmpty) Text(_addressCtrl.text),
                    const Text('--------------------------------'),
                    if (_showId) const Text('Receipt: POS-XXXXXXXX'),
                    if (_showDate) const Text('Date   : 01/06/2026 10:00'),
                    if (_showCashier) const Text('Cashier: Admin'),
                    const Text('--------------------------------'),
                    const Text('Product A x1          5,000'),
                    const Text('Product B x2         10,000'),
                    const Text('--------------------------------'),
                    const Text('Subtotal             15,000'),
                    const Text('TOTAL                15,000',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const Text('--------------------------------'),
                    Text(_footerCtrl.text.isEmpty
                        ? 'Thank you!'
                        : _footerCtrl.text),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  const _LabeledField({
    required this.label,
    required this.controller,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.poppins(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.textMedium)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style:
              GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.poppins(fontSize: 13, color: AppColors.textLight),
            filled: true,
            fillColor: AppColors.bg,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick Stats Page
// ─────────────────────────────────────────────────────────────────────────────

class _QuickStatsPage extends StatefulWidget {
  final PosController pos;
  const _QuickStatsPage({required this.pos});

  @override
  State<_QuickStatsPage> createState() => _QuickStatsPageState();
}

class _QuickStatsPageState extends State<_QuickStatsPage> {
  @override
  void initState() {
    super.initState();
    widget.pos.fetchSalesHistory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: Text('Quick Stats',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: widget.pos.fetchSalesHistory,
          ),
        ],
      ),
      body: Obx(() {
        if (widget.pos.isLoadingHistory.value) {
          return const Center(child: CircularProgressIndicator());
        }
        final today = DateTime.now();
        final todaySales = widget.pos.salesHistory
            .where((s) =>
                !s.isRefundRecord &&
                s.createdAt.year == today.year &&
                s.createdAt.month == today.month &&
                s.createdAt.day == today.day)
            .toList();
        final todayRevenue =
            todaySales.fold<double>(0, (acc, s) => acc + s.total);
        final todayCash = todaySales
            .where((s) => s.paymentMethod == 'cash')
            .fold<double>(0, (acc, s) => acc + s.total);
        final todayCard = todaySales
            .where((s) => s.paymentMethod == 'card')
            .fold<double>(0, (acc, s) => acc + s.total);
        final avgOrder =
            todaySales.isEmpty ? 0.0 : todayRevenue / todaySales.length;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              DateFormat('EEEE, dd MMMM yyyy').format(today),
              style: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textMedium),
            ),
            const SizedBox(height: 14),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _StatCard(
                  label: "Today's Revenue",
                  value: fmtPrice(todayRevenue),
                  icon: Icons.attach_money_rounded,
                  color: const Color(0xFF27AE60),
                ),
                _StatCard(
                  label: 'Transactions',
                  value: todaySales.length.toString(),
                  icon: Icons.receipt_rounded,
                  color: AppColors.primary,
                ),
                _StatCard(
                  label: 'Cash Sales',
                  value: fmtPrice(todayCash),
                  icon: Icons.payments_rounded,
                  color: const Color(0xFFF39C12),
                ),
                _StatCard(
                  label: 'Card Sales',
                  value: fmtPrice(todayCard),
                  icon: Icons.credit_card_rounded,
                  color: const Color(0xFF2980B9),
                ),
                _StatCard(
                  label: 'Avg. Order',
                  value: fmtPrice(avgOrder),
                  icon: Icons.trending_up_rounded,
                  color: const Color(0xFF8E44AD),
                ),
                _StatCard(
                  label: 'Total Records',
                  value: widget.pos.salesHistory.length.toString(),
                  icon: Icons.history_rounded,
                  color: AppColors.textMedium,
                ),
              ],
            ),
          ],
        );
      }),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const Spacer(),
          Text(value,
              style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 10, color: AppColors.textMedium)),
        ],
      ),
    );
  }
}
