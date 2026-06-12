import 'dart:async';
import 'dart:math' show max;
import 'package:audioplayers/audioplayers.dart';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
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
import '../../features/pos/data/repositories/pos_repository.dart';
import 'admin_dashboard.dart'
    show AdminOrdersPage, AdminChatPage, AdminPaymentsPage;
import 'label_print_screen.dart';

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
                Get.isRegistered<PosRepository>() ? PosRepository.to : null;
            if (svc == null) return const SizedBox.shrink();
            final offline = !svc.isOnlinObs.value;
            final pending = svc.pendingCountObs.value;
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
                    onTap: () => PosRepository.to.syncPending(),
                    child: Text('ယခု ထပ်တူပြုရန်',
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

  // ── Notification counts ──────────────────────────────────────────────────
  int _pendingOrders = 0;
  int _unreadMessages = 0;
  int _pendingPayments = 0;
  StreamSubscription<QuerySnapshot>? _ordersSub;
  StreamSubscription<QuerySnapshot>? _paymentsSub;
  StreamSubscription<QuerySnapshot>? _chatSub;
  // Watches Firebase Auth so we set up the chat sub as soon as the session
  // is confirmed (currentUser can be null briefly while Auth restores state).
  StreamSubscription<User?>? _authSub;

  @override
  void initState() {
    super.initState();
    _subscribeNotifications();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _ordersSub?.cancel();
    _paymentsSub?.cancel();
    _chatSub?.cancel();
    super.dispose();
  }

  void _subscribeNotifications() {
    final db = FirebaseFirestore.instance;

    _ordersSub = db
        .collection('orders')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((s) {
      if (mounted) setState(() => _pendingOrders = s.docs.length);
    });

    _paymentsSub = db
        .collection('payments')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((s) {
      if (mounted) setState(() => _pendingPayments = s.docs.length);
    });

    // authStateChanges fires immediately with the current user (even if
    // currentUser was null at initState time), then again on sign-in/out.
    _authSub = FirebaseAuth.instance.authStateChanges().listen((fbUser) {
      _chatSub?.cancel();
      _chatSub = null;
      if (fbUser == null) {
        if (mounted) setState(() => _unreadMessages = 0);
        return;
      }
      final uid = fbUser.uid;
      // Direct count: messages sent TO the admin that are still unread.
      // Simpler and more reliable than reading the unreadCounts map on conversations.
      _chatSub = db
          .collectionGroup('messages')
          .where('receiverId', isEqualTo: uid)
          .where('isRead', isEqualTo: false)
          .snapshots()
          .listen((s) {
        if (mounted) setState(() => _unreadMessages = s.docs.length);
      }, onError: (_) {});
    });
  }

  Widget _buildNotifFabs(BuildContext context) {
    final fabs = <Widget>[];

    void addFab({
      required int count,
      required IconData icon,
      required Color color,
      required Widget page,
    }) {
      if (count <= 0) return;
      fabs.add(
        GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => page),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.40),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  constraints: const BoxConstraints(minWidth: 18),
                  height: 18,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: AppColors.secondary,
                    borderRadius: BorderRadius.circular(9),
                    border:
                        Border.all(color: Colors.white, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    count > 99 ? '99+' : '$count',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      fabs.add(const SizedBox(height: 10));
    }

    addFab(
      count: _unreadMessages,
      icon: Icons.chat_bubble_rounded,
      color: const Color(0xFFFF9F43),
      page: const AdminChatPage(),
    );
    addFab(
      count: _pendingOrders,
      icon: Icons.receipt_long_rounded,
      color: const Color(0xFF3B82F6),
      page: const AdminOrdersPage(),
    );
    addFab(
      count: _pendingPayments,
      icon: Icons.account_balance_wallet_rounded,
      color: const Color(0xFF1DD1A1),
      page: const AdminPaymentsPage(),
    );

    if (fabs.isEmpty) return const SizedBox.shrink();

    return Positioned(
      bottom: 16,
      left: 16,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: fabs.reversed.toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final w = MediaQuery.of(context).size.width;
    if (w >= 700) {
      final cartW = (w * 0.30).clamp(300.0, 440.0);
      return Stack(
        children: [
          Row(
            children: [
              Expanded(child: _ProductPanel(pos: widget.pos)),
              Container(width: 1, color: AppColors.border),
              SizedBox(width: cartW, child: _CartPanel(pos: widget.pos)),
            ],
          ),
          _buildNotifFabs(context),
        ],
      );
    }
    // Mobile / portrait: product panel + floating cart FAB
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
        _buildNotifFabs(context),
      ],
    );
  }

  void _showMobileCart(BuildContext context, PosController pos) {
    final h = MediaQuery.of(context).size.height;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SizedBox(
        height: h * (isLandscape ? 0.95 : 0.85),
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
  final _searchFocus = FocusNode();
  final _beep = AudioPlayer();
  final _error = AudioPlayer();
  String _query = '';
  String _categoryId = '';
  List<ProductModel> _products = [];
  List<CategoryModel> _categories = [];
  bool _loading = true;
  Timer? _debounce;
  StreamSubscription? _productSub;

  // USB / BT HID barcode scanner: accumulate keystrokes globally so the
  // on-screen keyboard never pops up during a scan.
  String _hwBuffer = '';
  int _hwLastKeyMs = 0;
  static const _kScanGapMs = 80; // scanners fire chars < 80 ms apart
  ModalRoute<dynamic>? _route;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _subscribeProducts();
    ever(widget.pos.reservedStock, (_) {
      if (mounted) setState(() {});
    });
    // WiFi barcode scanner (companion app)
    if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
      BarcodeScannerService.to.onBarcodeReceived = (barcode) {
        if (mounted) _onBarcodeSubmit(barcode);
      };
    }
    // USB / BT HID scanner — intercept hardware keys globally, no TextField focus
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    // Pre-load sounds so first play is instant (no asset-load latency)
    _beep
      ..setReleaseMode(ReleaseMode.stop)
      ..setSourceAsset('sounds/beeb.mp3');
    _error
      ..setReleaseMode(ReleaseMode.stop)
      ..setSourceAsset('sounds/error.mp3');
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _searchCtrl.dispose();
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

  bool _handleHardwareKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    // Don't intercept keys when another screen (e.g. product form) is on top
    if (_route?.isCurrent != true) return false;
    // User is typing in the search bar — let keystrokes through normally
    if (_searchFocus.hasFocus) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Gap too long → human key press, not scanner; reset buffer
    if (_hwBuffer.isNotEmpty && now - _hwLastKeyMs > _kScanGapMs) {
      _hwBuffer = '';
    }
    _hwLastKeyMs = now;

    // Enter → barcode complete, submit it
    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final code = _hwBuffer.trim();
      _hwBuffer = '';
      if (code.isNotEmpty && mounted) _onBarcodeSubmit(code);
      return true; // consume so Enter doesn't focus anything
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _hwBuffer += char;
      return true;
    }
    return false;
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
      final exact =
          _products.where((p) => p.barcode.trim() == trimmed).toList();
      if (exact.isNotEmpty) {
        // Match — add to cart + beep + clear bar
        _addProductToCart(exact.first);
        _searchCtrl.clear();
      } else {
        // No match — error sound, keep barcode in bar
        _error.seek(Duration.zero).then((_) => _error.resume());
      }
    });
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _query = value);
    });
  }

  Future<void> _openCameraScanner() async {
    final scanned = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _BarcodeScanSheet(),
    );
    if (scanned != null && scanned.isNotEmpty && mounted) {
      _onBarcodeSubmit(scanned);
    }
  }

  void _addProductToCart(ProductModel product) {
    widget.pos.addToCart(product);
    _beep.seek(Duration.zero).then((_) => _beep.resume());
  }

  Future<void> _showCustomItemDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => _CustomItemDialog(
        onAdd: (name, price, qty) {
          final customProduct = ProductModel(
            id: 'CUSTOM-${DateTime.now().millisecondsSinceEpoch}',
            name: name,
            price: price,
            stock: 9999,
          );
          for (var i = 0; i < qty; i++) {
            widget.pos.addToCart(customProduct);
          }
          _beep.seek(Duration.zero).then((_) => _beep.resume());
        },
      ),
    );
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
                  focusNode: _searchFocus,
                  onChanged: _onSearchChanged,
                  style: GoogleFonts.poppins(
                      fontSize: 14, color: AppColors.textPrimary),
                  decoration: InputDecoration(
                    hintText:
                        'ကုန်ပစ္စည်း ရှာမည်... (ဘားကုဒ် အလိုအလျောက် ထည့်သည်)',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                              _searchFocus.unfocus();
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
              if (MediaQuery.of(context).size.height < 700)
                IconButton(
                  onPressed: _openCameraScanner,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  tooltip: 'ကင်မရာဖြင့် ဘားကုဒ် စကန်',
                  color: AppColors.primary,
                ),
              IconButton(
                onPressed: _showCustomItemDialog,
                icon: const Icon(Icons.add_box_rounded),
                tooltip: 'Custom ကုန်ပစ္စည်း',
                color: AppColors.primary,
              ),
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
                  label: 'အားလုံး',
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
                          Text('ကုန်ပစ္စည်း မတွေ့ပါ',
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
// Custom Item Dialog
// ─────────────────────────────────────────────────────────────────────────────

class _CustomItemDialog extends StatefulWidget {
  final void Function(String name, double price, int qty) onAdd;
  const _CustomItemDialog({required this.onAdd});

  @override
  State<_CustomItemDialog> createState() => _CustomItemDialogState();
}

class _CustomItemDialogState extends State<_CustomItemDialog> {
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    final price = double.tryParse(_priceCtrl.text.trim()) ?? 0;
    final qty = int.tryParse(_qtyCtrl.text.trim()) ?? 1;
    if (name.isEmpty || price <= 0) return;
    widget.onAdd(name, price, qty.clamp(1, 999));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('Custom ကုန်ပစ္စည်း ထည့်မည်',
          style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _dialogField(
          ctrl: _nameCtrl,
          hint: 'ကုန်ပစ္စည်းအမည်',
          icon: Icons.label_outline_rounded,
          inputType: TextInputType.text,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 12),
        _dialogField(
          ctrl: _priceCtrl,
          hint: 'ဈေးနှုန်း (Ks)',
          icon: Icons.attach_money_rounded,
          // text type so any keyboard layout can enter numbers
          inputType: TextInputType.text,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
        ),
        const SizedBox(height: 12),
        _dialogField(
          ctrl: _qtyCtrl,
          hint: 'အရေအတွက်',
          icon: Icons.production_quantity_limits_rounded,
          inputType: TextInputType.number,
          onSubmitted: (_) => _submit(),
        ),
      ]),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('ပယ်ဖျက်မည်',
              style: GoogleFonts.poppins(color: AppColors.textMedium)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: _submit,
          child: Text('ထည့်မည်', style: GoogleFonts.poppins(fontSize: 13)),
        ),
      ],
    );
  }

  Widget _dialogField({
    required TextEditingController ctrl,
    required String hint,
    required IconData icon,
    required TextInputType inputType,
    ValueChanged<String>? onSubmitted,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: inputType,
      onSubmitted: onSubmitted,
      style: GoogleFonts.poppins(fontSize: 13, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle:
            GoogleFonts.poppins(fontSize: 13, color: AppColors.textMedium),
        prefixIcon: Icon(icon, size: 18, color: AppColors.textMedium),
        filled: true,
        fillColor: AppColors.bg,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
      ),
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
  String? _selectedStaff;
  List<String> _staffList = [];

  PosController get pos => widget.pos;

  @override
  void initState() {
    super.initState();
    _loadStaff();
  }

  Future<void> _loadStaff() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('pos_staff')
          .orderBy('name')
          .get();
      if (mounted) {
        final names = snap.docs
            .map((d) => (d.data()['name'] as String? ?? '').trim())
            .where((n) => n.isNotEmpty)
            .toList();
        setState(() {
          _staffList = names;
          if (_selectedStaff == null && names.isNotEmpty) {
            _selectedStaff = names.first;
          }
        });
      }
    } catch (_) {}
  }

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
          Text('ဈေးတောင်း ထဲ မရှိသေးပါ',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 14)),
          const SizedBox(height: 4),
          Text('ကုန်ပစ္စည်း ထည့်ရန် စကင်မည် သို့မဟုတ် နှိပ်ပါ',
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
    final method = pos.paymentMethod.value;
    final isCash = method == 'cash';
    return Column(
      children: [
        // Payment method toggle — 1 × 4 row
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            _PaymentBtn(
              label: 'ငွေသား',
              icon: Icons.payments_rounded,
              selected: method == 'cash',
              color: const Color(0xFF2D8CFF),
              onTap: () => pos.paymentMethod.value = 'cash',
            ),
            const SizedBox(width: 8),
            _PaymentBtn(
              label: 'KPay',
              icon: Icons.account_balance_wallet_rounded,
              assetImage: 'assets/icons/kpay.png',
              selected: method == 'kpay',
              color: const Color(0xFF00A0DC),
              onTap: () => pos.paymentMethod.value = 'kpay',
            ),
            const SizedBox(width: 8),
            _PaymentBtn(
              label: 'WavePay',
              icon: Icons.waves_rounded,
              assetImage: 'assets/icons/wavepay.png',
              selected: method == 'wavepay',
              color: const Color(0xFF7B2FF7),
              onTap: () => pos.paymentMethod.value = 'wavepay',
            ),
            const SizedBox(width: 8),
            _PaymentBtn(
              label: 'ကတ်',
              icon: Icons.credit_card_rounded,
              selected: method == 'card',
              color: const Color(0xFF43A047),
              onTap: () => pos.paymentMethod.value = 'card',
            ),
          ]),
        ),
        const SizedBox(height: 8),

        // ── Staff selector (optional) ──────────────────────────────────────
        if (_staffList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(children: [
                Icon(Icons.person_rounded, size: 18, color: AppColors.textMedium),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<String>(
                    value: _selectedStaff,
                    isExpanded: true,
                    underline: const SizedBox.shrink(),
                    dropdownColor: AppColors.card,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textPrimary),
                    hint: Text('ရောင်းချသူ ရွေးချယ်ရန်',
                        style: GoogleFonts.poppins(
                            fontSize: 12, color: AppColors.textMedium)),
                    items: [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text('မရွေးချယ်ရသေးပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.textMedium)),
                      ),
                      ..._staffList.map((name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(name,
                                style: GoogleFonts.poppins(fontSize: 13)),
                          )),
                    ],
                    onChanged: (v) => setState(() => _selectedStaff = v),
                  ),
                ),
              ]),
            ),
          ),
        const SizedBox(height: 8),

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

        // Digital payment view (KPay / WavePay / Card)
        if (!isCash)
          Expanded(
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _methodColor(method).withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: method == 'kpay' || method == 'wavepay'
                      ? Image.asset(
                          'assets/icons/$method.png',
                          width: 48,
                          height: 48,
                        )
                      : Icon(_methodIcon(method),
                          size: 48, color: _methodColor(method)),
                ),
                const SizedBox(height: 16),
                Text(_methodLabel(method),
                    style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Text(fmtPrice(pos.total),
                    style: GoogleFonts.poppins(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: _methodColor(method))),
                const SizedBox(height: 8),
                Text('ကောက်ခံရန် CHARGE နှိပ်ပါ',
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
                        Text('လျှော့ဈေး',
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
                      Text('စုစုပေါင်း',
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
                                  content: Text('မှာယူမှု ခေတ္တဆိုင်းထားပြီ',
                                      style: GoogleFonts.poppins()),
                                  backgroundColor: AppColors.textMedium,
                                  behavior: SnackBarBehavior.floating,
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.pause_rounded, size: 16),
                            label: Text('ဆိုင်းထားရန်',
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
                            label: Text('ငွေပေးချေ',
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
                            label: Text('မလုပ်တော့',
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
                                  label: Text('ကောက်ခံ',
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
    final sale = await pos.processPayment(_cashierName,
        staffName: _selectedStaff ?? '');
    if (sale == null) return;
    // Cart is now cleared — hide payment view so the (empty) cart shows
    _cashCtrl.clear();
    _discountCtrl.clear();
    if (mounted) {
      setState(() {
        _showNumpad = false;
        _selectedStaff = null;
      });
    }
    // Refresh history so Sales History tab (today totals) updates immediately
    pos.fetchSalesHistory();
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
        title: Text('ဈေးတောင်း ရှင်းရန်',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text('ဈေးတောင်းမှ ပစ္စည်းအားလုံး ဖယ်ရှားမလား?',
            style: GoogleFonts.poppins(color: AppColors.textMedium)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('မလုပ်တော့',
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
            child: Text('ရှင်းရန်',
                style: GoogleFonts.poppins(color: Colors.white)),
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
          title: Text('မှာယူမှု လျှော့ဈေး',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _DiscTypeBtn(
                      label: 'ပမာဏ (ကျပ်)',
                      selected: type == 'amount',
                      onTap: () => setS(() => type = 'amount')),
                  const SizedBox(width: 8),
                  _DiscTypeBtn(
                      label: 'ရာခိုင်နှုန်း (%)',
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
              child: Text('ဖယ်ရှားရန်',
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
              child: Text('သုံးရန်',
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
                child: Text(
                    'ခေတ္တဆိုင်းထားသော မှာယူမှုများ (${pos.heldOrders.length})',
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
                            content: Text('ပြန်လည် ဆောင်ရွက်သည်: $id',
                                style: GoogleFonts.poppins()),
                            backgroundColor: AppColors.primary,
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 3),
                          ));
                        },
                        child: Text('ဆက်ရန်',
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

  Color _methodColor(String method) {
    switch (method) {
      case 'kpay':
        return const Color(0xFF00A0DC);
      case 'wavepay':
        return const Color(0xFF7B2FF7);
      case 'card':
        return const Color(0xFF43A047);
      default:
        return AppColors.primary;
    }
  }

  IconData _methodIcon(String method) {
    switch (method) {
      case 'kpay':
        return Icons.account_balance_wallet_rounded;
      case 'wavepay':
        return Icons.waves_rounded;
      case 'card':
        return Icons.credit_card_rounded;
      default:
        return Icons.payments_rounded;
    }
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'kpay':
        return 'KBZ Pay (KPay) ဖြင့် ငွေပေးချေမှု';
      case 'wavepay':
        return 'WavePay ဖြင့် ငွေပေးချေမှု';
      case 'card':
        return 'ကတ်ဖြင့် ငွေပေးချေမှု';
      default:
        return 'ငွေပေးချေမှု';
    }
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
        storeName:
            prefs.getString(ReceiptSettings.kStoreName) ?? 'သုံးရာသီဖိနပ်ဆိုင်',
        storeAddress: prefs.getString(ReceiptSettings.kStoreAddress) ??
            '54 လမ်း, 115D လမ်းထောင့်',
        footer: prefs.getString(ReceiptSettings.kFooter) ??
            'အားပေးမှုကိုကျေးဇူးတင်ပါတယ်',
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
                  Text('ငွေပေးချေမှု အောင်မြင်ပြီ',
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
                          label: Text('ပိတ်ရန်',
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
                          label: Text('ဓာတ်ပုံ ပရင့်ထုတ်ရန်',
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
                      label: Text('စာသား ပရင့်ထုတ်ရန် (အင်္ဂလိပ်သာ)',
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
        content: Text('အရင်ဆုံး ဘလူးတုသ် ပရင်တာ ချိတ်ပါ',
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
        content:
            Text('ပရင့်ထုတ်မှု မအောင်မြင်ပါ: $e', style: GoogleFonts.poppins()),
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
              _pdfRow('လျှော့ဈေး', '-${fmtPrice(sale.discount)}'),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('စုစုပေါင်း',
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
                pw.Text(fmtPrice(sale.total),
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold)),
              ],
            ),
            pw.SizedBox(height: 4),
            if (sale.paymentMethod == 'cash') ...[
              _pdfRow('ငွေသား', fmtPrice(sale.cashGiven)),
              _pdfRow('ငွေအမ်း', fmtPrice(sale.change)),
            ] else
              _pdfRow(
                  'ငွေပေးချေမှု',
                  sale.paymentMethod == 'kpay'
                      ? 'KPay'
                      : sale.paymentMethod == 'wavepay'
                          ? 'WavePay'
                          : 'ကတ်'),
            pw.Divider(),
            pw.Center(
              child: pw.Text('Thank you! / Kyay Zu Tin Bar Tae',
                  style: const pw.TextStyle(fontSize: 9)),
            ),
            pw.SizedBox(height: 40),
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
        if (settings.showId) _ReceiptRow('ဘောင်ချာ', sale.id, small: true),
        if (settings.showDate)
          _ReceiptRow(
              'Date', DateFormat('dd/MM/yyyy HH:mm').format(sale.createdAt),
              small: true),
        if (settings.showCashier)
          _ReceiptRow('Cashier', sale.cashierName, small: true),
        if (settings.showCashier && sale.staffName.isNotEmpty)
          _ReceiptRow('Staff', sale.staffName, small: true),
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
          _ReceiptRow('လျှော့ဈေး', '-${fmtPrice(sale.discount)}'),
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
          _ReceiptRow(
              'ငွေပေးချေမှု',
              sale.paymentMethod == 'kpay'
                  ? 'KPay'
                  : sale.paymentMethod == 'wavepay'
                      ? 'WavePay'
                      : 'ကတ်'),
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
        child: SizedBox(
          width: double.infinity,
          child: Text(
            '-' * 200,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: TextStyle(
                fontSize: 11, color: AppColors.textMedium, letterSpacing: 0),
          ),
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
  final Color color;
  final VoidCallback onTap;
  final String? assetImage;
  const _PaymentBtn(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.color,
      required this.onTap,
      this.assetImage});

  @override
  Widget build(BuildContext context) {
    final Widget logoWidget = assetImage != null
        ? Image.asset(assetImage!, width: 28, height: 28)
        : Icon(icon,
            size: 26, color: selected ? Colors.white : AppColors.textMedium);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: selected ? 6 : 10),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? color : AppColors.border,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              logoWidget,
              if (selected) ...[
                const SizedBox(height: 3),
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
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

class _SalesHistoryTabState extends State<_SalesHistoryTab>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  String _query = '';
  late TabController _phoneTabCtrl;

  // ── Chart state ───────────────────────────────────────────────────────────
  Map<DateTime, double> _chartData = {};
  bool _chartLoading = false;
  late DateTime _chartFrom;
  late DateTime _chartTo;

  @override
  void initState() {
    super.initState();
    _phoneTabCtrl = TabController(length: 2, vsync: this);
    final now = DateTime.now();
    _chartTo = DateTime(now.year, now.month, now.day);
    _chartFrom = _chartTo.subtract(const Duration(days: 6));
    _fetchChart();
  }

  @override
  void dispose() {
    _phoneTabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchChart() async {
    setState(() => _chartLoading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('pos_sales').get();
      final Map<DateTime, double> map = {};
      final days = _chartTo.difference(_chartFrom).inDays;
      for (int i = 0; i <= days; i++) {
        map[_chartFrom.add(Duration(days: i))] = 0;
      }
      for (final doc in snap.docs) {
        final d = doc.data();
        final isRefund = (d['type'] as String? ?? 'sale') == 'refund';
        final raw = d['createdAt'];
        DateTime? dt;
        if (raw is String) dt = DateTime.tryParse(raw);
        if (dt == null) continue;
        final day = DateTime(dt.year, dt.month, dt.day);
        if (map.containsKey(day)) {
          final amount = (d['total'] as num?)?.toDouble() ?? 0;
          map[day] = (map[day] ?? 0) + (isRefund ? -amount : amount);
        }
      }
      if (mounted)
        setState(() {
          _chartData = map;
          _chartLoading = false;
        });
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _pickChartRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _chartFrom, end: _chartTo),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null && mounted) {
      setState(() {
        _chartFrom =
            DateTime(picked.start.year, picked.start.month, picked.start.day);
        _chartTo = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      _fetchChart();
    }
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

  String _fmtK(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  Widget _buildChartPanel() {
    final sortedDays = _chartData.keys.toList()..sort();
    final maxVal = _chartData.values.fold(0.0, max);
    final yMax = maxVal <= 0 ? 1000.0 : maxVal * 1.25;
    final total = _chartData.values.fold<double>(0, (a, b) => a + b);
    final activeDays = _chartData.values.where((v) => v > 0).length;

    // ── Today's payment breakdown ──────────────────────────────────────────
    final now = DateTime.now();
    final todaySales = widget.pos.salesHistory.where((s) {
      final d = s.createdAt;
      return d.year == now.year &&
          d.month == now.month &&
          d.day == now.day &&
          !s.isRefundRecord;
    }).toList();

    double todayCash = 0, todayKpay = 0, todayWave = 0, todayCard = 0;
    for (final s in todaySales) {
      switch (s.paymentMethod) {
        case 'cash':
          todayCash += s.total;
          break;
        case 'kpay':
          todayKpay += s.total;
          break;
        case 'wavepay':
          todayWave += s.total;
          break;
        case 'card':
          todayCard += s.total;
          break;
      }
    }
    final todayTotal = todayCash + todayKpay + todayWave + todayCard;
    final todayProfit = todaySales.fold<double>(0, (a, s) => a + s.totalProfit);
    final hasProfitData = todaySales.any((s) => s.hasProfitData);

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Today's breakdown ─────────────────────────────────────────────
          Text('ယနေ့ ရောင်းချမှု',
              style: GoogleFonts.poppins(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Row(children: [
            _PayBadge(
                label: 'ငွေသား',
                amount: todayCash,
                color: const Color(0xFF2D8CFF),
                icon: Icons.payments_rounded),
            if (todayKpay > 0) ...[
              const SizedBox(width: 6),
              _PayBadge(
                  label: 'KPay',
                  amount: todayKpay,
                  color: const Color(0xFF00A0DC),
                  assetImage: 'assets/icons/kpay.png'),
            ],
            if (todayWave > 0) ...[
              const SizedBox(width: 6),
              _PayBadge(
                  label: 'WavePay',
                  amount: todayWave,
                  color: const Color(0xFF7B2FF7),
                  assetImage: 'assets/icons/wavepay.png'),
            ],
            if (todayCard > 0) ...[
              const SizedBox(width: 6),
              _PayBadge(
                  label: 'ကတ်',
                  amount: todayCard,
                  color: const Color(0xFF43A047),
                  icon: Icons.credit_card_rounded),
            ],
          ]),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('ယနေ့ စုစုပေါင်း',
                    style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                Text(fmtPrice(todayTotal),
                    style: GoogleFonts.poppins(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF27AE60).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  const Icon(Icons.trending_up_rounded,
                      size: 14, color: Color(0xFF27AE60)),
                  const SizedBox(width: 4),
                  Text('ယနေ့ အမြတ်',
                      style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF27AE60))),
                ]),
                hasProfitData
                    ? Text(fmtPrice(todayProfit),
                        style: GoogleFonts.poppins(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF27AE60)))
                    : Text('မရှိသေး',
                        style: GoogleFonts.poppins(
                            fontSize: 11, color: AppColors.textMedium)),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Header ────────────────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('နေ့စဉ် ရောင်းချမှု',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  Text(
                    '${DateFormat('dd MMM').format(_chartFrom)} – ${DateFormat('dd MMM').format(_chartTo)}',
                    style: GoogleFonts.poppins(
                        fontSize: 10, color: AppColors.textMedium),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _pickChartRange,
              icon: const Icon(Icons.date_range_rounded, size: 14),
              label: Text('ကာလ',
                  style: GoogleFonts.poppins(
                      fontSize: 11, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ]),
          const SizedBox(height: 12),

          // ── Bar chart ─────────────────────────────────────────────────────
          Expanded(
            child: _chartLoading
                ? const Center(child: CircularProgressIndicator())
                : sortedDays.isEmpty
                    ? Center(
                        child: Text('ဤကာလ ရောင်းချမှု မရှိပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.textMedium)))
                    : BarChart(
                        BarChartData(
                          maxY: yMax,
                          minY: 0,
                          barGroups: sortedDays.asMap().entries.map((e) {
                            final revenue = _chartData[e.value] ?? 0;
                            return BarChartGroupData(
                              x: e.key,
                              barRods: [
                                BarChartRodData(
                                  toY: revenue,
                                  width: (180 / sortedDays.length)
                                      .clamp(5.0, 18.0),
                                  borderRadius: const BorderRadius.vertical(
                                      top: Radius.circular(4)),
                                  gradient: LinearGradient(
                                    colors: [
                                      AppColors.primary,
                                      AppColors.primary.withValues(alpha: 0.5),
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
                                reservedSize: 40,
                                interval: yMax / 4,
                                getTitlesWidget: (v, _) {
                                  if (v == 0) return const SizedBox.shrink();
                                  return Text(_fmtK(v),
                                      style: GoogleFonts.poppins(
                                          fontSize: 8,
                                          color: AppColors.textMedium));
                                },
                              ),
                            ),
                            bottomTitles: AxisTitles(
                              sideTitles: SideTitles(
                                showTitles: true,
                                reservedSize: 22,
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
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text(
                                      DateFormat('dd/MM').format(sortedDays[i]),
                                      style: GoogleFonts.poppins(
                                          fontSize: 8,
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
                                      fontSize: 10,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
          ),

          // ── Summary stats ─────────────────────────────────────────────────
          if (!_chartLoading && _chartData.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: _MiniStat(
                  label: 'စုစုပေါင်း',
                  value: fmtPrice(total),
                  color: AppColors.primary,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'ရောင်းချသောနေ့',
                  value: '$activeDays ရက်',
                  color: AppColors.accent,
                ),
              ),
              Expanded(
                child: _MiniStat(
                  label: 'ပျမ်းမျှ/နေ့',
                  value: fmtPrice(activeDays > 0 ? total / activeDays : 0),
                  color: AppColors.textMedium,
                ),
              ),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildSalesList() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          color: AppColors.card,
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: GoogleFonts.poppins(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'ID၊ ကက်ရှယာ၊ ကုန်ပစ္စည်းဖြင့် ရှာမည်...',
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
                    Text('ရောင်းချမှု မရှိသေးပါ',
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
                    Text('"$_query" အတွက် ရလဒ် မတွေ့ပါ',
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
                                    child: Text('ပြန်အမ်းပြီ',
                                        style: GoogleFonts.poppins(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.secondary)),
                                  ),
                              ]),
                              Text(
                                '${sale.items.length} items • ${sale.paymentMethod.toUpperCase()} • ${sale.cashierName}${sale.staffName.isNotEmpty ? ' • Staff: ${sale.staffName}' : ''}',
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
                              _HistoryActionBtn(
                                icon: Icons.print_rounded,
                                color: AppColors.primary,
                                tooltip: 'View receipt',
                                onTap: () => showDialog(
                                  context: context,
                                  builder: (_) => _ReceiptDialog(sale: sale),
                                ),
                              ),
                              if (!isRefund && !isRefunded) ...[
                                const SizedBox(width: 6),
                                _HistoryActionBtn(
                                  icon: Icons.undo_rounded,
                                  color: AppColors.secondary,
                                  tooltip: 'ပြန်အမ်းရန်',
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

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width;

    if (w < 700) {
      return Column(
        children: [
          Container(
            color: AppColors.card,
            child: TabBar(
              controller: _phoneTabCtrl,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMedium,
              indicatorColor: AppColors.primary,
              labelStyle: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600),
              unselectedLabelStyle:
                  GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w500),
              tabs: const [
                Tab(text: 'ရောင်းချမှု သမိုင်း'),
                Tab(text: 'ယနေ့ ရောင်းချမှု'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _phoneTabCtrl,
              children: [
                _buildSalesList(),
                Obx(() => _buildChartPanel()),
              ],
            ),
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 55, child: _buildSalesList()),
        Container(width: 1, color: AppColors.border),
        Expanded(
          flex: 45,
          child: Obx(() => _buildChartPanel()),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _MiniStat(
      {required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(value,
            style: GoogleFonts.poppins(
                fontSize: 12, fontWeight: FontWeight.w700, color: color),
            textAlign: TextAlign.center),
        Text(label,
            style:
                GoogleFonts.poppins(fontSize: 9, color: AppColors.textMedium),
            textAlign: TextAlign.center),
      ],
    );
  }
}

class _PayBadge extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData? icon;
  final String? assetImage;
  const _PayBadge(
      {required this.label,
      required this.amount,
      required this.color,
      this.icon,
      this.assetImage});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              if (assetImage != null)
                Image.asset(assetImage!, width: 18, height: 18)
              else
                Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(label,
                    style: GoogleFonts.poppins(
                        fontSize: 9, fontWeight: FontWeight.w600, color: color),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 2),
            Text(fmtPrice(amount),
                style: GoogleFonts.poppins(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
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
            _QuickBtn(label: 'တိကျသော', onTap: () => _quickSet(widget.total)),
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
                Text('ငွေအမ်း',
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
                Text('ဆက်လိုသည်',
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
          Text('ပြန်အမ်းရန်',
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
            Text('ပြန်အမ်းမည့် ပစ္စည်းနှင့် အရေအတွက် ရွေးပါ',
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
                Text('ပြန်အမ်းငွေ စုစုပေါင်း',
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
          child: Text('မလုပ်တော့',
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
              label: Text('ပြန်အမ်းငွေ အတည်ပြုရန်',
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
  @override
  Widget build(BuildContext context) {
    final items = [
      _DashCardData(
        icon: Icons.storefront_rounded,
        title: 'ကုန်ပစ္စည်းများ',
        subtitle: 'ထည့်ရန် / ပြင်ရန် / ဖျက်ရန်',
        colorA: const Color(0xFF43A047),
        colorB: const Color(0xFF1B5E20),
        onTap: () => context.push('/admin/products'),
      ),
      _DashCardData(
        icon: Icons.inventory_2_rounded,
        title: 'လျော့နည်းကုန်ပစ္စည်းများ',
        subtitle: 'ကုန်ပစ္စည်း နည်းပါးနေသည်',
        colorA: const Color(0xFFFF8C00),
        colorB: const Color(0xFFE65100),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const _LowStockPage())),
      ),
      _DashCardData(
        icon: Icons.devices_rounded,
        title: 'ဟာ့ဒ်ဝဲ',
        subtitle: 'စကင်နာ & ပရင်တာ',
        colorA: const Color(0xFF1976D2),
        colorB: const Color(0xFF0D47A1),
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const HardwarePage())),
      ),
      _DashCardData(
        icon: Icons.receipt_long_rounded,
        title: 'ဘောင်ချာ',
        subtitle: 'ဘောင်ချာ ပြင်ဆင်ရန်',
        colorA: const Color(0xFF2E7D32),
        colorB: const Color(0xFF1B5E20),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _ReceiptManagementPage())),
      ),
      _DashCardData(
        icon: Icons.show_chart_rounded,
        title: 'အမြတ်',
        subtitle: 'ဝင်ငွေ နှင့် ကုန်ကျစ်ရိတ်',
        colorA: const Color(0xFF00897B),
        colorB: const Color(0xFF00695C),
        onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => _ProfitAnalyticsPage(pos: widget.pos))),
      ),
      _DashCardData(
        icon: Icons.people_rounded,
        title: 'ဝန်ထမ်းများ',
        subtitle: 'ရောင်းချသူ စီမံရန်',
        colorA: const Color(0xFF6A1B9A),
        colorB: const Color(0xFF4A148C),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const _StaffManagementPage())),
      ),
      _DashCardData(
        icon: Icons.label_rounded,
        title: 'Label ရိုက်ရန်',
        subtitle: 'ဂေါ်ပတ်ကပ် ဒီဇိုင်း & ပရင့်',
        colorA: const Color(0xFF00B4D8),
        colorB: const Color(0xFF0096C7),
        onTap: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const LabelPrintScreen())),
      ),
      _DashCardData(
        icon: Icons.print_rounded,
        title: 'စမ်းသပ် ပရင့်ထုတ်ရန်',
        subtitle: 'ပရင်တာ စစ်ဆေးရန်',
        colorA: const Color(0xFFC62828),
        colorB: const Color(0xFFB71C1C),
        onTap: () {
          final bt = BtPrinterService.to;
          if (!bt.isConnected.value) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                  'ပရင်တာ မချိတ်ဆက်ရသေးပါ။ ဟာ့ဒ်ဝဲ → ချိတ်ဆက်ရန် သွားပါ',
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
                ok
                    ? 'Check your printer for the test page.'
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
              Text('POS ဒက်ရ်ှဘုတ်',
                  style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text('စီမံရန် တစ်ဆောင်ရာ နှိပ်ပါ',
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

  static const _amber = Color(0xFFF39C12);
  static const _green = Color(0xFF27AE60);

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
        title: Text('လျော့နည်းကုန်ပစ္စည်းများ',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        elevation: 0,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded), onPressed: _fetch),
        ],
      ),
      body: LayoutBuilder(builder: (_, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 300, child: _buildLeftPanel()),
            VerticalDivider(
                width: 1, thickness: 1, color: AppColors.border),
            Expanded(child: _buildProductArea(isGrid: true)),
          ]);
        }
        return Column(children: [
          _buildThresholdBar(),
          Expanded(child: _buildProductArea(isGrid: false)),
        ]);
      }),
    );
  }

  Widget _buildThresholdBar() {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(children: [
        Text('သတိပေးမှု: ',
            style: GoogleFonts.poppins(
                fontSize: 13, color: AppColors.textMedium)),
        Expanded(
          child: Slider(
            value: _threshold.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            activeColor: _amber,
            label: _threshold.toString(),
            onChanged: (v) => setState(() => _threshold = v.toInt()),
            onChangeEnd: (v) { _saveThreshold(v.toInt()); _fetch(); },
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: _amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('≤ $_threshold',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _amber)),
        ),
      ]),
    );
  }

  Widget _buildLeftPanel() {
    final outCount = _items
        .where((i) => ((i['stock'] as num?)?.toInt() ?? 0) == 0)
        .length;
    final lowCount = _items.length - outCount;

    return Container(
      color: AppColors.card,
      height: double.infinity,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Text('ကုန်ပစ္စည်း အနေအထား',
              style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          _buildStatCard(
            icon: Icons.remove_shopping_cart_rounded,
            label: 'ကုန်ပစ္စည်း မရှိ',
            count: outCount,
            color: AppColors.secondary,
          ),
          const SizedBox(height: 10),
          _buildStatCard(
            icon: Icons.warning_amber_rounded,
            label: 'လျော့နည်းနေသော',
            count: lowCount,
            color: _amber,
          ),
          const SizedBox(height: 10),
          _buildStatCard(
            icon: Icons.inventory_2_rounded,
            label: 'ထောက်လှမ်းမှု စုစုပေါင်း',
            count: _items.length,
            color: AppColors.primary,
          ),
          const SizedBox(height: 24),
          Divider(color: AppColors.border, height: 1),
          const SizedBox(height: 20),
          Text('သတိပေးမှု စံနှုန်း',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text('Stock ≤ $_threshold ဖြစ်သောကုန်ပစ္စည်းများ ပြသည်',
              style: GoogleFonts.poppins(
                  fontSize: 11, color: AppColors.textMedium)),
          Slider(
            value: _threshold.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            activeColor: _amber,
            label: _threshold.toString(),
            onChanged: (v) => setState(() => _threshold = v.toInt()),
            onChangeEnd: (v) { _saveThreshold(v.toInt()); _fetch(); },
          ),
          Center(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
              decoration: BoxDecoration(
                color: _amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('≤ $_threshold ခု',
                  style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _amber)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required String label,
    required int count,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 20, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label,
              style: GoogleFonts.poppins(
                  fontSize: 12, color: AppColors.textMedium)),
        ),
        Text('$count',
            style: GoogleFonts.poppins(
                fontSize: 26, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  Widget _buildProductArea({required bool isGrid}) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.check_circle_outline_rounded,
              size: 64, color: _green),
          const SizedBox(height: 14),
          Text('ကုန်ပစ္စည်းအားလုံး လုံလောက်စွာ ရှိသည်',
              style: GoogleFonts.poppins(
                  fontSize: 15, color: AppColors.textMedium)),
        ]),
      );
    }
    if (isGrid) {
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 3.4,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: _items.length,
        itemBuilder: (_, i) => _buildProductCard(_items[i]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _items.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: _buildProductCard(_items[i]),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> item) {
    final stock = (item['stock'] as num?)?.toInt() ?? 0;
    final isOut = stock == 0;
    final color = isOut ? AppColors.secondary : _amber;
    final progress =
        _threshold > 0 ? (stock / _threshold).clamp(0.0, 1.0) : 0.0;

    final rawUrl = (item['thumbnail'] as String? ?? '').isNotEmpty
        ? item['thumbnail'] as String
        : ((item['images'] as List?)?.isNotEmpty == true
            ? (item['images'] as List).first as String
            : '');
    final url = AppConstants.fixImageUrl(rawUrl);
    final brand = (item['brand'] as String? ?? '');

    final thumb = url.isNotEmpty
        ? CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: color.withValues(alpha: 0.1),
              child: Icon(Icons.image_outlined, color: color, size: 22),
            ),
            errorWidget: (_, __, ___) => Container(
              color: color.withValues(alpha: 0.1),
              child: Icon(
                isOut
                    ? Icons.remove_shopping_cart_rounded
                    : Icons.warning_amber_rounded,
                color: color,
                size: 22,
              ),
            ),
          )
        : Container(
            color: color.withValues(alpha: 0.1),
            child: Icon(
              isOut
                  ? Icons.remove_shopping_cart_rounded
                  : Icons.warning_amber_rounded,
              color: color,
              size: 22,
            ),
          );

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        ClipRRect(
          borderRadius:
              const BorderRadius.horizontal(left: Radius.circular(12)),
          child: SizedBox(width: 64, child: thumb),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  item['name'] ?? '',
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (brand.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(brand,
                      style: GoogleFonts.poppins(
                          fontSize: 10, color: AppColors.textMedium),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
                const SizedBox(height: 7),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: color.withValues(alpha: 0.12),
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 12),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              isOut ? 'OUT' : '$stock',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hardware Page
// ─────────────────────────────────────────────────────────────────────────────

class HardwarePage extends StatefulWidget {
  const HardwarePage({super.key});

  @override
  State<HardwarePage> createState() => _HardwarePageState();
}

class _HardwarePageState extends State<HardwarePage> {
  static const _kPaperWidth = 'pos_paper_width';
  int _paperWidth = 80;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _paperWidth = p.getInt(_kPaperWidth) ?? 80);
    });
    if (!kIsWeb) BtPrinterService.to.loadPairedDevices();
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
        title: Text('ဟာ့ဒ်ဝဲ',
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
            title: 'ဘောင်ချာ စာရွက် အရွယ်',
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
          _SectionCard(
            icon: Icons.bluetooth_rounded,
            iconColor: const Color(0xFF2980B9),
            title: 'ဘလူးတုသ် ပရင်တာ',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status banner
                Obx(() {
                  final bt = BtPrinterService.to;
                  final connected = bt.isConnected.value;
                  final name = bt.connectedDevice.value?.name ?? '';
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: connected
                          ? const Color(0xFF27AE60).withValues(alpha: 0.08)
                          : Colors.orange.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: connected
                              ? const Color(0xFF27AE60).withValues(alpha: 0.5)
                              : Colors.orange.withValues(alpha: 0.5)),
                    ),
                    child: Row(children: [
                      Icon(
                        connected
                            ? Icons.bluetooth_connected_rounded
                            : Icons.bluetooth_disabled_rounded,
                        color: connected
                            ? const Color(0xFF27AE60)
                            : Colors.orange,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              connected ? 'ချိတ်ဆက်ပြီး' : 'မချိတ်မိသေးဘူး',
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: connected
                                      ? const Color(0xFF27AE60)
                                      : Colors.orange),
                            ),
                            if (name.isNotEmpty)
                              Text(name,
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: AppColors.textMedium)),
                          ],
                        ),
                      ),
                      if (connected)
                        TextButton(
                          onPressed: bt.disconnect,
                          child: Text('ဖြတ်ရန်',
                              style: GoogleFonts.poppins(
                                  color: Colors.red, fontSize: 12)),
                        ),
                    ]),
                  );
                }),

                const SizedBox(height: 12),

                // Device list header + refresh
                Row(children: [
                  Text('Paired Devices',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary)),
                  const Spacer(),
                  Obx(() {
                    final bt = BtPrinterService.to;
                    return bt.isScanning.value
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : IconButton(
                            onPressed: bt.loadPairedDevices,
                            icon: const Icon(Icons.refresh_rounded),
                            color: AppColors.primary,
                            iconSize: 20,
                            tooltip: 'ထပ်မံ ရှာရန်',
                            constraints: const BoxConstraints(),
                            padding: const EdgeInsets.all(4),
                          );
                  }),
                ]),

                const SizedBox(height: 6),

                // Inline device list
                Obx(() {
                  final bt = BtPrinterService.to;
                  if (bt.isScanning.value) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (bt.devices.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(children: [
                        Icon(Icons.bluetooth_searching_rounded,
                            color: AppColors.textLight, size: 30),
                        const SizedBox(height: 6),
                        Text('Paired ပရင်တာ မတွေ့ပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                color: AppColors.textMedium)),
                        Text('Refresh နှိပ်ပါ သို့မဟုတ် အောက်ပါ အဆင့်များ လိုက်နာပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 11,
                                color: AppColors.textLight)),
                      ]),
                    );
                  }
                  return Column(
                    children: bt.devices.map((d) {
                      final isThis =
                          bt.connectedDevice.value?.address == d.address &&
                              bt.isConnected.value;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        decoration: BoxDecoration(
                          color: isThis
                              ? const Color(0xFF27AE60).withValues(alpha: 0.06)
                              : AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: isThis
                                  ? const Color(0xFF27AE60)
                                      .withValues(alpha: 0.4)
                                  : AppColors.border),
                        ),
                        child: ListTile(
                          dense: true,
                          leading: Icon(
                            isThis
                                ? Icons.bluetooth_connected_rounded
                                : Icons.print_rounded,
                            color: isThis
                                ? const Color(0xFF27AE60)
                                : AppColors.textMedium,
                            size: 20,
                          ),
                          title: Text(d.name,
                              style: GoogleFonts.poppins(
                                  fontSize: 13,
                                  fontWeight: isThis
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: AppColors.textPrimary)),
                          subtitle: Text(d.address,
                              style: GoogleFonts.poppins(
                                  fontSize: 10,
                                  color: AppColors.textMedium)),
                          trailing: isThis
                              ? Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF27AE60)
                                        .withValues(alpha: 0.12),
                                    borderRadius:
                                        BorderRadius.circular(6),
                                  ),
                                  child: Text('Connected',
                                      style: GoogleFonts.poppins(
                                          fontSize: 10,
                                          color:
                                              const Color(0xFF27AE60),
                                          fontWeight:
                                              FontWeight.w600)),
                                )
                              : Obx(() => bt.isConnecting.value
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2))
                                  : ElevatedButton(
                                      onPressed: () => bt.connect(d),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            AppColors.primary,
                                        foregroundColor: Colors.white,
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 12,
                                                vertical: 6),
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(
                                                    8)),
                                        minimumSize: Size.zero,
                                        tapTargetSize:
                                            MaterialTapTargetSize
                                                .shrinkWrap,
                                      ),
                                      child: Text('ချိတ်ဆက်ရန်',
                                          style: GoogleFonts.poppins(
                                              fontSize: 11)),
                                    )),
                        ),
                      );
                    }).toList(),
                  );
                }),

                const SizedBox(height: 12),

                // Troubleshooting guide
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.help_outline_rounded,
                            size: 14, color: Colors.amber),
                        const SizedBox(width: 6),
                        Text('ချိတ်မရလျှင် ဤအဆင့်များ လိုက်နာပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.amber)),
                      ]),
                      const SizedBox(height: 6),
                      _StepRow(
                          step: '1',
                          text: 'ပရင်တာကို ဖွင့်ပါ (Power ON)'),
                      _StepRow(
                          step: '2',
                          text:
                              'ဖုန်း Settings → Bluetooth တွင် ပရင်တာကို Pair ဦးပါ'),
                      _StepRow(
                          step: '3',
                          text:
                              'ဤနေရာသို့ ပြန်လာပြီး Refresh (↻) နှိပ်ပါ'),
                      _StepRow(
                          step: '4',
                          text:
                              'စာရင်းမှ ပရင်တာ နာမည် ရွေးပြီး "ချိတ်ဆက်ရန်" နှိပ်ပါ'),
                      _StepRow(
                          step: '5',
                          text:
                              'ထပ်ချိတ်မရလျှင် ပရင်တာကို ပိတ်ပြီး ပြန်ဖွင့်ပါ'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Barcode Scanner ─────────────────────────────────────────────
          _SectionCard(
            icon: Icons.qr_code_scanner_rounded,
            iconColor: const Color(0xFF27AE60),
            title: 'ဘားကုဒ် စကင်နာ (BT HID)',
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
                title: 'ကွန်ရက် ဘားကုဒ် (WiFi)',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Status row
                    Row(children: [
                      Container(
                        width: 8,
                        height: 8,
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
                                    fontSize: 10, color: AppColors.secondary)),
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
                          child: _ConnInfoBox(label: 'IP လိပ်စာ', value: ip),
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
                          label: Text('$ip:$p ကူးရန်',
                              style: GoogleFonts.poppins(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF00897B),
                            side: const BorderSide(color: Color(0xFF00897B)),
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
                        Text('နောက်ဆုံး လက်ခံသည်: $last',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: AppColors.textMedium)),
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
        content:
            Text('ဘောင်ချာ ဆက်တင် သိမ်းဆည်းပြီ', style: GoogleFonts.poppins()),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  // ── Section helpers ──────────────────────────────────────────────────────

  Widget _buildStoreInfoCard() => _SectionCard(
        icon: Icons.store_rounded,
        iconColor: const Color(0xFF27AE60),
        title: 'ဆိုင် အချက်အလက်',
        child: Column(children: [
          _LabeledField(
            label: 'ဆိုင် နာမည်',
            controller: _nameCtrl,
            hint: 'e.g. TSfootwear',
          ),
          const SizedBox(height: 12),
          _LabeledField(
            label: 'ဆိုင် လိပ်စာ',
            controller: _addressCtrl,
            hint: 'e.g. 54 St, 115D Corner',
          ),
        ]),
      );

  Widget _buildFooterCard() => _SectionCard(
        icon: Icons.format_quote_rounded,
        iconColor: const Color(0xFF8E44AD),
        title: 'အောက်ခြေ မက်ဆေ့ချ်',
        child: _LabeledField(
          label: 'အောက်ခြေ စာသား',
          controller: _footerCtrl,
          hint: 'e.g. Thank you! Come again.',
        ),
      );

  Widget _buildTogglesCard() => _SectionCard(
        icon: Icons.visibility_rounded,
        iconColor: const Color(0xFF2980B9),
        title: 'ဘောင်ချာတွင် ပြသရန်',
        child: Column(children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('ဘောင်ချာ ID',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textPrimary)),
            value: _showId,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _showId = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('ရက်စွဲ & အချိန်',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textPrimary)),
            value: _showDate,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _showDate = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('ကက်ရှယာ နာမည်',
                style: GoogleFonts.poppins(
                    fontSize: 13, color: AppColors.textPrimary)),
            value: _showCashier,
            activeThumbColor: AppColors.primary,
            onChanged: (v) => setState(() => _showCashier = v),
          ),
        ]),
      );

  Widget _buildPreviewCard() => _SectionCard(
        icon: Icons.preview_rounded,
        iconColor: const Color(0xFFF39C12),
        title: 'ဘောင်ချာ ကြိုကြည့်',
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.border),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
            ],
          ),
          child: DefaultTextStyle(
            style: const TextStyle(
                fontFamily: 'Courier', fontSize: 12, color: Colors.black),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(_nameCtrl.text.isEmpty ? 'ဆိုင် နာမည်' : _nameCtrl.text,
                    style: const TextStyle(
                        fontFamily: 'Courier',
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                if (_addressCtrl.text.isNotEmpty)
                  Text(_addressCtrl.text, style: const TextStyle(fontSize: 11)),
                const SizedBox(height: 6),
                const _PreviewDash(),
                if (_showId) _previewRow('Receipt', 'POS-XXXXXXXX'),
                if (_showDate) _previewRow('Date   ', '01/06/2026 10:00'),
                if (_showCashier) _previewRow('Cashier', 'Admin'),
                if (_showId || _showDate || _showCashier) const _PreviewDash(),
                _previewRow('Product A  x1', '5,000'),
                _previewRow('Product B  x2', '10,000'),
                const _PreviewDash(),
                _previewRow('Subtotal', '15,000'),
                const SizedBox(height: 2),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('TOTAL',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                    const Text('15,000',
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 6),
                const _PreviewDash(),
                const SizedBox(height: 4),
                Text(
                  _footerCtrl.text.isEmpty ? 'Thank you!' : _footerCtrl.text,
                  style: const TextStyle(fontSize: 12),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      );

  Widget _previewRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 11)),
            Text(value, style: const TextStyle(fontSize: 11)),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final appBar = AppBar(
      backgroundColor: AppColors.card,
      title: Text('ဘောင်ချာ စီမံခြင်း',
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
                child: Text('သိမ်းဆည်းရန်',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600))),
      ],
    );

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: appBar,
      body: LayoutBuilder(
        builder: (context, constraints) {
          // ── Tablet landscape: side-by-side ─────────────────────────────
          if (constraints.maxWidth >= 720) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left panel – all controls
                Expanded(
                  flex: 44,
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _buildStoreInfoCard(),
                      const SizedBox(height: 14),
                      _buildFooterCard(),
                      const SizedBox(height: 14),
                      _buildTogglesCard(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                Container(width: 1, color: AppColors.border),
                // Right panel – live receipt preview
                Expanded(
                  flex: 56,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('ကြိုကြည့်',
                            style: GoogleFonts.poppins(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textMedium)),
                        const SizedBox(height: 10),
                        _buildPreviewCard(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          // ── Phone / portrait: single column ────────────────────────────
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _buildStoreInfoCard(),
              const SizedBox(height: 14),
              _buildFooterCard(),
              const SizedBox(height: 14),
              _buildTogglesCard(),
              const SizedBox(height: 14),
              _buildPreviewCard(),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewDash extends StatelessWidget {
  const _PreviewDash();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: SizedBox(
          width: double.infinity,
          child: Text(
            '-' * 200,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: const TextStyle(
                fontFamily: 'Courier', fontSize: 11, color: Colors.black54),
          ),
        ),
      );
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
// Profit Analytics Page
// ─────────────────────────────────────────────────────────────────────────────

class _ProfitAnalyticsPage extends StatefulWidget {
  final PosController pos;
  const _ProfitAnalyticsPage({required this.pos});

  @override
  State<_ProfitAnalyticsPage> createState() => _ProfitAnalyticsPageState();
}

class _ProfitAnalyticsPageState extends State<_ProfitAnalyticsPage> {
  late DateTime _from;
  late DateTime _to;

  bool _loading = true;

  // Daily chart (within selected range)
  Map<DateTime, double> _dailyRevenue = {};
  Map<DateTime, double> _dailyProfit = {};

  // Monthly chart (last 12 months)
  final List<String> _monthKeys = []; // "YYYY-MM"
  Map<String, double> _monthlyRevenue = {};
  Map<String, double> _monthlyProfit = {};

  // Summary totals
  double _todayRevenue = 0, _todayProfit = 0;
  double _monthRevenue = 0, _monthProfit = 0;

  // Top products by profit
  List<Map<String, dynamic>> _topProducts = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _to = DateTime(now.year, now.month, now.day);
    _from = _to.subtract(const Duration(days: 6));
    _buildMonthKeys(now);
    _fetch();
  }

  void _buildMonthKeys(DateTime now) {
    for (int i = 11; i >= 0; i--) {
      final m = DateTime(now.year, now.month - i);
      _monthKeys.add('${m.year}-${m.month.toString().padLeft(2, '0')}');
    }
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      final snap =
          await FirebaseFirestore.instance.collection('pos_sales').get();

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final monthStart = DateTime(now.year, now.month, 1);

      // Initialise daily maps
      final Map<DateTime, double> dRev = {};
      final Map<DateTime, double> dProfit = {};
      final days = _to.difference(_from).inDays;
      for (int i = 0; i <= days; i++) {
        final d = _from.add(Duration(days: i));
        dRev[d] = 0;
        dProfit[d] = 0;
      }

      // Initialise monthly maps
      final Map<String, double> mRev = {for (final k in _monthKeys) k: 0};
      final Map<String, double> mProfit = {for (final k in _monthKeys) k: 0};

      double todayRev = 0, todayProfit = 0;
      double monthRev = 0, monthProfit = 0;

      // Top products accumulator: productName → {revenue, profit, qty}
      final Map<String, Map<String, double>> prodMap = {};

      for (final doc in snap.docs) {
        final d = doc.data();
        final isRefund = (d['type'] as String? ?? 'sale') == 'refund';

        final raw = d['createdAt'];
        DateTime? dt;
        if (raw is String) dt = DateTime.tryParse(raw);
        if (dt == null) continue;
        final day = DateTime(dt.year, dt.month, dt.day);

        final revenue = (d['total'] as num?)?.toDouble() ?? 0;
        final profit = (d['totalProfit'] as num?)?.toDouble() ?? 0;
        final sign = isRefund ? -1.0 : 1.0;

        // Daily
        if (dRev.containsKey(day)) {
          dRev[day] = (dRev[day] ?? 0) + sign * revenue;
          dProfit[day] = (dProfit[day] ?? 0) + sign * profit;
        }

        // Monthly
        final mk = '${dt.year}-${dt.month.toString().padLeft(2, '0')}';
        if (mRev.containsKey(mk)) {
          mRev[mk] = (mRev[mk] ?? 0) + sign * revenue;
          mProfit[mk] = (mProfit[mk] ?? 0) + sign * profit;
        }

        // Today summary
        if (day == today) {
          todayRev += sign * revenue;
          todayProfit += sign * profit;
        }

        // Month summary
        if (!dt.isBefore(monthStart)) {
          monthRev += sign * revenue;
          monthProfit += sign * profit;
        }

        // Per-product stats: only unwind from sales (not refunds — complex to reverse per item)
        if (!isRefund) {
          final rawItems = d['items'];
          if (rawItems is List) {
            for (final item in rawItems) {
              if (item is! Map) continue;
              final name = (item['name'] as String?) ?? 'Unknown';
              final itemProfit = (item['itemProfit'] as num?)?.toDouble() ?? 0;
              final lineTotal = (item['lineTotal'] as num?)?.toDouble() ?? 0;
              final qty = (item['qty'] as num?)?.toDouble() ?? 0;
              prodMap.putIfAbsent(
                  name, () => {'profit': 0, 'revenue': 0, 'qty': 0});
              prodMap[name]!['profit'] =
                  (prodMap[name]!['profit'] ?? 0) + itemProfit;
              prodMap[name]!['revenue'] =
                  (prodMap[name]!['revenue'] ?? 0) + lineTotal;
              prodMap[name]!['qty'] = (prodMap[name]!['qty'] ?? 0) + qty;
            }
          }
        }
      }

      // Sort top products by profit desc, take top 10
      final sorted = prodMap.entries.toList()
        ..sort((a, b) =>
            (b.value['profit'] ?? 0).compareTo(a.value['profit'] ?? 0));
      final top = sorted
          .where((e) => (e.value['profit'] ?? 0) > 0)
          .take(10)
          .map((e) => {'name': e.key, ...e.value})
          .toList();

      if (mounted) {
        setState(() {
          _dailyRevenue = dRev;
          _dailyProfit = dProfit;
          _monthlyRevenue = mRev;
          _monthlyProfit = mProfit;
          _todayRevenue = todayRev;
          _todayProfit = todayProfit;
          _monthRevenue = monthRev;
          _monthProfit = monthProfit;
          _topProducts = top;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
        _from =
            DateTime(picked.start.year, picked.start.month, picked.start.day);
        _to = DateTime(picked.end.year, picked.end.month, picked.end.day);
      });
      _fetch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final todayMargin =
        _todayRevenue > 0 ? _todayProfit / _todayRevenue * 100 : 0.0;
    final monthMargin =
        _monthRevenue > 0 ? _monthProfit / _monthRevenue * 100 : 0.0;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        title: Text('အမြတ် ခွဲခြမ်းစိတ်ဖြာ',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _fetch,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Summary grid ──────────────────────────────────────────
                _SectionHeader('Summary'),
                const SizedBox(height: 10),
                LayoutBuilder(builder: (ctx, bc) {
                  final isTablet = bc.maxWidth >= 600;
                  return GridView.count(
                    crossAxisCount: isTablet ? 4 : 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: isTablet ? 1.6 : 1.7,
                    children: [
                      _StatCard(
                        label: "Today's Profit",
                        value: fmtPrice(_todayProfit),
                        icon: Icons.trending_up_rounded,
                        color: const Color(0xFF27AE60),
                      ),
                      _StatCard(
                        label: "Today's Margin",
                        value: '${todayMargin.toStringAsFixed(1)}%',
                        icon: Icons.percent_rounded,
                        color: const Color(0xFF2980B9),
                      ),
                      _StatCard(
                        label: "Month's Profit",
                        value: fmtPrice(_monthProfit),
                        icon: Icons.calendar_month_rounded,
                        color: const Color(0xFF8E44AD),
                      ),
                      _StatCard(
                        label: "Month's Margin",
                        value: '${monthMargin.toStringAsFixed(1)}%',
                        icon: Icons.donut_large_rounded,
                        color: const Color(0xFFF39C12),
                      ),
                    ],
                  );
                }),

                const SizedBox(height: 24),

                // ── Daily profit chart ────────────────────────────────────
                _SectionHeader('နေ့စဉ် အမြတ် နှင့် ဝင်ငွေ'),
                const SizedBox(height: 10),
                _ProfitChartCard(
                  revenueData: _dailyRevenue,
                  profitData: _dailyProfit,
                  from: _from,
                  to: _to,
                  onPickRange: _pickRange,
                  labelType: 'daily',
                ),

                const SizedBox(height: 24),

                // ── Monthly profit chart ──────────────────────────────────
                _SectionHeader('Monthly Profit (Last 12 Months)'),
                const SizedBox(height: 10),
                _MonthlyProfitChart(
                  monthKeys: _monthKeys,
                  revenueData: _monthlyRevenue,
                  profitData: _monthlyProfit,
                ),

                const SizedBox(height: 24),

                // ── Top products ──────────────────────────────────────────
                _SectionHeader('Top Products by Profit'),
                const SizedBox(height: 10),
                if (_topProducts.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        'No profit data yet.\nAdd a cost price to products to track profit.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: AppColors.textMedium),
                      ),
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: _topProducts.asMap().entries.map((e) {
                        final rank = e.key + 1;
                        final p = e.value;
                        final name = p['name'] as String;
                        final profit = (p['profit'] as double?) ?? 0;
                        final revenue = (p['revenue'] as double?) ?? 0;
                        final margin =
                            revenue > 0 ? profit / revenue * 100 : 0.0;
                        final isLast = rank == _topProducts.length;
                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 12),
                              child: Row(children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: rank == 1
                                        ? const Color(0xFFFFD700)
                                        : rank == 2
                                            ? const Color(0xFFC0C0C0)
                                            : rank == 3
                                                ? const Color(0xFFCD7F32)
                                                : AppColors.bg,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Center(
                                    child: Text('$rank',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: rank <= 3
                                                ? Colors.white
                                                : AppColors.textMedium)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: GoogleFonts.poppins(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.textPrimary),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                      Text(
                                        'Revenue: ${fmtPrice(revenue)}  |  Margin: ${margin.toStringAsFixed(1)}%',
                                        style: GoogleFonts.poppins(
                                            fontSize: 11,
                                            color: AppColors.textMedium),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(fmtPrice(profit),
                                    style: GoogleFonts.poppins(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: const Color(0xFF27AE60))),
                              ]),
                            ),
                            if (!isLast)
                              Divider(
                                  height: 1,
                                  color: AppColors.bg,
                                  indent: 16,
                                  endIndent: 16),
                          ],
                        );
                      }).toList(),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ── Section Header helper ──────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Text(title,
        style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary));
  }
}

// ── Daily Profit Chart Card ────────────────────────────────────────────────────
class _ProfitChartCard extends StatelessWidget {
  final Map<DateTime, double> revenueData;
  final Map<DateTime, double> profitData;
  final DateTime from;
  final DateTime to;
  final VoidCallback onPickRange;
  final String labelType;

  const _ProfitChartCard({
    required this.revenueData,
    required this.profitData,
    required this.from,
    required this.to,
    required this.onPickRange,
    required this.labelType,
  });

  String _fmtK(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final sortedDays = revenueData.keys.toList()..sort();
    final allVals = [
      ...revenueData.values,
      ...profitData.values,
    ];
    final maxVal = allVals.fold(0.0, (a, b) => a > b ? a : b);
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
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('နေ့စဉ် အမြတ် နှင့် ဝင်ငွေ',
                      style: GoogleFonts.poppins(
                          fontSize: 13,
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
            OutlinedButton.icon(
              onPressed: onPickRange,
              icon: const Icon(Icons.date_range_rounded, size: 15),
              label: Text('ကာလ',
                  style: GoogleFonts.poppins(
                      fontSize: 12, fontWeight: FontWeight.w500)),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side:
                    BorderSide(color: AppColors.primary.withValues(alpha: 0.4)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Legend
          Row(children: [
            _LegendDot(color: AppColors.primary, label: 'ဝင်ငွေ'),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFF27AE60), label: 'အမြတ်'),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: sortedDays.isEmpty
                ? Center(
                    child: Text('ဤကာလအတွင်း ဒေတာ မရှိပါ',
                        style: GoogleFonts.poppins(
                            fontSize: 13, color: AppColors.textMedium)))
                : BarChart(
                    BarChartData(
                      maxY: yMax,
                      minY: 0,
                      barGroups: sortedDays.asMap().entries.map((e) {
                        final day = e.value;
                        final rev = revenueData[day] ?? 0;
                        final prf = profitData[day] ?? 0;
                        final barW = (260 / sortedDays.length).clamp(4.0, 16.0);
                        return BarChartGroupData(
                          x: e.key,
                          groupVertically: false,
                          barsSpace: 2,
                          barRods: [
                            BarChartRodData(
                              toY: rev,
                              width: barW,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              color: AppColors.primary.withValues(alpha: 0.7),
                            ),
                            BarChartRodData(
                              toY: prf,
                              width: barW,
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(4)),
                              color: const Color(0xFF27AE60),
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 42,
                            getTitlesWidget: (v, _) => Text(
                              _fmtK(v),
                              style: GoogleFonts.poppins(
                                  fontSize: 9, color: AppColors.textMedium),
                            ),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 28,
                            getTitlesWidget: (v, _) {
                              final idx = v.toInt();
                              if (idx < 0 || idx >= sortedDays.length) {
                                return const SizedBox.shrink();
                              }
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  DateFormat('d/M').format(sortedDays[idx]),
                                  style: GoogleFonts.poppins(
                                      fontSize: 8, color: AppColors.textMedium),
                                ),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        getDrawingHorizontalLine: (v) => FlLine(
                          color: AppColors.textMedium.withValues(alpha: 0.1),
                          strokeWidth: 1,
                        ),
                      ),
                      borderData: FlBorderData(show: false),
                      barTouchData: BarTouchData(
                        touchTooltipData: BarTouchTooltipData(
                          getTooltipItem: (group, gi, rod, ri) {
                            final day = sortedDays[group.x.toInt()];
                            final label = ri == 0 ? 'ဝင်ငွေ' : 'အမြတ်';
                            return BarTooltipItem(
                              '${DateFormat('dd MMM').format(day)}\n$label: ${fmtPrice(rod.toY)}',
                              GoogleFonts.poppins(
                                  fontSize: 11, color: Colors.white),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Monthly Profit Chart ───────────────────────────────────────────────────────
class _MonthlyProfitChart extends StatelessWidget {
  final List<String> monthKeys;
  final Map<String, double> revenueData;
  final Map<String, double> profitData;

  const _MonthlyProfitChart({
    required this.monthKeys,
    required this.revenueData,
    required this.profitData,
  });

  String _fmtK(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(0)}K';
    return v.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
    final allVals = [
      ...revenueData.values,
      ...profitData.values,
    ];
    final maxVal = allVals.fold(0.0, (a, b) => a > b ? a : b);
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
          Row(children: [
            _LegendDot(color: AppColors.primary, label: 'ဝင်ငွေ'),
            const SizedBox(width: 16),
            _LegendDot(color: const Color(0xFF27AE60), label: 'အမြတ်'),
          ]),
          const SizedBox(height: 12),
          SizedBox(
            height: 200,
            child: BarChart(
              BarChartData(
                maxY: yMax,
                minY: 0,
                barGroups: monthKeys.asMap().entries.map((e) {
                  final mk = e.value;
                  final rev = revenueData[mk] ?? 0;
                  final prf = profitData[mk] ?? 0;
                  final barW = (260 / monthKeys.length).clamp(4.0, 16.0);
                  return BarChartGroupData(
                    x: e.key,
                    groupVertically: false,
                    barsSpace: 2,
                    barRods: [
                      BarChartRodData(
                        toY: rev,
                        width: barW,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        color: AppColors.primary.withValues(alpha: 0.7),
                      ),
                      BarChartRodData(
                        toY: prf,
                        width: barW,
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4)),
                        color: const Color(0xFF27AE60),
                      ),
                    ],
                  );
                }).toList(),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (v, _) => Text(
                        _fmtK(v),
                        style: GoogleFonts.poppins(
                            fontSize: 9, color: AppColors.textMedium),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (v, _) {
                        final idx = v.toInt();
                        if (idx < 0 || idx >= monthKeys.length) {
                          return const SizedBox.shrink();
                        }
                        final parts = monthKeys[idx].split('-');
                        final month = int.tryParse(parts[1]) ?? 1;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            DateFormat('MMM').format(DateTime(2000, month)),
                            style: GoogleFonts.poppins(
                                fontSize: 8, color: AppColors.textMedium),
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (v) => FlLine(
                    color: AppColors.textMedium.withValues(alpha: 0.1),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, gi, rod, ri) {
                      final mk = monthKeys[group.x.toInt()];
                      final parts = mk.split('-');
                      final label = ri == 0 ? 'ဝင်ငွေ' : 'အမြတ်';
                      final month = int.tryParse(parts[1]) ?? 1;
                      final yr = parts[0];
                      return BarTooltipItem(
                        '${DateFormat('MMM').format(DateTime(2000, month))} $yr\n$label: ${fmtPrice(rod.toY)}',
                        GoogleFonts.poppins(fontSize: 11, color: Colors.white),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Legend dot ─────────────────────────────────────────────────────────────────
class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 4),
      Text(label,
          style:
              GoogleFonts.poppins(fontSize: 11, color: AppColors.textMedium)),
    ]);
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

// ─────────────────────────────────────────────────────────────────────────────
// Staff Management Page
// ─────────────────────────────────────────────────────────────────────────────

class _StaffManagementPage extends StatefulWidget {
  const _StaffManagementPage();

  @override
  State<_StaffManagementPage> createState() => _StaffManagementPageState();
}

class _StaffManagementPageState extends State<_StaffManagementPage> {
  final _db = FirebaseFirestore.instance;
  final _nameCtrl = TextEditingController();
  List<Map<String, dynamic>> _staff = [];
  bool _loading = true;
  bool _saving = false;

  // ── Chart ──────────────────────────────────────────────────────────────────
  String _chartFilter = 'day'; // 'day' | 'month'
  Map<String, double> _chartData = {};
  bool _chartLoading = false;

  static const _barColors = [
    Color(0xFF6A1B9A), Color(0xFF1976D2), Color(0xFF00897B),
    Color(0xFFFF8C00), Color(0xFFC62828), Color(0xFF2E7D32),
  ];

  @override
  void initState() {
    super.initState();
    _load();
    _fetchChart();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchChart() async {
    setState(() => _chartLoading = true);
    try {
      final now = DateTime.now();
      DateTime from;
      if (_chartFilter == 'day') {
        from = DateTime(now.year, now.month, now.day);
      } else {
        from = DateTime(now.year, now.month, 1);
      }
      final snap = await _db.collection('pos_sales').get();
      final Map<String, double> map = {};
      for (final doc in snap.docs) {
        final d = doc.data();
        if ((d['type'] as String? ?? 'sale') == 'refund') continue;
        final staffName = (d['staffName'] as String? ?? '').trim();
        if (staffName.isEmpty) continue;
        final raw = d['createdAt'];
        DateTime? dt;
        if (raw is String) dt = DateTime.tryParse(raw);
        if (dt == null || dt.isBefore(from)) continue;
        final amount = (d['total'] as num?)?.toDouble() ?? 0;
        map[staffName] = (map[staffName] ?? 0) + amount;
      }
      if (mounted) setState(() { _chartData = map; _chartLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _chartLoading = false);
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final snap =
          await _db.collection('pos_staff').orderBy('name').get();
      if (mounted) {
        setState(() {
          _staff = snap.docs
              .map((d) => {'id': d.id, ...d.data()})
              .toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await _db.collection('pos_staff').add({
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
      });
      _nameCtrl.clear();
      await _load();
    } catch (e) {
      _snack('မထည့်နိုင်ပါ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('ဖျက်ရန် အတည်ပြုပါ',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Text('"$name" ဖျက်မည်လား?',
            style: GoogleFonts.poppins(color: AppColors.textMedium)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('မလုပ်တော့',
                  style: GoogleFonts.poppins(color: AppColors.textMedium))),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('ဖျက်မည်',
                  style: GoogleFonts.poppins(color: AppColors.secondary))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _db.collection('pos_staff').doc(id).delete();
      await _load();
    } catch (e) {
      _snack('မဖျက်နိုင်ပါ: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(fontSize: 12)),
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        title: Text('ဝန်ထမ်းများ',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        iconTheme: IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () { _load(); _fetchChart(); }),
        ],
      ),
      body: LayoutBuilder(builder: (_, constraints) {
        final isWide = constraints.maxWidth >= 720;
        if (isWide) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(children: [
                _buildAddStaffBar(),
                _buildStaffList(),
              ]),
            ),
            VerticalDivider(
                width: 1, thickness: 1, color: AppColors.border),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildSalesChart(),
              ),
            ),
          ]);
        }
        return Column(children: [
          _buildAddStaffBar(),
          _buildSalesChart(),
          _buildStaffList(),
        ]);
      }),
    );
  }

  Widget _buildAddStaffBar() {
    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _nameCtrl,
            style: GoogleFonts.poppins(
                fontSize: 14, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'ဝန်ထမ်းအမည် ထည့်ပါ...',
              hintStyle: GoogleFonts.poppins(
                  fontSize: 13, color: AppColors.textMedium),
              filled: true,
              fillColor: AppColors.bg,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
            onSubmitted: (_) => _add(),
          ),
        ),
        const SizedBox(width: 10),
        ElevatedButton.icon(
          onPressed: _saving ? null : _add,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.add_rounded, size: 18),
          label: Text('ထည့်မည်',
              style: GoogleFonts.poppins(
                  fontSize: 13, fontWeight: FontWeight.w600)),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ]),
    );
  }

  Widget _buildStaffList() {
    return Expanded(
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _staff.isEmpty
              ? Center(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.people_outline_rounded,
                            size: 52, color: AppColors.textLight),
                        const SizedBox(height: 10),
                        Text('ဝန်ထမ်း မရှိသေးပါ',
                            style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppColors.textMedium)),
                      ]))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _staff.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _staff[i];
                    final name = s['name'] as String? ?? '';
                    final amount = _chartData[name] ?? 0.0;
                    return Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: _barColors[i % _barColors.length]
                                .withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: _barColors[i % _barColors.length]),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name,
                                  style: GoogleFonts.poppins(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary)),
                              if (amount > 0)
                                Text(
                                  '${_chartFilter == 'day' ? 'ယနေ့' : 'ဤလ'}: ${fmtPrice(amount)}',
                                  style: GoogleFonts.poppins(
                                      fontSize: 11,
                                      color: _barColors[
                                          i % _barColors.length]),
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline_rounded,
                              color: AppColors.secondary, size: 20),
                          onPressed: () => _delete(s['id'] as String, name),
                        ),
                      ]),
                    );
                  },
                ),
    );
  }

  Widget _buildSalesChart() {
    final entries = _chartData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final maxVal = entries.isEmpty
        ? 1000.0
        : entries.first.value * 1.25;

    return Container(
      color: AppColors.card,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Header + toggle
        Row(children: [
          Expanded(
            child: Text(
              _chartFilter == 'day' ? 'ယနေ့ ရောင်းချမှု' : 'ဤလ ရောင်းချမှု',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary),
            ),
          ),
          _FilterChip(
            label: 'ယနေ့',
            selected: _chartFilter == 'day',
            onTap: () {
              setState(() => _chartFilter = 'day');
              _fetchChart();
            },
          ),
          const SizedBox(width: 6),
          _FilterChip(
            label: 'ဤလ',
            selected: _chartFilter == 'month',
            onTap: () {
              setState(() => _chartFilter = 'month');
              _fetchChart();
            },
          ),
        ]),
        const SizedBox(height: 12),
        // Chart
        SizedBox(
          height: 180,
          child: _chartLoading
              ? const Center(child: CircularProgressIndicator())
              : entries.isEmpty
                  ? Center(
                      child: Text('ဤကာလ ရောင်းချမှု မရှိပါ',
                          style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: AppColors.textMedium)))
                  : BarChart(
                      BarChartData(
                        maxY: maxVal,
                        minY: 0,
                        barGroups: entries.asMap().entries.map((e) {
                          final idx = e.key;
                          final color =
                              _barColors[idx % _barColors.length];
                          return BarChartGroupData(
                            x: idx,
                            barRods: [
                              BarChartRodData(
                                toY: e.value.value,
                                width: (220 / entries.length)
                                    .clamp(12.0, 40.0),
                                borderRadius:
                                    const BorderRadius.vertical(
                                        top: Radius.circular(6)),
                                color: color,
                              ),
                            ],
                          );
                        }).toList(),
                        titlesData: FlTitlesData(
                          topTitles: const AxisTitles(
                              sideTitles:
                                  SideTitles(showTitles: false)),
                          rightTitles: const AxisTitles(
                              sideTitles:
                                  SideTitles(showTitles: false)),
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 44,
                              interval: maxVal / 4,
                              getTitlesWidget: (v, _) {
                                if (v == 0) {
                                  return const SizedBox.shrink();
                                }
                                final k = v >= 1000000
                                    ? '${(v / 1000000).toStringAsFixed(1)}M'
                                    : v >= 1000
                                        ? '${(v / 1000).toStringAsFixed(0)}K'
                                        : v.toStringAsFixed(0);
                                return Text(k,
                                    style: GoogleFonts.poppins(
                                        fontSize: 9,
                                        color: AppColors.textMedium));
                              },
                            ),
                          ),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 28,
                              getTitlesWidget: (v, _) {
                                final i = v.toInt();
                                if (i >= entries.length) {
                                  return const SizedBox.shrink();
                                }
                                final name = entries[i].key;
                                final short = name.length > 6
                                    ? name.substring(0, 6)
                                    : name;
                                return Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(short,
                                      style: GoogleFonts.poppins(
                                          fontSize: 9,
                                          color: AppColors.textMedium)),
                                );
                              },
                            ),
                          ),
                        ),
                        gridData: FlGridData(
                          drawVerticalLine: false,
                          horizontalInterval: maxVal / 4,
                          getDrawingHorizontalLine: (_) => FlLine(
                            color:
                                AppColors.border.withValues(alpha: 0.4),
                            strokeWidth: 0.5,
                          ),
                        ),
                        borderData: FlBorderData(show: false),
                        barTouchData: BarTouchData(
                          touchTooltipData: BarTouchTooltipData(
                            getTooltipColor: (_) => AppColors.textPrimary,
                            tooltipRoundedRadius: 8,
                            getTooltipItem: (group, _, rod, __) {
                              final name = entries[group.x].key;
                              return BarTooltipItem(
                                '$name\n${fmtPrice(rod.toY)}',
                                GoogleFonts.poppins(
                                    fontSize: 10,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : AppColors.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.primary,
          ),
        ),
      ),
    );
  }
}

// ── Camera barcode scanner sheet ──────────────────────────────────────────────
class _BarcodeScanSheet extends StatefulWidget {
  const _BarcodeScanSheet();

  @override
  State<_BarcodeScanSheet> createState() => _BarcodeScanSheetState();
}

class _BarcodeScanSheetState extends State<_BarcodeScanSheet> {
  final MobileScannerController _ctrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
  );
  bool _scanned = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _scanned = true;
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Container(
      height: size.height * 0.65,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle + header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: Text(
                    'ဘားကုဒ် စကန်ဖတ်ရန်',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Camera preview with viewfinder overlay
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(20)),
                  child: MobileScanner(
                    controller: _ctrl,
                    onDetect: _onDetect,
                  ),
                ),
                // Dimmed overlay with a transparent scan window
                IgnorePointer(
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: _ScanOverlayPainter(),
                  ),
                ),
                // Corner frame
                Center(
                  child: Container(
                    width: 220,
                    height: 120,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 2.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                // Hint text
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Text(
                    'ဘားကုဒ်ကို အကွက်အတွင်း ထားပါ',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const holeW = 220.0;
    const holeH = 120.0;
    final cx = size.width / 2;
    final cy = size.height / 2;
    final hole = Rect.fromCenter(
        center: Offset(cx, cy), width: holeW, height: holeH);

    final paint = Paint()..color = Colors.black.withValues(alpha: 0.55);
    final full = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutout = Path()
      ..addRRect(RRect.fromRectAndRadius(hole, const Radius.circular(12)));
    canvas.drawPath(
        Path.combine(PathOperation.difference, full, cutout), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
