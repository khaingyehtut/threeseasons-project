import 'dart:async';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../services/bt_printer_service.dart';
import '../../services/barcode_server_service.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/locale_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../models/notification_model.dart';
import '../../models/payment_model.dart';
import '../../services/payment_service.dart';
import '../../core/constants.dart';
import '../../core/responsive.dart';
import '../../core/navigation.dart';
import '../../core/theme.dart';
import '../../models/category_model.dart';
import '../../models/order_model.dart';
import '../../models/product_model.dart';
import '../../models/user_model.dart';
import '../../models/banner_model.dart';
import '../../services/auth_service.dart';
import '../../services/banner_service.dart';
import '../../services/chat_service.dart';
import '../../services/notification_service.dart';
import '../../services/upload_service.dart';
import '../../models/announcement_model.dart';
import '../../services/announcement_service.dart';
import '../chat/chat_screen.dart';
import 'pos_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Firestore helper — converts a doc to a plain Map, Timestamps → ISO strings
// ─────────────────────────────────────────────────────────────────────────────
Map<String, dynamic> _docToMap(DocumentSnapshot doc) {
  final raw = doc.data() as Map<String, dynamic>? ?? {};
  final result = <String, dynamic>{'id': doc.id};
  raw.forEach((k, v) {
    result[k] = v is Timestamp ? v.toDate().toIso8601String() : v;
  });
  return result;
}

// ─────────────────────────────────────────────────────────────────────────────
// Root: AdminDashboard (6 tabs)
// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _index = 0;

  static final _pages = [
    const _DashboardTab(),
    const _AdminManageTab(),
    const PosScreen(),
    const _AdminSettingsTab(),
  ];

  @override
  void initState() {
    super.initState();
    // Load admin's saved language preference (separate from user locale)
    Get.find<LocaleController>().loadAdminLocale();
  }

  static const _navItems = [
    (Icons.dashboard_rounded, Icons.dashboard_outlined, 'Dashboard'),
    (Icons.grid_view_rounded, Icons.grid_view_outlined, 'Manage'),
    (Icons.point_of_sale_rounded, Icons.point_of_sale_outlined, 'POS'),
    (Icons.settings_rounded, Icons.settings_outlined, 'Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 20,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(_navItems.length, (i) {
                final (filled, outline, label) = _navItems[i];
                final selected = _index == i;
                return GestureDetector(
                  onTap: () => setState(() => _index = i),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                    padding: EdgeInsets.symmetric(
                      horizontal: selected ? 20 : 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.gradient1 : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          selected ? filled : outline,
                          color: selected ? Colors.white : AppColors.textMedium,
                          size: 22,
                        ),
                        if (selected) ...[
                          const SizedBox(width: 8),
                          Text(
                            label,
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. Dashboard Tab
// ─────────────────────────────────────────────────────────────────────────────
class _DashboardTab extends StatefulWidget {
  const _DashboardTab();

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  bool _isLoading = true;
  String? _error;
  int totalUsers = 0;
  int totalProducts = 0;
  int totalOrders = 0;
  int pendingOrders = 0;
  double totalRevenue = 0.0;
  List<Map<String, dynamic>> recentOrders = [];
  List<Map<String, dynamic>> topProducts = [];

  // POS stats
  double todayPosSales = 0.0;
  double monthPosSales = 0.0;
  int todayPosCount = 0;
  int monthPosCount = 0;
  List<Map<String, dynamic>> recentPosSales = [];

  StreamSubscription? _ordersSub;
  StreamSubscription? _productsSub;
  StreamSubscription? _usersSub;
  StreamSubscription? _posSub;

  @override
  void initState() {
    super.initState();
    _subscribeToStats();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _productsSub?.cancel();
    _usersSub?.cancel();
    _posSub?.cancel();
    super.dispose();
  }

  void _subscribeToStats() {
    if (mounted)
      setState(() {
        _isLoading = true;
        _error = null;
      });
    final db = FirebaseFirestore.instance;

    _ordersSub?.cancel();
    _ordersSub = db
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      double revenue = 0;
      int pending = 0;
      final orderMaps = <Map<String, dynamic>>[];
      for (final doc in snap.docs) {
        final m = _docToMap(doc);
        revenue += _parseDouble(m['totalPrice']);
        if ((m['status'] ?? '').toString().toLowerCase() == 'pending')
          pending++;
        orderMaps.add(m);
      }
      if (mounted) {
        setState(() {
          totalOrders = snap.docs.length;
          pendingOrders = pending;
          totalRevenue = revenue;
          recentOrders = orderMaps.take(5).toList();
          _isLoading = false;
        });
      }
    }, onError: (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
    });

    _productsSub?.cancel();
    _productsSub = db.collection('products').snapshots().listen((snap) {
      final productMaps = snap.docs.map(_docToMap).toList()
        ..sort((a, b) => _parseInt(b['sold']).compareTo(_parseInt(a['sold'])));
      if (mounted) {
        setState(() {
          totalProducts = snap.docs.length;
          topProducts = productMaps.take(5).toList();
        });
      }
    });

    _usersSub?.cancel();
    _usersSub = db.collection('users').snapshots().listen((snap) {
      if (mounted) {
        setState(() {
          totalUsers = snap.docs
              .where((d) => (d.data()['role'] ?? 'user') == 'user')
              .length;
        });
      }
    });

    // POS sales — today + month totals
    _posSub?.cancel();
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final monthStart = DateTime(now.year, now.month, 1);

    _posSub = db
        .collection('pos_sales')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      double todaySales = 0;
      double monthSales = 0;
      int todayCount = 0;
      int monthCount = 0;
      final recent = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final m = _docToMap(doc);
        // Skip refund records
        if ((m['type'] ?? '') == 'refund') continue;
        final dateStr = (m['createdAt'] ?? '').toString();
        final date = DateTime.tryParse(dateStr);
        if (date == null) continue;
        final total = _parseDouble(m['total']);
        if (!date.isBefore(monthStart)) {
          monthSales += total;
          monthCount++;
          if (!date.isBefore(todayStart)) {
            todaySales += total;
            todayCount++;
          }
        }
        if (recent.length < 5) recent.add(m);
      }

      if (mounted) {
        setState(() {
          todayPosSales = todaySales;
          monthPosSales = monthSales;
          todayPosCount = todayCount;
          monthPosCount = monthCount;
          recentPosSales = recent;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = Get.find<AuthController>().user.value;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: () async => _subscribeToStats(),
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(user)),
            if (_isLoading)
              const SliverFillRemaining(
                  child: Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary)))
            else if (_error != null)
              SliverFillRemaining(child: _buildError())
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildStatsGrid(context),
                      const SizedBox(height: 28),
                      _buildPosSummary(context),
                      const SizedBox(height: 28),
                      _sectionTitle('Recent Orders'),
                      const SizedBox(height: 12),
                      _buildRecentOrders(),
                      const SizedBox(height: 24),
                      _sectionTitle('Top Products'),
                      const SizedBox(height: 12),
                      _buildTopProducts(),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(UserModel? user) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.surface, AppColors.bg],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Panel',
                        style: GoogleFonts.poppins(
                            color: AppColors.textMedium,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 2),
                    Text('Welcome, ${user?.name ?? 'Admin'}',
                        style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontSize: 22,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                          gradient: AppColors.gradient1,
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('TSfootwear Admin',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  gradient: AppColors.gradient1,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.4),
                        blurRadius: 16,
                        offset: const Offset(0, 6))
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  (user?.name ?? 'A').substring(0, 1).toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              // Notification bell — shows unread order_placed badge for admin
              Obx(() {
                final unread =
                    Get.find<NotificationController>().unreadCount.value;
                return GestureDetector(
                  onTap: () => pushTo('/notifications'),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: AppColors.primary.withValues(alpha: 0.3)),
                        ),
                        alignment: Alignment.center,
                        child: Icon(Icons.notifications_rounded,
                            color: AppColors.primary, size: 18),
                      ),
                      if (unread > 0)
                        Positioned(
                          top: -3,
                          right: -3,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            constraints: const BoxConstraints(
                                minWidth: 16, minHeight: 16),
                            decoration: const BoxDecoration(
                                color: Color(0xFFFF4757),
                                shape: BoxShape.circle),
                            child: Text(
                              unread > 9 ? '9+' : '$unread',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  height: 1),
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
              const SizedBox(width: 8),
              Obx(() {
                final isDark = Get.find<LocaleController>().isDark.value;
                return GestureDetector(
                  onTap: () => Get.find<LocaleController>().toggleTheme(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      isDark
                          ? Icons.dark_mode_rounded
                          : Icons.light_mode_rounded,
                      color: AppColors.warning,
                      size: 18,
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => _logout(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  alignment: Alignment.center,
                  child: Icon(Icons.logout_rounded,
                      color: AppColors.error, size: 18),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to logout?',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: AppColors.textMedium))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Logout',
                  style: GoogleFonts.poppins(
                      color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await Get.find<AuthController>().logout();
    goTo('/login');
  }

  Widget _buildStatsGrid(BuildContext context) {
    final stats = [
      _StatData(
          label: 'Users',
          value: totalUsers.toString(),
          icon: Icons.people_rounded,
          gradient: AppColors.gradient1,
          trend: '',
          up: true),
      _StatData(
          label: 'Products',
          value: totalProducts.toString(),
          icon: Icons.inventory_2_rounded,
          gradient: AppColors.gradient3,
          trend: '',
          up: true),
      _StatData(
          label: 'Pending Orders',
          value: pendingOrders.toString(),
          icon: Icons.pending_actions_rounded,
          gradient: AppColors.gradient2,
          trend: '',
          up: true),
      _StatData(
        label: 'Revenue',
        value: 'Ks ${_formatNumber(totalRevenue)}',
        icon: Icons.attach_money_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFFFF9F43), Color(0xFFFFCA7E)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        trend: '',
        up: true,
      ),
      _StatData(
        label: 'Today POS',
        value: 'Ks ${_formatNumber(todayPosSales)}',
        icon: Icons.point_of_sale_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF00B894), Color(0xFF55EFC4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        trend: '$todayPosCount sales',
        up: true,
      ),
      _StatData(
        label: 'Month POS',
        value: 'Ks ${_formatNumber(monthPosSales)}',
        icon: Icons.calendar_month_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF9C8FFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        trend: '$monthPosCount sales',
        up: true,
      ),
    ];
    return GridView.count(
      crossAxisCount: Responsive.isDesktop(context)
          ? 5
          : Responsive.isTablet(context)
              ? 5
              : 2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.4,
      children: stats.map((s) => _StatCard(data: s)).toList(),
    );
  }

  Widget _buildPosSummary(BuildContext context) {
    final now = DateTime.now();
    final month = DateFormat('MMMM yyyy').format(now);
    final today = DateFormat('dd MMM yyyy').format(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header row ────────────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionTitle('POS Sales'),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(month,
                  style: GoogleFonts.poppins(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary)),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── Today vs Month cards ──────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _PosSummaryCard(
                label: 'Today',
                subtitle: today,
                amount: todayPosSales,
                count: todayPosCount,
                color: const Color(0xFF00B894),
                icon: Icons.today_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _PosSummaryCard(
                label: 'This Month',
                subtitle: month,
                amount: monthPosSales,
                count: monthPosCount,
                color: AppColors.primary,
                icon: Icons.calendar_month_rounded,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Recent POS transactions ───────────────────────────────────────
        if (recentPosSales.isNotEmpty) ...[
          Text('Recent POS Transactions',
              style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMedium)),
          const SizedBox(height: 8),
          ...recentPosSales.map((sale) => _buildPosSaleRow(sale)),
        ],
      ],
    );
  }

  Widget _buildPosSaleRow(Map<String, dynamic> sale) {
    final id = (sale['id'] ?? '').toString();
    final total = _parseDouble(sale['total']);
    final method = (sale['paymentMethod'] ?? 'cash').toString().toUpperCase();
    final cashier = (sale['cashierName'] ?? '').toString();
    final dateStr = (sale['createdAt'] ?? '').toString();
    final date = DateTime.tryParse(dateStr);
    final timeStr = date != null ? DateFormat('HH:mm').format(date) : '';
    final isRefund = (sale['type'] ?? '') == 'refund';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isRefund
                  ? AppColors.secondary.withValues(alpha: 0.1)
                  : const Color(0xFF00B894).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isRefund ? Icons.undo_rounded : Icons.point_of_sale_rounded,
              size: 16,
              color: isRefund ? AppColors.secondary : const Color(0xFF00B894),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  id.length > 20 ? '...${id.substring(id.length - 12)}' : id,
                  style: GoogleFonts.poppins(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary),
                ),
                Text(
                  '$cashier · $method · $timeStr',
                  style: GoogleFonts.poppins(
                      fontSize: 10, color: AppColors.textMedium),
                ),
              ],
            ),
          ),
          Text(
            fmtPrice(total),
            style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isRefund ? AppColors.secondary : AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.poppins(
          color: AppColors.textPrimary,
          fontSize: 16,
          fontWeight: FontWeight.w600));

  Widget _buildRecentOrders() {
    if (recentOrders.isEmpty) {
      return const _EmptyState(
          icon: Icons.receipt_long_outlined, label: 'No recent orders');
    }
    return Column(children: recentOrders.map(_buildRecentOrderItem).toList());
  }

  Widget _buildRecentOrderItem(Map<String, dynamic> order) {
    final status = order['status'] ?? 'pending';
    final orderNum =
        order['orderNumber'] ?? order['id']?.toString().substring(0, 8) ?? '';
    final total = _parseDouble(order['totalPrice']);
    final rawAddr = order['shippingAddress'];
    final customer =
        (rawAddr is Map ? rawAddr['name'] : null)?.toString() ?? '';

    Color statusColor;
    switch (status.toLowerCase()) {
      case 'delivered':
        statusColor = AppColors.success;
        break;
      case 'shipped':
        statusColor = const Color(0xFF8B5CF6);
        break;
      case 'cancelled':
        statusColor = AppColors.error;
        break;
      case 'processing':
        statusColor = AppColors.primary;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          children: [
            // Colored left accent bar — fixed 4px width
            Container(width: 4, color: statusColor),
            // Expanded bounds the inner Row so Expanded children work
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.receipt_rounded,
                          color: statusColor, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text('#$orderNum',
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                          if (customer.isNotEmpty)
                            Text(customer,
                                style: GoogleFonts.poppins(
                                    color: AppColors.textMedium, fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis)
                          else
                            Text(fmtPrice(total),
                                style: GoogleFonts.poppins(
                                    color: AppColors.textMedium, fontSize: 11)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _StatusChip(status: status),
                        const SizedBox(height: 4),
                        Text(fmtPrice(total),
                            style: GoogleFonts.poppins(
                                color: AppColors.textPrimary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProducts() {
    if (topProducts.isEmpty) {
      return const _EmptyState(
          icon: Icons.inventory_2_outlined, label: 'No product data');
    }
    return Column(children: topProducts.map(_buildTopProductItem).toList());
  }

  Widget _buildTopProductItem(Map<String, dynamic> p) {
    final name = p['name'] ?? 'Unknown';
    final sold = _parseInt(p['sold']);
    final price = _parseDouble(p['price']);
    final thumbnail = UploadService.fixUrl(p['thumbnail'] ?? '');
    final rank = topProducts.indexOf(p) + 1;
    final maxSold =
        topProducts.isNotEmpty ? _parseInt(topProducts.first['sold']) : 1;
    final progress = maxSold > 0 ? (sold / maxSold).clamp(0.0, 1.0) : 0.0;

    final rankColors = [
      const Color(0xFFFFB800),
      const Color(0xFF9CA3AF),
      const Color(0xFFCD7C2F),
    ];
    final rankColor = rank <= 3 ? rankColors[rank - 1] : AppColors.textLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Rank badge
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: rankColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '#$rank',
              style: GoogleFonts.poppins(
                color: rankColor,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: thumbnail.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: thumbnail,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        const _ProductPlaceholder(size: 44))
                : const _ProductPlaceholder(size: 44),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: AppColors.border,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.primary),
                    minHeight: 4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(fmtPrice(price),
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
            Text('$sold sold',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 11)),
          ]),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(
              onPressed: _subscribeToStats, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. Products Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminProductsTab extends StatefulWidget {
  const _AdminProductsTab();

  @override
  State<_AdminProductsTab> createState() => _AdminProductsTabState();
}

class _AdminProductsTabState extends State<_AdminProductsTab> {
  bool _isLoading = true;
  String? _error;
  List<ProductModel> _products = [];
  List<ProductModel> _filtered = [];
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap =
          await FirebaseFirestore.instance.collection('products').get();
      _products = snap.docs.map((doc) {
        final m = _docToMap(doc);
        // Ensure category is a proper Map
        if (m['category'] is Map) {
          m['category'] = Map<String, dynamic>.from(m['category'] as Map);
        }
        return ProductModel.fromJson(m);
      }).toList();
      _products.sort((a, b) => a.name.compareTo(b.name));
      _applyFilter(_searchCtrl.text);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? List.from(_products)
          : _products
              .where((p) =>
                  p.name.toLowerCase().contains(query) ||
                  (p.category?.name ?? '').toLowerCase().contains(query))
              .toList();
    });
  }

  Future<void> _delete(String id) async {
    final ok = await _showConfirm(
        context, 'Delete Product', 'This action cannot be undone.');
    if (!ok) return;
    try {
      final product = _products.firstWhereOrNull((p) => p.id == id);
      await FirebaseFirestore.instance.collection('products').doc(id).delete();

      // Delete image file from server
      if (product != null && product.firstImage.isNotEmpty) {
        final token = await AuthService().getIdToken();
        if (token != null) {
          await UploadService().deleteImage(product.firstImage, token);
        }
      }

      _products.removeWhere((p) => p.id == id);
      _applyFilter(_searchCtrl.text);
      if (mounted) _snack('Product deleted', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Products',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textMedium),
              onPressed: _fetch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admin_products_fab',
        onPressed: () => _showProductSheet(context, null, _fetch),
        backgroundColor: AppColors.primary,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _applyFilter,
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search products…',
          prefixIcon: Icon(Icons.search_rounded, color: AppColors.textMedium),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: AppColors.textMedium),
                  onPressed: () {
                    _searchCtrl.clear();
                    _applyFilter('');
                  })
              : null,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
        ]),
      );
    }
    if (_filtered.isEmpty) {
      return const _EmptyState(
          icon: Icons.inventory_2_outlined, label: 'No products found');
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _ProductListItem(
          product: _filtered[i],
          onEdit: () => _showProductSheet(context, _filtered[i], _fetch),
          onDelete: () => _delete(_filtered[i].id),
        ),
      ),
    );
  }
}

class _ProductListItem extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _ProductListItem(
      {required this.product, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.firstImage.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: UploadService.fixUrl(product.firstImage),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const _ProductPlaceholder())
                : const _ProductPlaceholder(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product.name,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (product.category != null && product.category!.name.isNotEmpty)
                Text(product.category!.name,
                    style: GoogleFonts.poppins(
                        color: AppColors.textMedium, fontSize: 11)),
              const SizedBox(height: 6),
              Row(children: [
                Text('${fmtPrice(product.price)}',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: product.isInStock
                        ? AppColors.success.withValues(alpha: 0.15)
                        : AppColors.error.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    product.isInStock
                        ? 'Stock: ${product.stock}'
                        : 'Out of stock',
                    style: GoogleFonts.poppins(
                        color: product.isInStock
                            ? AppColors.success
                            : AppColors.error,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ]),
            ]),
          ),
          Column(children: [
            IconButton(
                icon: Icon(Icons.edit_rounded,
                    color: AppColors.primary, size: 20),
                onPressed: onEdit),
            IconButton(
                icon: Icon(Icons.delete_rounded,
                    color: AppColors.error, size: 20),
                onPressed: onDelete),
          ]),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Product Form Sheet
// ─────────────────────────────────────────────────────────────────────────────
void _showProductSheet(
    BuildContext context, ProductModel? product, VoidCallback onSaved) {
  Navigator.of(context).push(MaterialPageRoute(
    builder: (_) => _ProductFormSheet(product: product, onSaved: onSaved),
  ));
}

class _ProductFormSheet extends StatefulWidget {
  final ProductModel? product;
  final VoidCallback onSaved;
  const _ProductFormSheet({this.product, required this.onSaved});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _barcodeCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _cmpCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  final _discCtrl = TextEditingController();
  final _sizesCtrl = TextEditingController();
  final _colorsCtrl = TextEditingController();
  final _manualUrlCtrl = TextEditingController();
  bool _isFeatured = false;
  bool _isLoading = false;
  bool _showManualUrl = false;

  // Image
  File? _imageFile;
  Uint8List?
      _imageBytes; // bytes read immediately at pick time — survives cache eviction
  String _imageUrl = '';
  bool _isUploadingImage = false;

  String? _selectedCategoryId;
  List<CategoryModel> _categories = [];

  @override
  void initState() {
    super.initState();
    _loadCategories();
    final p = widget.product;
    if (p != null) {
      _nameCtrl.text = p.name;
      _barcodeCtrl.text = p.barcode;
      _descCtrl.text = p.description;
      _priceCtrl.text = p.price.toString();
      _cmpCtrl.text = p.comparePrice.toString();
      _stockCtrl.text = p.stock.toString();
      _discCtrl.text = p.discount.toString();
      _sizesCtrl.text = p.sizes.join(', ');
      _colorsCtrl.text = p.colors.join(', ');
      _isFeatured = p.isFeatured;
      _imageUrl = p.firstImage;
      _manualUrlCtrl.text = p.firstImage;
      _selectedCategoryId = p.category?.id;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _cmpCtrl.dispose();
    _stockCtrl.dispose();
    _discCtrl.dispose();
    _sizesCtrl.dispose();
    _colorsCtrl.dispose();
    _manualUrlCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('categories').get();
      setState(() {
        _categories = snap.docs.map((doc) {
          final m = _docToMap(doc);
          return CategoryModel.fromJson(m);
        }).toList();
      });
    } catch (_) {}
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: source, imageQuality: 80, maxWidth: 1200);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _imageFile = kIsWeb ? null : File(picked.path);
      _imageBytes = bytes;
      _imageUrl = '';
    });
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 5),
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instance;

      // Upload image on submit if a new file was picked
      String finalImageUrl =
          _imageUrl.isNotEmpty ? _imageUrl : _manualUrlCtrl.text.trim();
      if (_imageBytes != null) {
        setState(() => _isUploadingImage = true);
        try {
          final token = await AuthService().getIdToken();
          if (token == null) throw Exception('Not authenticated');

          // Delete old image from server if replacing
          final oldUrl = widget.product?.firstImage ?? '';
          if (oldUrl.isNotEmpty) {
            await UploadService().deleteImage(oldUrl, token);
          }

          final fileName = _imageFile?.path.split('/').last ?? 'image.jpg';
          finalImageUrl = await UploadService()
              .uploadImageBytes(_imageBytes!, fileName, token);
        } finally {
          if (mounted) setState(() => _isUploadingImage = false);
        }
      }

      CategoryModel? cat;
      if (_selectedCategoryId != null) {
        try {
          cat = _categories.firstWhere((c) => c.id == _selectedCategoryId);
        } catch (_) {}
      }

      final sizes = _sizesCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final colors = _colorsCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final payload = <String, dynamic>{
        'name': _nameCtrl.text.trim(),
        'barcode': _barcodeCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.tryParse(_priceCtrl.text) ?? 0.0,
        'comparePrice': double.tryParse(_cmpCtrl.text) ?? 0.0,
        'stock': int.tryParse(_stockCtrl.text) ?? 0,
        'discount': int.tryParse(_discCtrl.text) ?? 0,
        'isFeatured': _isFeatured,
        'isActive': true,
        'thumbnail': finalImageUrl,
        'images': finalImageUrl.isNotEmpty ? [finalImageUrl] : [],
        'sizes': sizes,
        'colors': colors,
        'tags': [],
        'brand': '',
        'rating': widget.product?.rating ?? 0.0,
        'numReviews': widget.product?.numReviews ?? 0,
        // Flat categoryId for Firestore queries + nested map for display
        'categoryId': cat?.id ?? '',
        if (cat != null)
          'category': {'id': cat.id, 'name': cat.name, 'slug': cat.slug},
      };

      if (widget.product == null) {
        payload['sold'] = 0;
        payload['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('products').add(payload);
      } else {
        await db.collection('products').doc(widget.product!.id).update(payload);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: AppColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.product == null ? 'Add Product' : 'Edit Product',
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isTablet = constraints.maxWidth >= 700;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Form(
                  key: _formKey,
                  child: isTablet ? _buildTabletLayout() : _buildPhoneLayout(),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildFormFields() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field(
              ctrl: _nameCtrl,
              label: 'Product Name *',
              validator: (v) => (v == null || v.isEmpty) ? 'Required' : null),
          const SizedBox(height: 14),
          _BarcodeInputField(ctrl: _barcodeCtrl),
          const SizedBox(height: 14),
          _Field(ctrl: _descCtrl, label: 'Description', maxLines: 3),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _Field(
                  ctrl: _priceCtrl,
                  label: 'Price *',
                  keyboardType: TextInputType.number,
                  validator: (v) =>
                      (v == null || v.isEmpty) ? 'Required' : null),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                  ctrl: _cmpCtrl,
                  label: 'Compare Price',
                  keyboardType: TextInputType.number),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _Field(
                  ctrl: _stockCtrl,
                  label: 'Stock',
                  keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _Field(
                  ctrl: _discCtrl,
                  label: 'Discount %',
                  keyboardType: TextInputType.number),
            ),
          ]),
          const SizedBox(height: 14),
          _buildCategoryDropdown(),
          const SizedBox(height: 14),
          _Field(
              ctrl: _sizesCtrl,
              label: 'Sizes',
              hint: 'e.g. S,M,L,XL or 31,32,33,34'),
          const SizedBox(height: 14),
          _Field(
              ctrl: _colorsCtrl, label: 'Colors', hint: 'e.g. Red,Blue,Green'),
          const SizedBox(height: 14),
          _buildFeaturedToggle(),
        ],
      );

  Widget _buildSubmitButton() => SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: (_isLoading || _isUploadingImage) ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : Text(widget.product == null ? 'Add Product' : 'Update Product'),
        ),
      );

  // ── Phone: single column ───────────────────────────────────────────────────
  Widget _buildPhoneLayout() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          _buildImagePicker(),
          const SizedBox(height: 16),
          _buildFormFields(),
          const SizedBox(height: 24),
          _buildSubmitButton(),
          const SizedBox(height: 20),
        ],
      );

  // ── Tablet: image left, fields right ─────────────────────────────────────
  Widget _buildTabletLayout() => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: image picker (fixed width)
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildImagePicker(),
              ],
            ),
          ),
          const SizedBox(width: 28),
          // Right: all form fields
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                _buildFormFields(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      );

  Widget _buildImagePicker() {
    // Effective preview URL: auto-upload wins, manual URL is fallback
    final previewUrl = UploadService.fixUrl(
        _imageUrl.isNotEmpty ? _imageUrl : _manualUrlCtrl.text.trim());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Product Image',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            // Toggle between file-pick and manual URL
            TextButton.icon(
              onPressed: () => setState(() => _showManualUrl = !_showManualUrl),
              icon: Icon(
                _showManualUrl ? Icons.upload_rounded : Icons.link_rounded,
                size: 16,
                color: AppColors.primary,
              ),
              label: Text(
                _showManualUrl ? 'Pick file' : 'Paste URL',
                style:
                    GoogleFonts.poppins(color: AppColors.primary, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        if (_showManualUrl) ...[
          // ── Manual URL input ──────────────────────────────
          TextField(
            controller: _manualUrlCtrl,
            style:
                GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'https://example.com/image.jpg',
              prefixIcon: Icon(Icons.link_rounded,
                  color: AppColors.textMedium, size: 18),
              suffixIcon: _manualUrlCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.clear_rounded,
                          color: AppColors.textMedium, size: 18),
                      onPressed: () {
                        _manualUrlCtrl.clear();
                        setState(() {});
                      })
                  : null,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 10),
          // Preview of manually entered URL
          if (previewUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: previewUrl,
                width: double.infinity,
                height: 140,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Container(
                  height: 60,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.error)),
                  child: Text('Could not load image',
                      style: GoogleFonts.poppins(
                          color: AppColors.error, fontSize: 12)),
                ),
              ),
            ),
        ] else ...[
          // ── File picker ───────────────────────────────────
          if (_imageBytes != null)
            // Use in-memory bytes — works even if the cache file was evicted
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.memory(_imageBytes!,
                  width: double.infinity, height: 160, fit: BoxFit.cover),
            )
          else if (previewUrl.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: previewUrl,
                width: double.infinity,
                height: 160,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _imagePlaceholderBox(),
              ),
            )
          else
            _imagePlaceholderBox(),

          if (_isUploadingImage) ...[
            const SizedBox(height: 6),
            LinearProgressIndicator(
                color: AppColors.primary, backgroundColor: AppColors.surface),
            const SizedBox(height: 4),
            Text('Uploading to server…',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 11)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary)),
                icon: Icon(Icons.photo_library_rounded, size: 18),
                label: const Text('Gallery'),
                onPressed: _isUploadingImage
                    ? null
                    : () => _pickImage(ImageSource.gallery),
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.accent,
                      side: BorderSide(color: AppColors.accent)),
                  icon: Icon(Icons.camera_alt_rounded, size: 18),
                  label: const Text('Camera'),
                  onPressed: _isUploadingImage
                      ? null
                      : () => _pickImage(ImageSource.camera),
                ),
              ),
            ],
          ]),
        ],
      ],
    );
  }

  Widget _imagePlaceholderBox() {
    return Container(
      width: double.infinity,
      height: 120,
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add_photo_alternate_outlined,
            color: AppColors.textMedium, size: 40),
        const SizedBox(height: 6),
        Text('Pick image from gallery or camera',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 11)),
      ]),
    );
  }

  Widget _buildCategoryDropdown() {
    // Guard: only use the stored ID if it's already in the loaded categories list.
    // Avoids assertion when the sheet first renders before _loadCategories() completes.
    final safeValue = _categories.any((c) => c.id == _selectedCategoryId)
        ? _selectedCategoryId
        : null;

    return Container(
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border)),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeValue,
          hint: Text('Select Category',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 14)),
          isExpanded: true,
          dropdownColor: AppColors.surface,
          style:
              GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
          icon: Icon(Icons.keyboard_arrow_down_rounded,
              color: AppColors.textMedium),
          items: [
            const DropdownMenuItem<String>(
                value: null,
                child: Text('No Category',
                    style: TextStyle(color: AppColors.textMedium))),
            ..._categories
                .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))),
          ],
          onChanged: (v) => setState(() => _selectedCategoryId = v),
        ),
      ),
    );
  }

  Widget _buildFeaturedToggle() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text('Featured Product',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary, fontSize: 14)),
        Switch(
          value: _isFeatured,
          onChanged: (v) => setState(() => _isFeatured = v),
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. Orders Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminOrdersTab extends StatefulWidget {
  const _AdminOrdersTab();

  @override
  State<_AdminOrdersTab> createState() => _AdminOrdersTabState();
}

class _AdminOrdersTabState extends State<_AdminOrdersTab> {
  bool _isLoading = true;
  String? _error;
  List<OrderModel> _orders = [];
  List<OrderModel> _filtered = [];
  String _selectedStatus = 'all';
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();
  StreamSubscription? _ordersSub;

  static const _statuses = [
    'all',
    'pending',
    'processing',
    'shipped',
    'delivered',
    'cancelled'
  ];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    _ordersSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _subscribe() {
    if (mounted)
      setState(() {
        _isLoading = true;
        _error = null;
      });
    _ordersSub?.cancel();
    _ordersSub = FirebaseFirestore.instance
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snap) {
      _orders =
          snap.docs.map((doc) => OrderModel.fromJson(_docToMap(doc))).toList();
      _applyFilter();
      if (mounted) setState(() => _isLoading = false);
    }, onError: (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
    });
  }

  void _applyFilter() {
    final q = _searchQuery.toLowerCase().trim();
    setState(() {
      _filtered = _orders.where((o) {
        final matchStatus = _selectedStatus == 'all' ||
            o.status.toLowerCase() == _selectedStatus.toLowerCase();
        if (!matchStatus) return false;
        if (q.isEmpty) return true;
        final name = (o.shippingAddress['name'] ?? '').toString().toLowerCase();
        final orderId = o.id.toLowerCase();
        final orderNum = o.orderNumber.toLowerCase();
        return name.contains(q) || orderId.contains(q) || orderNum.contains(q);
      }).toList();
    });
  }

  Future<void> _deleteOrder(OrderModel order) async {
    if (order.status.toLowerCase() != 'cancelled') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Order',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Delete order #${order.orderNumber.isNotEmpty ? order.orderNumber : order.id.substring(0, 8)}? This cannot be undone.',
          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.poppins(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(order.id)
          .delete();
      if (mounted) _snack('Order deleted', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _updateStatus(OrderModel order, String newStatus) async {
    try {
      await FirebaseFirestore.instance
          .collection('orders')
          .doc(order.id)
          .update({'status': newStatus});
      final idx = _orders.indexWhere((o) => o.id == order.id);
      if (idx != -1) {
        _orders[idx] = _orders[idx].copyWith(status: newStatus);
        _applyFilter();
      }
      if (mounted) _snack('Status updated to $newStatus', AppColors.success);
      _notifyCustomerStatusChange(order, newStatus);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _notifyCustomerStatusChange(
      OrderModel order, String newStatus) async {
    final statusMessages = {
      'pending': 'Your order #${order.orderNumber} has been received.',
      'confirmed': 'Your order #${order.orderNumber} has been confirmed! ✅',
      'processing': 'Your order #${order.orderNumber} is being processed. 📦',
      'shipped': 'Your order #${order.orderNumber} is on the way! 🚚',
      'delivered': 'Your order #${order.orderNumber} has been delivered! 🎉',
      'cancelled': 'Your order #${order.orderNumber} has been cancelled.',
    };
    final body = statusMessages[newStatus.toLowerCase()] ??
        'Your order #${order.orderNumber} status: $newStatus';

    try {
      final token = await AuthService().getIdToken();
      if (token != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(order.userId)
            .get();
        final fcmToken = doc.data()?['fcmToken'] as String?;
        if (fcmToken != null && fcmToken.isNotEmpty) {
          await NotificationService().sendToToken(
            token: fcmToken,
            title: 'Order Update',
            body: body,
            firebaseIdToken: token,
            data: {'type': 'order_status', 'orderId': order.id},
          );
        }
      }
    } catch (e) {
      debugPrint('[Notification] order status FCM failed: $e');
    }
    try {
      await NotificationModel.save(
        userId: order.userId,
        title: 'Order Update',
        body: body,
        type: 'order_status',
        data: {'orderId': order.id},
      );
    } catch (e) {
      debugPrint('[Notification] order status in-app save failed: $e');
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Orders',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textMedium),
              onPressed: _subscribe),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          _buildFilterChips(),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) {
          _searchQuery = v;
          _applyFilter();
        },
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search by order ID or name…',
          hintStyle:
              GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
          prefixIcon:
              Icon(Icons.search_rounded, color: AppColors.textMedium, size: 20),
          suffixIcon: _searchCtrl.text.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded,
                      color: AppColors.textMedium, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    _searchQuery = '';
                    _applyFilter();
                  },
                )
              : null,
        ),
      ),
    );
  }

  Widget _buildFilterChips() {
    return SizedBox(
      height: 46,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _statuses.length,
        itemBuilder: (_, i) {
          final s = _statuses[i];
          final isSelected = s == _selectedStatus;
          return GestureDetector(
            onTap: () {
              _selectedStatus = s;
              _applyFilter();
            },
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                gradient: isSelected ? AppColors.gradient1 : null,
                color: isSelected ? null : AppColors.card,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: isSelected ? Colors.transparent : AppColors.border),
              ),
              alignment: Alignment.center,
              child: Text(_capitalize(s),
                  style: GoogleFonts.poppins(
                      color: isSelected ? Colors.white : AppColors.textMedium,
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w400)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _subscribe, child: const Text('Retry')),
        ]),
      );
    }
    if (_filtered.isEmpty) {
      return const _EmptyState(
          icon: Icons.receipt_long_outlined, label: 'No orders found');
    }
    return RefreshIndicator(
      onRefresh: () async => _subscribe(),
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _OrderAdminCard(
          order: _filtered[i],
          statuses: _statuses.where((s) => s != 'all').toList(),
          onStatusChanged: (v) => _updateStatus(_filtered[i], v),
          onTap: () => _showOrderDetail(context, _filtered[i]),
          onDelete: () => _deleteOrder(_filtered[i]),
        ),
      ),
    );
  }

  void _showOrderDetail(BuildContext context, OrderModel order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OrderDetailSheet(order: order),
    );
  }
}

class _OrderAdminCard extends StatelessWidget {
  final OrderModel order;
  final List<String> statuses;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  const _OrderAdminCard(
      {required this.order,
      required this.statuses,
      required this.onStatusChanged,
      required this.onTap,
      required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${order.orderNumber.isNotEmpty ? order.orderNumber : order.id.substring(0, 8)}',
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    if ((order.shippingAddress['name'] ?? '')
                        .toString()
                        .isNotEmpty)
                      Text(
                        order.shippingAddress['name'].toString(),
                        style: GoogleFonts.poppins(
                            color: AppColors.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                    Text(
                      '${order.items.length} item${order.items.length != 1 ? 's' : ''} · ${fmtPrice(order.totalPrice)}',
                      style: GoogleFonts.poppins(
                          color: AppColors.textMedium, fontSize: 12),
                    ),
                  ]),
            ),
            _StatusChip(status: order.status),
          ]),
          if (order.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(
              DateFormat('MMM d, y · hh:mm a').format(order.createdAt!),
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 11),
            ),
          ],
          const SizedBox(height: 8),
          _PaymentMethodBadge(method: order.paymentMethod),
          const SizedBox(height: 10),
          Row(children: [
            Text('Update status: ',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 12)),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    // Guard: if status isn't in items list use null to avoid assertion
                    value:
                        statuses.contains(order.status) ? order.status : null,
                    hint: Text(
                      statuses.contains(order.status)
                          ? ''
                          : _capitalize(
                              order.status.isEmpty ? 'unknown' : order.status),
                      style: GoogleFonts.poppins(
                          color: AppColors.textLight, fontSize: 12),
                    ),
                    isExpanded: true,
                    dropdownColor: AppColors.surface,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textMedium, size: 16),
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary, fontSize: 12),
                    items: statuses
                        .map((s) => DropdownMenuItem(
                            value: s, child: Text(_capitalize(s))))
                        .toList(),
                    onChanged: (v) {
                      if (v != null && v != order.status) onStatusChanged(v);
                    },
                  ),
                ),
              ),
            ),
            if (order.status.toLowerCase() == 'cancelled') ...[
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: Icon(Icons.delete_outline_rounded,
                    color: AppColors.error, size: 20),
                tooltip: 'Delete order',
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.error.withValues(alpha: 0.10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                padding: const EdgeInsets.all(6),
                constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

class _OrderDetailSheet extends StatefulWidget {
  final OrderModel order;
  const _OrderDetailSheet({required this.order});

  @override
  State<_OrderDetailSheet> createState() => _OrderDetailSheetState();
}

class _OrderDetailSheetState extends State<_OrderDetailSheet> {
  GoogleMapController? _mapController;

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  OrderModel get order => widget.order;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Order Details',
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.w700)),
                  IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textMedium),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.all(20),
                children: [
                  _DetailRow(
                      label: 'Order #',
                      value: order.orderNumber.isNotEmpty
                          ? order.orderNumber
                          : order.id),
                  _DetailRow(
                      label: 'Status',
                      value: _capitalize(order.status),
                      valueColor: order.statusColor),
                  _DetailRow(
                      label: 'Payment',
                      value: _capitalize(order.paymentStatus)),
                  _DetailRow(label: 'Total', value: fmtPrice(order.totalPrice)),
                  if (order.createdAt != null)
                    _DetailRow(
                        label: 'Date',
                        value: DateFormat('MMM d, y').format(order.createdAt!)),
                  const SizedBox(height: 16),
                  Text('Customer',
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if ((order.shippingAddress['name'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _DetailRow(
                              label: 'Name',
                              value: order.shippingAddress['name'].toString()),
                        if ((order.shippingAddress['phone'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _DetailRow(
                              label: 'Phone',
                              value: order.shippingAddress['phone'].toString()),
                        if ((order.shippingAddress['street'] ?? '')
                            .toString()
                            .isNotEmpty)
                          _DetailRow(
                              label: 'Street',
                              value:
                                  order.shippingAddress['street'].toString()),
                        _DetailRow(
                            label: 'Payment', value: order.paymentMethod),
                      ],
                    ),
                  ),

                  // Map — only shown when lat/lng were picked
                  if (order.shippingAddress['lat'] != null &&
                      order.shippingAddress['lng'] != null) ...[
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 200,
                        child: GoogleMap(
                          initialCameraPosition: CameraPosition(
                            target: LatLng(
                              (order.shippingAddress['lat'] as num).toDouble(),
                              (order.shippingAddress['lng'] as num).toDouble(),
                            ),
                            zoom: 15,
                          ),
                          onMapCreated: (c) => _mapController = c,
                          markers: {
                            Marker(
                              markerId: const MarkerId('delivery'),
                              position: LatLng(
                                (order.shippingAddress['lat'] as num)
                                    .toDouble(),
                                (order.shippingAddress['lng'] as num)
                                    .toDouble(),
                              ),
                              infoWindow: InfoWindow(
                                title: (order.shippingAddress['name'] ?? '')
                                    .toString(),
                                snippet: (order.shippingAddress['street'] ?? '')
                                    .toString(),
                              ),
                            ),
                          },
                          zoomControlsEnabled: false,
                          mapToolbarEnabled: false,
                          myLocationButtonEnabled: false,
                          liteModeEnabled: true,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),
                  Text('Items',
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  ...order.items.map((item) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border)),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: item.image.isNotEmpty
                                  ? CachedNetworkImage(
                                      imageUrl: item.image,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorWidget: (_, __, ___) =>
                                          const _ProductPlaceholder(size: 44))
                                  : const _ProductPlaceholder(size: 44),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(item.name,
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textPrimary,
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    Text(
                                        'x${item.quantity} · ${fmtPrice(item.price)}',
                                        style: GoogleFonts.poppins(
                                            color: AppColors.textMedium,
                                            fontSize: 12)),
                                  ]),
                            ),
                            Text(fmtPrice(item.subtotal),
                                style: GoogleFonts.poppins(
                                    color: AppColors.accent,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      )),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentMethodBadge extends StatelessWidget {
  final String method;
  const _PaymentMethodBadge({required this.method});

  @override
  Widget build(BuildContext context) {
    final lower = method.toLowerCase();
    final Color bg;
    final Color fg;
    String? assetIcon;
    IconData? fallbackIcon;

    if (lower.contains('kpay') || lower.contains('kbz')) {
      bg = const Color(0xFFE5007E).withValues(alpha: 0.12);
      fg = const Color(0xFFE5007E);
      assetIcon = 'assets/icons/kpay.png';
    } else if (lower.contains('wave')) {
      bg = const Color(0xFF003087).withValues(alpha: 0.12);
      fg = const Color(0xFF003087);
      assetIcon = 'assets/icons/wavepay.png';
    } else if (lower.contains('cash')) {
      bg = Colors.green.withValues(alpha: 0.12);
      fg = Colors.green.shade700;
      fallbackIcon = Icons.payments_rounded;
    } else {
      bg = AppColors.border;
      fg = AppColors.textMedium;
      fallbackIcon = Icons.credit_card_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (assetIcon != null)
          Image.asset(assetIcon, width: 16, height: 16)
        else
          Icon(fallbackIcon, size: 13, color: fg),
        const SizedBox(width: 5),
        Text(method,
            style: GoogleFonts.poppins(
                color: fg, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. Users Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminUsersTab extends StatefulWidget {
  const _AdminUsersTab();

  @override
  State<_AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<_AdminUsersTab> {
  bool _isLoading = true;
  String? _error;
  List<UserModel> _users = [];
  List<UserModel> _filtered = [];
  final _searchCtrl = TextEditingController();

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      _users = snap.docs
          .map((doc) => UserModel.fromJson(_docToMap(doc)))
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      _applyFilter(_searchCtrl.text);
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _applyFilter(String q) {
    final query = q.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? List.from(_users)
          : _users
              .where((u) =>
                  u.name.toLowerCase().contains(query) ||
                  u.email.toLowerCase().contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Users',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textMedium),
              onPressed: _fetch),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _applyFilter,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by name or email…',
                prefixIcon:
                    Icon(Icons.search_rounded, color: AppColors.textMedium),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.clear_rounded,
                            color: AppColors.textMedium),
                        onPressed: () {
                          _searchCtrl.clear();
                          _applyFilter('');
                        })
                    : null,
              ),
            ),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
        ]),
      );
    }
    if (_filtered.isEmpty) {
      return const _EmptyState(
          icon: Icons.people_outline_rounded, label: 'No users found');
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filtered.length,
        itemBuilder: (_, i) => _UserCard(
          user: _filtered[i],
          onRoleToggle: () => _toggleRole(_filtered[i]),
        ),
      ),
    );
  }

  Future<void> _toggleRole(UserModel user) async {
    final newRole = user.isAdmin ? 'user' : 'admin';
    final action = user.isAdmin ? 'Remove admin from' : 'Make admin';
    final ok = await _showConfirm(
      context,
      user.isAdmin ? 'Remove Admin' : 'Make Admin',
      '$action "${user.name}"?',
    );
    if (!ok) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.id)
          .update({'role': newRole});
      final idx = _users.indexWhere((u) => u.id == user.id);
      if (idx != -1) {
        _users[idx] = _users[idx].copyWith(role: newRole);
        _applyFilter(_searchCtrl.text);
      }
      if (mounted) _snack('Role updated to $newRole', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }
}

class _UserCard extends StatelessWidget {
  final UserModel user;
  final VoidCallback? onRoleToggle;
  const _UserCard({required this.user, this.onRoleToggle});

  @override
  Widget build(BuildContext context) {
    final initials = user.name.trim().isNotEmpty
        ? user.name
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
                gradient:
                    user.isAdmin ? AppColors.gradient1 : AppColors.gradient3,
                shape: BoxShape.circle),
            alignment: Alignment.center,
            child: Text(initials,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(user.name,
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 8),
                _RoleBadge(role: user.role),
              ]),
              const SizedBox(height: 2),
              Text(user.email,
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (user.phone.isNotEmpty)
                Text(user.phone,
                    style: GoogleFonts.poppins(
                        color: AppColors.textMedium, fontSize: 11)),
            ]),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                    color: user.isOnline ? AppColors.success : AppColors.border,
                    shape: BoxShape.circle),
              ),
              const SizedBox(height: 6),
              if (onRoleToggle != null)
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  iconSize: 18,
                  icon: Icon(Icons.more_vert_rounded,
                      color: AppColors.textMedium, size: 18),
                  color: AppColors.surface,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'toggle',
                      child: Row(
                        children: [
                          Icon(
                            user.isAdmin
                                ? Icons.person_remove_rounded
                                : Icons.admin_panel_settings_rounded,
                            color: user.isAdmin
                                ? AppColors.error
                                : AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            user.isAdmin ? 'Remove Admin' : 'Make Admin',
                            style: GoogleFonts.poppins(
                              color: user.isAdmin
                                  ? AppColors.error
                                  : AppColors.primary,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  onSelected: (_) => onRoleToggle!(),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. Chat Tab (real-time via Firestore stream)
// ─────────────────────────────────────────────────────────────────────────────
class _AdminChatTab extends StatelessWidget {
  const _AdminChatTab();

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final adminId = Get.find<AuthController>().user.value?.id ?? '';
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.bg,
          automaticallyImplyLeading: true,
          title: Text('Customer Chats',
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700)),
        ),
        body: adminId.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary))
            : StreamBuilder<List<Map<String, dynamic>>>(
                stream: ChatService().conversationsStream(adminId),
                builder: (ctx, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary));
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: Text('Error: ${snapshot.error}',
                            style:
                                GoogleFonts.poppins(color: AppColors.error)));
                  }
                  final conversations = snapshot.data ?? [];
                  if (conversations.isEmpty) {
                    return const _EmptyState(
                        icon: Icons.chat_bubble_outline_rounded,
                        label: 'No conversations yet');
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: conversations.length,
                    itemBuilder: (_, i) {
                      final conv = conversations[i];
                      final participants =
                          List<String>.from(conv['participants'] ?? []);
                      final otherUserId = participants.firstWhere(
                          (id) => id != adminId,
                          orElse: () => participants.isNotEmpty
                              ? participants.first
                              : '');
                      return _ChatConvTile(
                          adminId: adminId,
                          otherUserId: otherUserId,
                          conv: conv);
                    },
                  );
                },
              ),
      );
    });
  }
}

class _ChatConvTile extends StatelessWidget {
  final String adminId;
  final String otherUserId;
  final Map<String, dynamic> conv;
  const _ChatConvTile(
      {required this.adminId, required this.otherUserId, required this.conv});

  @override
  Widget build(BuildContext context) {
    if (otherUserId.isEmpty) return const SizedBox.shrink();

    // Use pre-fetched otherUser data from the enriched conversationsStream
    final otherUser = conv['otherUser'] as Map<String, dynamic>? ?? {};
    final userName = otherUser['name']?.toString() ?? 'User';
    final userAvatar = otherUser['avatar']?.toString() ?? '';

    final lastMsg = conv['lastMessage']?.toString() ?? '';
    // unreadCount already computed per-participant by the enriched stream
    final unread = _parseInt(conv['unreadCount']);

    DateTime? time;
    final rawTime = conv['lastMessageAt'];
    if (rawTime is String) {
      time = DateTime.tryParse(rawTime);
    } else if (rawTime is Timestamp) {
      time = rawTime.toDate();
    }

    return _ConversationTile(
      userId: otherUserId,
      userName: userName,
      userAvatar: userAvatar,
      lastMessage: lastMsg,
      unreadCount: unread,
      time: time,
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: otherUserId,
          userName: userName,
          userAvatar: userAvatar,
        ),
      )),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. Categories Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminCategoriesTab extends StatefulWidget {
  const _AdminCategoriesTab();

  @override
  State<_AdminCategoriesTab> createState() => _AdminCategoriesTabState();
}

class _AdminCategoriesTabState extends State<_AdminCategoriesTab> {
  bool _isLoading = true;
  String? _error;
  List<CategoryModel> _categories = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap =
          await FirebaseFirestore.instance.collection('categories').get();
      _categories = snap.docs.map((doc) {
        final m = _docToMap(doc);
        return CategoryModel.fromJson(m);
      }).toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await _showConfirm(
        context, 'Delete Category', 'Delete "$name"? This cannot be undone.');
    if (!ok) return;
    try {
      await FirebaseFirestore.instance
          .collection('categories')
          .doc(id)
          .delete();
      _categories.removeWhere((c) => c.id == id);
      setState(() {});
      if (mounted) _snack('Category deleted', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Categories',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textMedium),
              onPressed: _fetch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admin_categories_fab',
        onPressed: () => _showCategorySheet(context, null, _fetch),
        backgroundColor: AppColors.primary,
        child: Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline_rounded, color: AppColors.error, size: 48),
          const SizedBox(height: 12),
          Text(_error!,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
        ]),
      );
    }
    if (_categories.isEmpty) {
      return const _EmptyState(
          icon: Icons.category_outlined, label: 'No categories yet');
    }
    return RefreshIndicator(
      onRefresh: _fetch,
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _categories.length,
        itemBuilder: (_, i) => _CategoryCard(
          category: _categories[i],
          onEdit: () => _showCategorySheet(context, _categories[i], _fetch),
          onDelete: () => _delete(_categories[i].id, _categories[i].name),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  final CategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _CategoryCard(
      {required this.category, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Row(
        children: [
          // Icon / Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: category.image.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: UploadService.fixUrl(category.image),
                    width: 56,
                    height: 56,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) =>
                        _CategoryIconBox(icon: category.icon))
                : _CategoryIconBox(icon: category.icon),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(category.name,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
              if (category.description.isNotEmpty)
                Text(category.description,
                    style: GoogleFonts.poppins(
                        color: AppColors.textMedium, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
              Text('${category.productCount} products',
                  style: GoogleFonts.poppins(
                      color: AppColors.primary,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
          Column(children: [
            IconButton(
                icon: Icon(Icons.edit_rounded,
                    color: AppColors.primary, size: 20),
                onPressed: onEdit),
            IconButton(
                icon: Icon(Icons.delete_rounded,
                    color: AppColors.error, size: 20),
                onPressed: onDelete),
          ]),
        ],
      ),
    );
  }
}

class _CategoryIconBox extends StatelessWidget {
  final String icon;
  const _CategoryIconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
          gradient: AppColors.gradient1,
          borderRadius: BorderRadius.circular(12)),
      alignment: Alignment.center,
      child: Text(icon.isNotEmpty ? icon : '🛍️',
          style: const TextStyle(fontSize: 26)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Category Form Sheet
// ─────────────────────────────────────────────────────────────────────────────
void _showCategorySheet(
    BuildContext context, CategoryModel? category, VoidCallback onSaved) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryFormSheet(category: category, onSaved: onSaved),
  );
}

class _CategoryFormSheet extends StatefulWidget {
  final CategoryModel? category;
  final VoidCallback onSaved;
  const _CategoryFormSheet({this.category, required this.onSaved});

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _iconCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  bool _isLoading = false;

  // Image
  Uint8List? _imageBytes;
  String _imageFilename = '';
  String _imageUrl = '';
  bool _isUploadingImage = false;

  @override
  void initState() {
    super.initState();
    final c = widget.category;
    if (c != null) {
      _nameCtrl.text = c.name;
      _descCtrl.text = c.description;
      _iconCtrl.text = c.icon;
      _colorCtrl.text = c.color;
      _imageUrl = c.image;
    } else {
      _iconCtrl.text = '🛍️';
      _colorCtrl.text = '#6C63FF';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _iconCtrl.dispose();
    _colorCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked =
        await picker.pickImage(source: source, imageQuality: 80, maxWidth: 800);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFilename = picked.name.isNotEmpty ? picked.name : 'image.jpg';
      _imageUrl = '';
    });
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    try {
      final db = FirebaseFirestore.instance;
      final name = _nameCtrl.text.trim();
      final slug = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

      // Upload image on submit if new bytes were picked
      if (_imageBytes != null) {
        setState(() => _isUploadingImage = true);
        final token = await AuthService().getIdToken();
        if (token == null) throw Exception('Not authenticated');

        final oldUrl = widget.category?.image ?? '';
        if (oldUrl.isNotEmpty) {
          await UploadService().deleteImage(oldUrl, token);
        }

        _imageUrl = await UploadService()
            .uploadImageBytes(_imageBytes!, _imageFilename, token);
        setState(() => _isUploadingImage = false);
      }

      final payload = <String, dynamic>{
        'name': name,
        'slug': slug,
        'description': _descCtrl.text.trim(),
        'icon':
            _iconCtrl.text.trim().isNotEmpty ? _iconCtrl.text.trim() : '🛍️',
        'color': _colorCtrl.text.trim().isNotEmpty
            ? _colorCtrl.text.trim()
            : '#6C63FF',
        'image': _imageUrl,
        'productCount': widget.category?.productCount ?? 0,
      };

      if (widget.category == null) {
        payload['createdAt'] = FieldValue.serverTimestamp();
        await db.collection('categories').add(payload);
      } else {
        await db
            .collection('categories')
            .doc(widget.category!.id)
            .update(payload);
      }

      if (mounted) {
        Navigator.of(context).pop();
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(
          children: [
            _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    widget.category == null ? 'Add Category' : 'Edit Category',
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700),
                  ),
                  IconButton(
                      icon: Icon(Icons.close_rounded,
                          color: AppColors.textMedium),
                      onPressed: () => Navigator.of(context).pop()),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: controller,
                padding: EdgeInsets.fromLTRB(
                    20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      // Category image picker
                      _buildCategoryImagePicker(),
                      const SizedBox(height: 16),
                      _Field(
                          ctrl: _nameCtrl,
                          label: 'Category Name *',
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Required' : null),
                      const SizedBox(height: 14),
                      _Field(
                          ctrl: _descCtrl, label: 'Description', maxLines: 2),
                      const SizedBox(height: 14),
                      Row(children: [
                        Expanded(
                          child: _Field(
                              ctrl: _iconCtrl,
                              label: 'Icon (emoji)',
                              hint: '🛍️'),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _Field(
                              ctrl: _colorCtrl,
                              label: 'Color (hex)',
                              hint: '#6C63FF'),
                        ),
                      ]),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: (_isLoading || _isUploadingImage)
                              ? null
                              : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(widget.category == null
                                  ? 'Add Category'
                                  : 'Update Category'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryImagePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Category Image',
            style: GoogleFonts.poppins(
                color: AppColors.textMedium,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        if (_imageBytes != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_imageBytes!,
                width: double.infinity, height: 120, fit: BoxFit.cover),
          )
        else if (_imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedNetworkImage(
              imageUrl: UploadService.fixUrl(_imageUrl),
              width: double.infinity,
              height: 120,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => _catImgPlaceholder(),
            ),
          )
        else
          _catImgPlaceholder(),
        if (_isUploadingImage) ...[
          const SizedBox(height: 6),
          LinearProgressIndicator(
              color: AppColors.primary, backgroundColor: AppColors.surface),
        ],
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(color: AppColors.primary)),
              icon: Icon(Icons.photo_library_rounded, size: 18),
              label: const Text('Gallery'),
              onPressed: _isUploadingImage
                  ? null
                  : () => _pickImage(ImageSource.gallery),
            ),
          ),
          if (!kIsWeb) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    side: BorderSide(color: AppColors.accent)),
                icon: Icon(Icons.camera_alt_rounded, size: 18),
                label: const Text('Camera'),
                onPressed: _isUploadingImage
                    ? null
                    : () => _pickImage(ImageSource.camera),
              ),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _catImgPlaceholder() {
    return Container(
      width: double.infinity,
      height: 100,
      decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border)),
      alignment: Alignment.center,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.add_photo_alternate_outlined,
            color: AppColors.textMedium, size: 32),
        const SizedBox(height: 4),
        Text('Pick category image',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 11)),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Conversation Tile (shared between chat tab)
// ─────────────────────────────────────────────────────────────────────────────
class _ConversationTile extends StatelessWidget {
  final String userId;
  final String userName;
  final String userAvatar;
  final String lastMessage;
  final int unreadCount;
  final DateTime? time;
  final VoidCallback onTap;
  const _ConversationTile(
      {required this.userId,
      required this.userName,
      required this.userAvatar,
      required this.lastMessage,
      required this.unreadCount,
      required this.onTap,
      this.time});

  @override
  Widget build(BuildContext context) {
    final initials = userName.trim().isNotEmpty
        ? userName
            .trim()
            .split(' ')
            .take(2)
            .map((w) => w[0].toUpperCase())
            .join()
        : '?';

    String timeStr = '';
    if (time != null) {
      final diff = DateTime.now().difference(time!);
      if (diff.inMinutes < 1) {
        timeStr = 'now';
      } else if (diff.inHours < 1) {
        timeStr = '${diff.inMinutes}m';
      } else if (diff.inDays < 1) {
        timeStr = '${diff.inHours}h';
      } else {
        timeStr = DateFormat('MMM d').format(time!);
      }
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: unreadCount > 0
                    ? AppColors.primary.withValues(alpha: 0.4)
                    : AppColors.border)),
        child: Row(
          children: [
            Stack(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      gradient: AppColors.gradient1, shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: userAvatar.isNotEmpty
                      ? ClipOval(
                          child: CachedNetworkImage(
                              imageUrl: userAvatar,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Text(initials,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w700))))
                      : Text(initials,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                ),
                if (unreadCount > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                          color: AppColors.error, shape: BoxShape.circle),
                      alignment: Alignment.center,
                      child: Text(
                          unreadCount > 9 ? '9+' : unreadCount.toString(),
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w700)),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(userName,
                            style: GoogleFonts.poppins(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w700
                                    : FontWeight.w500)),
                        if (timeStr.isNotEmpty)
                          Text(timeStr,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textMedium, fontSize: 11)),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      lastMessage.isNotEmpty ? lastMessage : 'No messages yet',
                      style: GoogleFonts.poppins(
                          color: unreadCount > 0
                              ? AppColors.textPrimary
                              : AppColors.textMedium,
                          fontSize: 12,
                          fontWeight: unreadCount > 0
                              ? FontWeight.w500
                              : FontWeight.w400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: AppColors.textMedium, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StatData {
  final String label;
  final String value;
  final IconData icon;
  final LinearGradient gradient;
  final String trend;
  final bool up;
  const _StatData(
      {required this.label,
      required this.value,
      required this.icon,
      required this.gradient,
      required this.trend,
      required this.up});
}

class _StatCard extends StatelessWidget {
  final _StatData data;
  const _StatCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: data.gradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: data.gradient.colors.first.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          // Large decorative icon in top-right
          Positioned(
            right: -10,
            top: -10,
            child: Icon(
              data.icon,
              size: 80,
              color: Colors.white.withValues(alpha: 0.12),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(data.icon, color: Colors.white, size: 20),
                ),
                const SizedBox(height: 10),
                Text(
                  data.value,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  data.label,
                  style: GoogleFonts.poppins(
                    color: Colors.white.withValues(alpha: 0.80),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
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

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status.toLowerCase()) {
      case 'pending':
        color = AppColors.warning;
        break;
      case 'processing':
        color = AppColors.primary;
        break;
      case 'shipped':
        color = const Color(0xFF8B5CF6);
        break;
      case 'delivered':
      case 'active':
        color = AppColors.success;
        break;
      case 'cancelled':
      case 'inactive':
        color = AppColors.error;
        break;
      default:
        color = AppColors.textMedium;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Text(_capitalize(status),
          style: GoogleFonts.poppins(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final isAdmin = role.toLowerCase() == 'admin';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          gradient: isAdmin ? AppColors.gradient1 : null,
          color: isAdmin ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: isAdmin ? null : Border.all(color: AppColors.border)),
      child: Text(_capitalize(role),
          style: GoogleFonts.poppins(
              color: isAdmin ? Colors.white : AppColors.textMedium,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// POS Summary Card
// ─────────────────────────────────────────────────────────────────────────────

class _PosSummaryCard extends StatelessWidget {
  final String label;
  final String subtitle;
  final double amount;
  final int count;
  final Color color;
  final IconData icon;

  const _PosSummaryCard({
    required this.label,
    required this.subtitle,
    required this.amount,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMedium)),
                    Text(subtitle,
                        style: GoogleFonts.poppins(
                            fontSize: 10, color: AppColors.textLight),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            fmtPrice(amount),
            style: GoogleFonts.poppins(
                fontSize: 18, fontWeight: FontWeight.w800, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            '$count transaction${count == 1 ? '' : 's'}',
            style:
                GoogleFonts.poppins(fontSize: 11, color: AppColors.textMedium),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String label;
  const _EmptyState({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, color: AppColors.textMedium, size: 56),
        const SizedBox(height: 12),
        Text(label,
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 14)),
      ]),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
              color: AppColors.border, borderRadius: BorderRadius.circular(2)),
        ),
      ),
    );
  }
}

class _ProductPlaceholder extends StatelessWidget {
  final double size;
  const _ProductPlaceholder({this.size = 64});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(10)),
      alignment: Alignment.center,
      child: Icon(Icons.image_rounded,
          color: AppColors.textMedium, size: size * 0.4),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final IconData? prefixIcon;
  const _Field(
      {required this.ctrl,
      required this.label,
      this.hint,
      this.maxLines = 1,
      this.keyboardType,
      this.validator,
      this.prefixIcon});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18) : null,
      ),
    );
  }
}

class _BarcodeInputField extends StatefulWidget {
  final TextEditingController ctrl;
  const _BarcodeInputField({required this.ctrl});

  @override
  State<_BarcodeInputField> createState() => _BarcodeInputFieldState();
}

class _BarcodeInputFieldState extends State<_BarcodeInputField> {
  final _focus = FocusNode();
  final _beep = AudioPlayer();
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    // Release callback ownership when widget is removed
    if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
      if (BarcodeScannerService.to.onBarcodeReceived != null) {
        BarcodeScannerService.to.onBarcodeReceived = null;
      }
    }
    _focus.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!mounted) return;
    if (_focus.hasFocus) {
      // Claim the network scanner when this field is active
      if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
        BarcodeScannerService.to.onBarcodeReceived = (barcode) {
          if (mounted) {
            widget.ctrl.text = barcode;
            widget.ctrl.selection =
                TextSelection.collapsed(offset: barcode.length);
          }
        };
      }
      setState(() => _scanning = true);
    } else {
      // Release the callback so POS can reclaim it
      if (!kIsWeb && Get.isRegistered<BarcodeScannerService>()) {
        BarcodeScannerService.to.onBarcodeReceived = null;
      }
      setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.ctrl,
      focusNode: _focus,
      // Next prevents Enter from accidentally submitting the form
      textInputAction: TextInputAction.next,
      keyboardType: TextInputType.text,
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 14),
      decoration: InputDecoration(
        labelText: 'Barcode',
        hintText: 'Scan or type barcode',
        prefixIcon: Icon(
          Icons.qr_code_scanner_rounded,
          size: 18,
          color: _scanning ? AppColors.primary : null,
        ),
        suffixIcon: _scanning
            ? Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                ),
              )
            : null,
        labelStyle: _scanning ? TextStyle(color: AppColors.primary) : null,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: GoogleFonts.poppins(
                  color: valueColor ?? AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. Notifications Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminNotificationsTab extends StatefulWidget {
  const _AdminNotificationsTab();

  @override
  State<_AdminNotificationsTab> createState() => _AdminNotificationsTabState();
}

class _AdminNotificationsTabState extends State<_AdminNotificationsTab> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  // 'all' | 'specific'
  String _target = 'all';

  // 'promo' (7d) | 'system' (90d)
  String _notiType = 'promo';

  // Users loaded for the picker
  List<Map<String, dynamic>> _users = [];
  bool _loadingUsers = false;
  String? _selectedUserId;
  String? _selectedUserName;

  bool _isSending = false;

  // Diagnostics
  String _fcmToken = '';
  bool? _backendOk;
  bool _loadingDiag = false;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _runDiagnostics();
  }

  Future<void> _runDiagnostics() async {
    setState(() => _loadingDiag = true);
    final results = await Future.wait([
      NotificationService().getTokenOrEmpty(),
      NotificationService().isBackendReachable(),
    ]);
    if (mounted) {
      setState(() {
        _fcmToken = results[0] as String;
        _backendOk = results[1] as bool;
        _loadingDiag = false;
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'user')
          .get();
      setState(() {
        _users = snap.docs
            .map((d) => {
                  'id': d.id,
                  'name': d.data()['name'] ?? 'Unknown',
                  'email': d.data()['email'] ?? '',
                  'fcmToken': d.data()['fcmToken'] ?? '',
                })
            .toList();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loadingUsers = false);
    }
  }

  Future<void> _send() async {
    if (!_formKey.currentState!.validate()) return;
    if (_target == 'specific' && _selectedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Please select a user',
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    setState(() => _isSending = true);
    try {
      final title = _titleCtrl.text.trim();
      final body = _bodyCtrl.text.trim();
      final idToken = await AuthService().getIdToken();
      if (idToken == null) throw Exception('Not authenticated');

      if (_target == 'all') {
        // Users only — admin should not receive broadcast promos/system msgs
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'user')
            .get();
        int pushed = 0;
        for (final doc in snap.docs) {
          final data = doc.data();
          try {
            await NotificationModel.save(
              userId: doc.id,
              title: title,
              body: body,
              type: _notiType,
            );
          } catch (e) {
            debugPrint('[Send] in-app save failed for ${doc.id}: $e');
          }
          final fcmToken = data['fcmToken'] as String?;
          if (fcmToken != null && fcmToken.isNotEmpty) {
            try {
              await NotificationService().sendToToken(
                token: fcmToken,
                title: title,
                body: body,
                firebaseIdToken: idToken,
                data: {'type': _notiType},
              );
              pushed++;
            } catch (e) {
              debugPrint('[Send] FCM failed for ${doc.id}: $e');
            }
          }
        }
        _showSuccess('Sent to ${snap.docs.length} users ($pushed push)');
      } else {
        final uid = _selectedUserId!;
        final user = _users.firstWhere((u) => u['id'] == uid,
            orElse: () => {'fcmToken': ''});
        await NotificationModel.save(
          userId: uid,
          title: title,
          body: body,
          type: _notiType,
        );
        final fcmToken = user['fcmToken'] as String;
        if (fcmToken.isNotEmpty) {
          await NotificationService().sendToToken(
            token: fcmToken,
            title: title,
            body: body,
            firebaseIdToken: idToken,
            data: {'type': _notiType},
          );
          _showSuccess('Sent to ${_selectedUserName ?? uid}');
        } else {
          _showSuccess(
              'In-app saved (${_selectedUserName ?? uid} has no FCM token)');
        }
      }

      _titleCtrl.clear();
      _bodyCtrl.clear();
      setState(() {
        _target = 'all';
        _notiType = 'promo';
        _selectedUserId = null;
        _selectedUserName = null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString(),
              style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _openUserPicker() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              const SizedBox(height: 10),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.border,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text('Select User',
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w600)),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _loadingUsers
                    ? const Center(child: CircularProgressIndicator())
                    : _users.isEmpty
                        ? Center(
                            child: Text('No users found',
                                style: GoogleFonts.poppins(
                                    color: AppColors.textMedium)))
                        : ListView.separated(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                            itemCount: _users.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: AppColors.border),
                            itemBuilder: (_, i) {
                              final u = _users[i];
                              final isSelected = u['id'] == _selectedUserId;
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.15),
                                  child: Text(
                                    (u['name'] as String).isNotEmpty
                                        ? (u['name'] as String)[0].toUpperCase()
                                        : '?',
                                    style: GoogleFonts.poppins(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600),
                                  ),
                                ),
                                title: Text(u['name'] as String,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textPrimary,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500)),
                                subtitle: Text(u['email'] as String,
                                    style: GoogleFonts.poppins(
                                        color: AppColors.textMedium,
                                        fontSize: 12)),
                                trailing: isSelected
                                    ? Icon(Icons.check_circle_rounded,
                                        color: AppColors.primary)
                                    : Icon(Icons.radio_button_unchecked,
                                        color: AppColors.textMedium),
                                onTap: () {
                                  setState(() {
                                    _selectedUserId = u['id'] as String;
                                    _selectedUserName = u['name'] as String;
                                  });
                                  Navigator.pop(ctx);
                                },
                              );
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text(
          'Send Notification',
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              // ── Diagnostics card ─────────────────────────────────────
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: _loadingDiag
                    ? Row(children: [
                        SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.primary),
                        ),
                        const SizedBox(width: 10),
                        Text('Checking diagnostics…',
                            style: GoogleFonts.poppins(
                                color: AppColors.textMedium, fontSize: 12)),
                      ])
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text('Diagnostics',
                                  style: GoogleFonts.poppins(
                                      color: AppColors.textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                              const Spacer(),
                              GestureDetector(
                                onTap: _runDiagnostics,
                                child: Icon(Icons.refresh_rounded,
                                    color: AppColors.primary, size: 18),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          _DiagRow(
                            label: 'Backend server',
                            ok: _backendOk == true,
                            value: _backendOk == null
                                ? 'unknown'
                                : _backendOk!
                                    ? 'Online'
                                    : 'OFFLINE — start the Node server',
                          ),
                          const SizedBox(height: 4),
                          _DiagRow(
                            label: 'FCM token (this device)',
                            ok: _fcmToken.isNotEmpty,
                            value: _fcmToken.isNotEmpty
                                ? '…${_fcmToken.substring(_fcmToken.length - 12)}'
                                : 'MISSING — check notification permission',
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 16),
              // ── Title ────────────────────────────────────────────────
              Text('Title',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _titleCtrl,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. New Arrivals!',
                  hintStyle: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 14),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Title is required'
                    : null,
              ),
              const SizedBox(height: 16),
              // ── Message ──────────────────────────────────────────────
              Text('Message',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextFormField(
                controller: _bodyCtrl,
                maxLines: 3,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'Enter your message here…',
                  hintStyle: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 14),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Message is required'
                    : null,
              ),
              const SizedBox(height: 20),
              // ── Target ───────────────────────────────────────────────
              Text('Target',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    _RadioOption(
                      label: 'All Users',
                      selected: _target == 'all',
                      onTap: () => setState(() {
                        _target = 'all';
                        _selectedUserId = null;
                        _selectedUserName = null;
                      }),
                    ),
                    Divider(height: 1, color: AppColors.border),
                    _RadioOption(
                      label: 'Specific User',
                      selected: _target == 'specific',
                      onTap: () => setState(() => _target = 'specific'),
                    ),
                  ],
                ),
              ),
              // ── User picker (specific) ───────────────────────────────
              if (_target == 'specific') ...[
                const SizedBox(height: 14),
                Text('User',
                    style: GoogleFonts.poppins(
                        color: AppColors.textMedium,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                GestureDetector(
                  onTap: _openUserPicker,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_outline_rounded,
                            color: AppColors.textMedium, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _selectedUserName ?? 'Tap to select a user…',
                            style: GoogleFonts.poppins(
                              color: _selectedUserName != null
                                  ? AppColors.textPrimary
                                  : AppColors.textMedium,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        Icon(Icons.keyboard_arrow_down_rounded,
                            color: AppColors.textMedium),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              // ── Notification type (controls TTL) ─────────────────────
              Text('Type',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              Container(
                decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border)),
                child: Column(
                  children: [
                    _RadioOption(
                      label: 'Promo  (kept 7 days)',
                      selected: _notiType == 'promo',
                      onTap: () => setState(() => _notiType = 'promo'),
                    ),
                    Divider(height: 1, color: AppColors.border),
                    _RadioOption(
                      label: 'System  (kept 90 days)',
                      selected: _notiType == 'system',
                      onTap: () => setState(() => _notiType = 'system'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              // ── Send button ──────────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient1,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4)),
                    ],
                  ),
                  child: ElevatedButton(
                    onPressed: _isSending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _isSending
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.send_rounded,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Send Notification',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              // ── Info card ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.primary, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Push notifications are sent via FCM and also saved in-app. Users who have not logged in on a device will receive the in-app notification on next login.',
                        style: GoogleFonts.poppins(
                            color: AppColors.primary,
                            fontSize: 12,
                            height: 1.5),
                      ),
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
// Admin Payments Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AdminPaymentsTab extends StatefulWidget {
  const _AdminPaymentsTab();
  @override
  State<_AdminPaymentsTab> createState() => _AdminPaymentsTabState();
}

class _AdminPaymentsTabState extends State<_AdminPaymentsTab>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _noteCtrl = TextEditingController();
  final _kpayNumCtrl = TextEditingController();
  final _kpayNameCtrl = TextEditingController();
  final _waveNumCtrl = TextEditingController();
  final _waveNameCtrl = TextEditingController();
  final _mandalayFeeCtrl = TextEditingController();

  static const _statuses = ['pending', 'approved', 'rejected'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _noteCtrl.dispose();
    _kpayNumCtrl.dispose();
    _kpayNameCtrl.dispose();
    _waveNumCtrl.dispose();
    _waveNameCtrl.dispose();
    _mandalayFeeCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAccountSettingsSheet() async {
    final current = await PaymentService().accountSettingsStream().first;
    _kpayNumCtrl.text = current['kpayNumber'] ?? '';
    _kpayNameCtrl.text = current['kpayName'] ?? '';
    _waveNumCtrl.text = current['waveNumber'] ?? '';
    _waveNameCtrl.text = current['waveName'] ?? '';
    if (!mounted) return;

    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Text('Payment Account Numbers',
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textMedium),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 20),

            // KPay
            _AccountSettingsSection(
              label: 'KPay',
              color: const Color(0xFFE5007E),
              nameCtrl: _kpayNameCtrl,
              numCtrl: _kpayNumCtrl,
            ),
            const SizedBox(height: 16),

            // Wave
            _AccountSettingsSection(
              label: 'Wave Money',
              color: const Color(0xFF003087),
              nameCtrl: _waveNameCtrl,
              numCtrl: _waveNumCtrl,
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        setSheet(() => saving = true);
                        try {
                          await PaymentService().saveAccountSettings(
                            kpayNumber: _kpayNumCtrl.text,
                            kpayName: _kpayNameCtrl.text,
                            waveNumber: _waveNumCtrl.text,
                            waveName: _waveNameCtrl.text,
                          );
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted)
                            _snack(
                                'Account numbers saved ✅', AppColors.success);
                        } catch (e) {
                          setSheet(() => saving = false);
                          if (mounted) _snack(e.toString(), AppColors.error);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showDeliveryFeeSheet() async {
    final current = await PaymentService().mandalayFeeStream().first;
    _mandalayFeeCtrl.text = current.toString();
    if (!mounted) return;

    bool saving = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Text('Delivery Fee Settings',
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 16,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              IconButton(
                  icon: Icon(Icons.close_rounded, color: AppColors.textMedium),
                  onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            _DeliveryFeeField(
              label: 'Mandalay City Fee (Ks)',
              hint: 'e.g. 3000',
              controller: _mandalayFeeCtrl,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Fixed fee for Mandalay city orders.\nOther areas: admin contacts customer via chat or notification.',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textMedium, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: saving
                    ? null
                    : () async {
                        final fee =
                            double.tryParse(_mandalayFeeCtrl.text.trim());
                        if (fee == null) {
                          if (mounted)
                            _snack('Enter a valid number', AppColors.error);
                          return;
                        }
                        setSheet(() => saving = true);
                        try {
                          await PaymentService().saveMandalayFee(fee);
                          if (ctx.mounted) Navigator.pop(ctx);
                          if (mounted)
                            _snack('Delivery fee saved ✅', AppColors.success);
                        } catch (e) {
                          setSheet(() => saving = false);
                          if (mounted) _snack(e.toString(), AppColors.error);
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Save',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _deletePayment(String paymentId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Delete Transaction',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        content: Text(
          'Permanently delete this payment record? This cannot be undone.',
          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete',
                style: GoogleFonts.poppins(
                    color: AppColors.error, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await PaymentService().deletePayment(paymentId);
      if (mounted) _snack('Transaction deleted', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _approve(String paymentId) async {
    _noteCtrl.clear();
    final confirm =
        await _showNoteDialog('Approve Payment', confirmLabel: 'Approve');
    if (!confirm) return;
    try {
      final token = await AuthService().getIdToken();
      if (token == null) return;
      await PaymentService()
          .approvePayment(paymentId, token, adminNote: _noteCtrl.text.trim());
      if (mounted) _snack('Payment approved ✅', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _reject(String paymentId) async {
    _noteCtrl.clear();
    final confirm = await _showNoteDialog('Reject Payment',
        hint: 'Reason for rejection (required)',
        confirmLabel: 'Reject',
        confirmColor: AppColors.error);
    if (!confirm) return;
    try {
      final token = await AuthService().getIdToken();
      if (token == null) return;
      await PaymentService()
          .rejectPayment(paymentId, token, adminNote: _noteCtrl.text.trim());
      if (mounted) _snack('Payment rejected', AppColors.error);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<bool> _showNoteDialog(String title,
      {String hint = 'Optional note',
      String confirmLabel = 'Confirm',
      Color? confirmColor}) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(title,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: TextField(
          controller: _noteCtrl,
          style:
              GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
          ),
          maxLines: 2,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(confirmLabel,
                style: GoogleFonts.poppins(
                    color: confirmColor ?? AppColors.success,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _viewScreenshot(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.contain,
              errorWidget: (_, __, ___) => const Icon(
                  Icons.broken_image_rounded,
                  color: Colors.white54,
                  size: 64),
            ),
          ),
          Positioned(
            top: 8,
            right: 8,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Payments',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: Icon(Icons.local_shipping_outlined,
                color: AppColors.textMedium),
            tooltip: 'Delivery Fee',
            onPressed: _showDeliveryFeeSheet,
          ),
          IconButton(
            icon: Icon(Icons.settings_rounded, color: AppColors.textMedium),
            tooltip: 'Account Numbers',
            onPressed: _showAccountSettingsSheet,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textMedium,
          indicatorColor: AppColors.primary,
          indicatorSize: TabBarIndicatorSize.label,
          labelStyle:
              GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
          unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13),
          tabs: const [
            Tab(text: 'Pending'),
            Tab(text: 'Approved'),
            Tab(text: 'Rejected'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: _statuses
            .map((s) => _PaymentList(
                  status: s,
                  onApprove: s == 'pending' ? _approve : null,
                  onReject: s == 'pending' ? _reject : null,
                  onDelete: s != 'pending' ? _deletePayment : null,
                  onViewScreenshot: _viewScreenshot,
                ))
            .toList(),
      ),
    );
  }
}

// ── Account settings section widget used in the settings bottom sheet ─────────

class _AccountSettingsSection extends StatelessWidget {
  final String label;
  final Color color;
  final TextEditingController nameCtrl;
  final TextEditingController numCtrl;
  const _AccountSettingsSection({
    required this.label,
    required this.color,
    required this.nameCtrl,
    required this.numCtrl,
  });

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: GoogleFonts.poppins(
                color: color, fontSize: 13, fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 8),
      TextField(
        controller: nameCtrl,
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Account Name',
          labelStyle:
              GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
          prefixIcon: Icon(Icons.person_outline_rounded,
              color: AppColors.textMedium, size: 18),
        ),
      ),
      const SizedBox(height: 8),
      TextField(
        controller: numCtrl,
        keyboardType: TextInputType.phone,
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: 'Phone Number',
          labelStyle:
              GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
          prefixIcon: Icon(Icons.phone_rounded, color: color, size: 18),
        ),
      ),
    ]);
  }
}

class _DeliveryFeeField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  const _DeliveryFeeField({
    required this.label,
    required this.hint,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle:
            GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        hintStyle:
            GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        prefixIcon: Icon(Icons.local_shipping_outlined,
            color: AppColors.textMedium, size: 18),
      ),
    );
  }
}

// ── Payment list (per-tab) ────────────────────────────────────────────────────

class _PaymentList extends StatelessWidget {
  final String status;
  final void Function(String)? onApprove;
  final void Function(String)? onReject;
  final void Function(String)? onDelete;
  final void Function(String) onViewScreenshot;

  const _PaymentList({
    required this.status,
    this.onApprove,
    this.onReject,
    this.onDelete,
    required this.onViewScreenshot,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<PaymentModel>>(
      stream: PaymentService().allPaymentsStream(status: status),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        final payments = snap.data ?? [];
        if (payments.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 56, color: AppColors.textMedium),
              const SizedBox(height: 12),
              Text('No $status payments',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 14)),
            ]),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: payments.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _PaymentCard(
            payment: payments[i],
            onApprove: onApprove,
            onReject: onReject,
            onDelete: onDelete,
            onViewScreenshot: onViewScreenshot,
          ),
        );
      },
    );
  }
}

// ── Individual payment card ───────────────────────────────────────────────────

class _PaymentCard extends StatelessWidget {
  final PaymentModel payment;
  final void Function(String)? onApprove;
  final void Function(String)? onReject;
  final void Function(String)? onDelete;
  final void Function(String) onViewScreenshot;

  const _PaymentCard({
    required this.payment,
    this.onApprove,
    this.onReject,
    this.onDelete,
    required this.onViewScreenshot,
  });

  @override
  Widget build(BuildContext context) {
    final p = payment;
    final statusColor = p.isApproved
        ? AppColors.success
        : p.isRejected
            ? AppColors.error
            : AppColors.warning;
    final methodColor = p.paymentMethod == 'KPay'
        ? const Color(0xFFE5007E)
        : const Color(0xFF003087);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Header ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Row(children: [
            // Method badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: methodColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.paymentMethod,
                  style: GoogleFonts.poppins(
                      color: methodColor,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${p.amount.toStringAsFixed(0)} MMK',
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
            ),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(p.status.toUpperCase(),
                  style: GoogleFonts.poppins(
                      color: statusColor,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
        // ── Details ──────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (p.orderId != null)
              Text('Order: ${p.orderId}',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 12)),
            Text(
              p.createdAt != null
                  ? '${p.createdAt!.day}/${p.createdAt!.month}/${p.createdAt!.year}  ${p.createdAt!.hour.toString().padLeft(2, '0')}:${p.createdAt!.minute.toString().padLeft(2, '0')}'
                  : '',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 11),
            ),
            if (p.adminNote.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Note: ${p.adminNote}',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 12,
                      fontStyle: FontStyle.italic)),
            ],
          ]),
        ),
        // ── Screenshot thumbnail ─────────────────────────────────────────
        if (p.screenshotUrl.isNotEmpty) ...[
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => onViewScreenshot(p.screenshotUrl),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(bottom: Radius.circular(0)),
              child: CachedNetworkImage(
                imageUrl: p.screenshotUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                    height: 160,
                    color: AppColors.surface,
                    child: const Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary, strokeWidth: 2))),
                errorWidget: (_, __, ___) => Container(
                    height: 80,
                    color: AppColors.surface,
                    child: Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            color: AppColors.textMedium))),
              ),
            ),
          ),
        ],
        // ── Actions ──────────────────────────────────────────────────────
        if (onApprove != null || onReject != null || onDelete != null) ...[
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(children: [
              if (onReject != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onReject!(p.id),
                    icon: const Icon(Icons.close_rounded, size: 16),
                    label: Text('Reject',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onApprove != null && onReject != null)
                const SizedBox(width: 10),
              if (onApprove != null)
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => onApprove!(p.id),
                    icon: const Icon(Icons.check_rounded,
                        size: 16, color: Colors.white),
                    label: Text('Approve',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              if (onDelete != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => onDelete!(p.id),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: Text('Delete',
                        style: GoogleFonts.poppins(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(
                          color: AppColors.error.withValues(alpha: 0.4)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

String _capitalize(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();

String _formatNumber(double v) {
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
  return v.toStringAsFixed(0);
}

int _parseInt(dynamic v) {
  if (v == null) return 0;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

double _parseDouble(dynamic v) {
  if (v == null) return 0.0;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0.0;
  return 0.0;
}

Future<bool> _showConfirm(
    BuildContext context, String title, String message) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(title,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600)),
      content: Text(message,
          style:
              GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13)),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium))),
        TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Delete',
                style: GoogleFonts.poppins(color: AppColors.error))),
      ],
    ),
  );
  return result ?? false;
}

class _DiagRow extends StatelessWidget {
  final String label;
  final String value;
  final bool ok;

  const _DiagRow({required this.label, required this.value, required this.ok});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle_rounded : Icons.error_rounded,
          color: ok ? AppColors.success : AppColors.error,
          size: 15,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.poppins(fontSize: 12, height: 1.4),
              children: [
                TextSpan(
                    text: '$label: ',
                    style: TextStyle(color: AppColors.textMedium)),
                TextSpan(
                    text: value,
                    style: TextStyle(
                        color: ok ? AppColors.textPrimary : AppColors.error,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _RadioOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _RadioOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: 2,
                ),
              ),
              child: selected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Manage grid data model
// ─────────────────────────────────────────────────────────────────────────────
class _ManageItem {
  final String label;
  final IconData icon;
  final LinearGradient gradient;
  final Widget page;
  final String? subtitle;
  const _ManageItem({
    required this.label,
    required this.icon,
    required this.gradient,
    required this.page,
    this.subtitle,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Manage Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminManageTab extends StatefulWidget {
  const _AdminManageTab();
  @override
  State<_AdminManageTab> createState() => _AdminManageTabState();
}

class _AdminManageTabState extends State<_AdminManageTab> {
  int _products = 0, _orders = 0, _users = 0, _pending = 0;
  final List<StreamSubscription> _subs = [];

  @override
  void initState() {
    super.initState();
    final db = FirebaseFirestore.instance;
    _subs.add(db.collection('products').snapshots().listen((s) {
      if (mounted) setState(() => _products = s.docs.length);
    }));
    _subs.add(db.collection('orders').snapshots().listen((s) {
      if (mounted) setState(() => _orders = s.docs.length);
    }));
    _subs.add(db.collection('users').snapshots().listen((s) {
      if (mounted)
        setState(() => _users =
            s.docs.where((d) => (d['role'] ?? 'user') == 'user').length);
    }));
    _subs.add(db
        .collection('payments')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((s) {
      if (mounted) setState(() => _pending = s.docs.length);
    }));
  }

  @override
  void dispose() {
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      _ManageItem(
        label: 'Products',
        icon: Icons.inventory_2_rounded,
        gradient: AppColors.gradient1,
        subtitle: '$_products items',
        page: const _AdminProductsTab(),
      ),
      _ManageItem(
        label: 'Orders',
        icon: Icons.receipt_long_rounded,
        gradient: AppColors.gradient2,
        subtitle: '$_orders total',
        page: const _AdminOrdersTab(),
      ),
      _ManageItem(
        label: 'Users',
        icon: Icons.people_rounded,
        gradient: AppColors.gradient3,
        subtitle: '$_users users',
        page: const _AdminUsersTab(),
      ),
      _ManageItem(
        label: 'Chat',
        icon: Icons.chat_bubble_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFFFF9F43), Color(0xFFFFCA80)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        page: const _AdminChatTab(),
      ),
      _ManageItem(
        label: 'Categories',
        icon: Icons.category_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF43D9AD), Color(0xFF26C6DA)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        page: const _AdminCategoriesTab(),
      ),
      _ManageItem(
        label: 'Notify',
        icon: Icons.notifications_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF9C8FFF), Color(0xFF6C63FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        page: const _AdminNotificationsTab(),
      ),
      _ManageItem(
        label: 'Payments',
        icon: Icons.account_balance_wallet_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF1DD1A1), Color(0xFF55EFC4)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        subtitle: _pending > 0 ? '$_pending pending' : null,
        page: const _AdminPaymentsTab(),
      ),
      _ManageItem(
        label: 'Banners',
        icon: Icons.photo_size_select_actual_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFFE84393), Color(0xFFFF6B9D)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        page: const _AdminBannersTab(),
      ),
      _ManageItem(
        label: 'Announce',
        icon: Icons.campaign_rounded,
        gradient: const LinearGradient(
            colors: [Color(0xFF5F72FF), Color(0xFF9B59B6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        page: const _AdminAnnouncementsTab(),
      ),
    ];

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Manage',
                        style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontSize: 26,
                            fontWeight: FontWeight.w800)),
                    Text('Tap to manage your store',
                        style: GoogleFonts.poppins(
                            color: AppColors.textMedium, fontSize: 13)),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.isDesktop(context)
                      ? 5
                      : Responsive.isTablet(context)
                          ? 5
                          : 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 1.0,
                ),
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final item = items[i];
                    final hasBadge = item.label == 'Payments' && _pending > 0;
                    return GestureDetector(
                      onTap: () => Navigator.push(
                          ctx, MaterialPageRoute(builder: (_) => item.page)),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: item.gradient,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: item.gradient.colors.first
                                  .withValues(alpha: 0.35),
                              blurRadius: 14,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Stack(
                          children: [
                            // Large decorative icon in bottom-right
                            Positioned(
                              right: -12,
                              bottom: -12,
                              child: Icon(
                                item.icon,
                                size: 72,
                                color: Colors.white.withValues(alpha: 0.12),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  // Icon box
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.22),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(item.icon,
                                        color: Colors.white, size: 22),
                                  ),
                                  // Label + subtitle
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(item.label,
                                          style: GoogleFonts.poppins(
                                              color: Colors.white,
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700)),
                                      if (item.subtitle != null)
                                        Container(
                                          margin: const EdgeInsets.only(top: 3),
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: hasBadge
                                                ? const Color(0xFFFF9F43)
                                                    .withValues(alpha: 0.9)
                                                : Colors.white
                                                    .withValues(alpha: 0.20),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                          ),
                                          child: Text(item.subtitle!,
                                              style: GoogleFonts.poppins(
                                                  color: Colors.white,
                                                  fontSize: 10,
                                                  fontWeight: hasBadge
                                                      ? FontWeight.w700
                                                      : FontWeight.w500)),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            // Arrow in top-right
                            Positioned(
                              top: 12,
                              right: 12,
                              child: Container(
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.arrow_forward_rounded,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  childCount: items.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Settings Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminSettingsTab extends StatelessWidget {
  const _AdminSettingsTab();

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final locale = Get.find<LocaleController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
          children: [
            // ── Title ─────────────────────────────────────────────────────
            Text('Settings',
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 24),

            // ── Profile card ──────────────────────────────────────────────
            Obx(() {
              final user = auth.user.value;
              return Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  gradient: AppColors.gradient1,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(children: [
                  Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      (user?.name ?? 'A').substring(0, 1).toUpperCase(),
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(user?.name ?? 'Admin',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(user?.email ?? '',
                              style: GoogleFonts.poppins(
                                  color: Colors.white.withValues(alpha: 0.8),
                                  fontSize: 12)),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 3),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text('Administrator',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                  ),
                ]),
              );
            }),
            const SizedBox(height: 28),

            // ── Appearance ────────────────────────────────────────────────
            _SettingsSection(title: 'Appearance', children: [
              Obx(() {
                final isDark = locale.isDark.value;
                return _SettingsTile(
                  icon: isDark
                      ? Icons.dark_mode_rounded
                      : Icons.light_mode_rounded,
                  iconColor: AppColors.warning,
                  title: 'Theme',
                  subtitle: isDark ? 'Dark mode' : 'Light mode',
                  trailing: Switch(
                    value: isDark,
                    onChanged: (_) => locale.toggleTheme(),
                    activeThumbColor: AppColors.primary,
                    activeTrackColor: AppColors.primaryLight,
                  ),
                );
              }),
            ]),
            const SizedBox(height: 16),

            // ── Language ──────────────────────────────────────────────────
            _SettingsSection(title: 'Admin Language', children: [
              Obx(() {
                final isMM = locale.adminIsMyanmar;
                return _SettingsTile(
                  icon: Icons.language_rounded,
                  iconColor: AppColors.accent,
                  title: 'Admin Language',
                  subtitle: isMM ? 'မြန်မာဘာသာ' : 'English',
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    _LangChip(
                        label: 'MM',
                        selected: isMM,
                        onTap: () => locale.setAdminMyanmar()),
                    const SizedBox(width: 6),
                    _LangChip(
                        label: 'EN',
                        selected: !isMM,
                        onTap: () => locale.setAdminEnglish()),
                  ]),
                );
              }),
            ]),
            const SizedBox(height: 16),

            // ── Hardware ──────────────────────────────────────────────────
            const _HardwareSettingsSection(),
            const SizedBox(height: 16),

            // ── App Info ──────────────────────────────────────────────────
            _SettingsSection(title: 'About', children: [
              _SettingsTile(
                icon: Icons.storefront_rounded,
                iconColor: AppColors.primary,
                title: 'App Name',
                subtitle: 'TSfootwear',
              ),
              _SettingsTile(
                icon: Icons.info_outline_rounded,
                iconColor: AppColors.textMedium,
                title: 'Version',
                subtitle: '1.0.0',
              ),
              _SettingsTile(
                icon: Icons.build_rounded,
                iconColor: AppColors.textMedium,
                title: 'Build',
                subtitle: 'Production',
              ),
            ]),
            const SizedBox(height: 28),

            // ── Logout ────────────────────────────────────────────────────
            GestureDetector(
              onTap: () => _confirmLogout(context),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border:
                      Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                ),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.logout_rounded, color: AppColors.error, size: 18),
                  const SizedBox(width: 10),
                  Text('Logout',
                      style: GoogleFonts.poppins(
                          color: AppColors.error,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Logout',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
        content: Text('Are you sure you want to logout?',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13)),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text('Cancel',
                  style: GoogleFonts.poppins(color: AppColors.textMedium))),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text('Logout',
                  style: GoogleFonts.poppins(
                      color: AppColors.error, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    if (ok != true) return;
    await Get.find<AuthController>().logout();
    goTo('/login');
  }
}

// ── Settings helper widgets ───────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(title,
            style: GoogleFonts.poppins(
                color: AppColors.textMedium,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5)),
      ),
      Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: children.asMap().entries.map((e) {
            final isLast = e.key == children.length - 1;
            return Column(children: [
              e.value,
              if (!isLast)
                Divider(
                    height: 1,
                    thickness: 0.8,
                    color: AppColors.border,
                    indent: 54),
            ]);
          }).toList(),
        ),
      ),
    ]);
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.subtitle = '',
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, color: iconColor, size: 17),
        ),
        const SizedBox(width: 14),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (subtitle.isNotEmpty)
              Text(subtitle,
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 11)),
          ]),
        ),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

class _LangChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _LangChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: selected ? AppColors.gradient1 : null,
          color: selected ? null : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? Colors.transparent : AppColors.border),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: selected ? Colors.white : AppColors.textMedium,
                fontSize: 11,
                fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Banners Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AdminBannersTab extends StatefulWidget {
  const _AdminBannersTab();
  @override
  State<_AdminBannersTab> createState() => _AdminBannersTabState();
}

class _AdminBannersTabState extends State<_AdminBannersTab> {
  final _bannerService = BannerService();

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _deleteBanner(BannerModel banner) async {
    final ok = await _showConfirm(
        context, 'Delete Banner', 'Remove this banner? This cannot be undone.');
    if (!ok) return;
    try {
      // Delete image from server too
      final token = await AuthService().getIdToken() ?? '';
      if (banner.imageUrl.isNotEmpty && token.isNotEmpty) {
        await UploadService().deleteImage(banner.imageUrl, token);
      }
      await _bannerService.deleteBanner(banner.id);
      if (mounted) _snack('Banner deleted', AppColors.success);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _toggleActive(BannerModel banner) async {
    try {
      await _bannerService.toggleActive(banner.id, !banner.isActive);
    } catch (e) {
      if (mounted) _snack(e.toString(), AppColors.error);
    }
  }

  void _showBannerSheet(BannerModel? existing) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BannerFormSheet(
        existing: existing,
        onSaved: () {
          if (mounted) _snack('Banner saved', AppColors.success);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Banners',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admin_banners_fab',
        onPressed: () => _showBannerSheet(null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<List<BannerModel>>(
        stream: _bannerService.allBannersStream(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: AppColors.primary));
          }
          final banners = snap.data ?? [];
          if (banners.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_size_select_actual_outlined,
                      size: 64, color: AppColors.textLight),
                  const SizedBox(height: 12),
                  Text('No banners yet',
                      style: GoogleFonts.poppins(
                          color: AppColors.textMedium, fontSize: 15)),
                  const SizedBox(height: 6),
                  Text('Tap + to add your first banner',
                      style: GoogleFonts.poppins(
                          color: AppColors.textLight, fontSize: 13)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: banners.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _BannerCard(
              banner: banners[i],
              onEdit: () => _showBannerSheet(banners[i]),
              onDelete: () => _deleteBanner(banners[i]),
              onToggle: () => _toggleActive(banners[i]),
            ),
          );
        },
      ),
    );
  }
}

class _BannerCard extends StatelessWidget {
  final BannerModel banner;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  const _BannerCard({
    required this.banner,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image preview
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(15)),
            child: banner.imageUrl.isNotEmpty
                ? CachedNetworkImage(
                    imageUrl: UploadService.fixUrl(banner.imageUrl),
                    height: 140,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(
                        height: 140,
                        color: AppColors.border,
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary, strokeWidth: 2))),
                    errorWidget: (_, __, ___) => Container(
                        height: 140,
                        color: AppColors.border,
                        child: const Icon(Icons.broken_image_outlined,
                            color: Colors.white54, size: 36)),
                  )
                : Container(
                    height: 140,
                    color: AppColors.border,
                    child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: Colors.white54, size: 36)),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (banner.title.isNotEmpty)
                        Text(banner.title,
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: AppColors.textPrimary),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      if (banner.subtitle.isNotEmpty)
                        Text(banner.subtitle,
                            style: GoogleFonts.poppins(
                                fontSize: 12, color: AppColors.textMedium),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text('Order: ${banner.order}',
                              style: GoogleFonts.poppins(
                                  fontSize: 11, color: AppColors.textLight)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: banner.isActive
                                  ? AppColors.success.withValues(alpha: 0.12)
                                  : AppColors.border,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              banner.isActive ? 'Active' : 'Hidden',
                              style: GoogleFonts.poppins(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: banner.isActive
                                    ? AppColors.success
                                    : AppColors.textLight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Toggle active
                Switch(
                  value: banner.isActive,
                  onChanged: (_) => onToggle(),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primary,
                ),
                // Edit
                IconButton(
                  icon: Icon(Icons.edit_rounded,
                      color: AppColors.primary, size: 20),
                  onPressed: onEdit,
                ),
                // Delete
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded,
                      color: AppColors.error, size: 20),
                  onPressed: onDelete,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Banner Add/Edit sheet ──────────────────────────────────────────────────

class _BannerFormSheet extends StatefulWidget {
  final BannerModel? existing;
  final VoidCallback onSaved;

  const _BannerFormSheet({this.existing, required this.onSaved});

  @override
  State<_BannerFormSheet> createState() => _BannerFormSheetState();
}

class _BannerFormSheetState extends State<_BannerFormSheet> {
  final _titleCtrl = TextEditingController();
  final _subtitleCtrl = TextEditingController();
  final _orderCtrl = TextEditingController();

  Uint8List? _imageBytes;
  String _imageFilename = '';
  String _existingUrl = '';
  bool _isActive = true;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final b = widget.existing;
    if (b != null) {
      _titleCtrl.text = b.title;
      _subtitleCtrl.text = b.subtitle;
      _orderCtrl.text = b.order.toString();
      _existingUrl = b.imageUrl;
      _isActive = b.isActive;
    } else {
      _orderCtrl.text = '0';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _orderCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _imageBytes = bytes;
        _imageFilename = picked.name.isNotEmpty ? picked.name : 'banner.jpg';
      });
    }
  }

  Future<void> _save() async {
    if (_imageBytes == null && _existingUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Please pick an image'),
          backgroundColor: AppColors.error));
      return;
    }
    setState(() => _isLoading = true);
    try {
      final token = await AuthService().getIdToken() ?? '';

      String imageUrl = _existingUrl;
      if (_imageBytes != null) {
        imageUrl = await UploadService()
            .uploadImageBytes(_imageBytes!, _imageFilename, token);
        if (_existingUrl.isNotEmpty) {
          await UploadService().deleteImage(_existingUrl, token);
        }
      }

      final order = int.tryParse(_orderCtrl.text.trim()) ?? 0;
      final service = BannerService();

      if (widget.existing == null) {
        await service.createBanner(
          imageUrl: imageUrl,
          title: _titleCtrl.text.trim(),
          subtitle: _subtitleCtrl.text.trim(),
          isActive: _isActive,
          order: order,
        );
      } else {
        await service.updateBanner(widget.existing!.id, {
          'imageUrl': imageUrl,
          'title': _titleCtrl.text.trim(),
          'subtitle': _subtitleCtrl.text.trim(),
          'isActive': _isActive,
          'order': order,
        });
      }

      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString()), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.5,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: ctrl,
          padding: EdgeInsets.fromLTRB(
              20, 16, 20, MediaQuery.of(context).viewInsets.bottom + 24),
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 20),
            Text(isEdit ? 'Edit Banner' : 'New Banner',
                style: GoogleFonts.poppins(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 20),

            // Image picker
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                height: 160,
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: AppColors.border, style: BorderStyle.solid),
                ),
                clipBehavior: Clip.antiAlias,
                child: _imageBytes != null
                    ? Image.memory(_imageBytes!,
                        fit: BoxFit.cover, width: double.infinity)
                    : _existingUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: UploadService.fixUrl(_existingUrl),
                            fit: BoxFit.cover,
                            width: double.infinity,
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate_rounded,
                                  size: 40, color: AppColors.textLight),
                              const SizedBox(height: 8),
                              Text('Tap to pick image',
                                  style: GoogleFonts.poppins(
                                      color: AppColors.textLight,
                                      fontSize: 13)),
                            ],
                          ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _pickImage,
              icon: const Icon(Icons.photo_library_rounded, size: 18),
              label: Text(_imageBytes != null || _existingUrl.isNotEmpty
                  ? 'Change image'
                  : 'Pick image'),
            ),
            const SizedBox(height: 16),

            // Title
            TextField(
              controller: _titleCtrl,
              decoration: InputDecoration(
                labelText: 'Title (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Subtitle
            TextField(
              controller: _subtitleCtrl,
              decoration: InputDecoration(
                labelText: 'Subtitle (optional)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Order
            TextField(
              controller: _orderCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Display order (0 = first)',
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),

            // Active toggle
            Row(
              children: [
                Text('Show on home page',
                    style: GoogleFonts.poppins(
                        fontSize: 14, color: AppColors.textPrimary)),
                const Spacer(),
                Switch(
                  value: _isActive,
                  onChanged: (v) => setState(() => _isActive = v),
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.primary,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Save button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Update Banner' : 'Add Banner',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin Announcements Tab
// ─────────────────────────────────────────────────────────────────────────────
class _AdminAnnouncementsTab extends StatefulWidget {
  const _AdminAnnouncementsTab();
  @override
  State<_AdminAnnouncementsTab> createState() => _AdminAnnouncementsTabState();
}

class _AdminAnnouncementsTabState extends State<_AdminAnnouncementsTab> {
  final _service = AnnouncementService();
  List<AnnouncementModel> _items = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('announcements')
          .orderBy('createdAt', descending: true)
          .get();
      _items = snap.docs
          .map((d) => AnnouncementModel.fromJson({'id': d.id, ...d.data()}))
          .toList();
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _snack(String msg, Color c) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(msg, style: GoogleFonts.poppins(color: Colors.white)),
          backgroundColor: c,
          behavior: SnackBarBehavior.floating));

  Future<void> _toggle(AnnouncementModel a) async {
    try {
      await _service.toggleActive(a.id, !a.isActive);
      _fetch();
    } catch (e) {
      _snack(e.toString(), AppColors.error);
    }
  }

  Future<void> _delete(AnnouncementModel a) async {
    final ok =
        await _showConfirm(context, 'Delete', '"${a.title}" will be removed.');
    if (!ok) return;
    try {
      await _service.delete(a.id);
      _fetch();
      _snack('Deleted', AppColors.success);
    } catch (e) {
      _snack(e.toString(), AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        automaticallyImplyLeading: true,
        title: Text('Announcements',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
              icon: Icon(Icons.refresh_rounded, color: AppColors.textMedium),
              onPressed: _fetch),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'admin_announce_fab',
        backgroundColor: AppColors.primary,
        onPressed: () async {
          await _showAnnouncementSheet(context, null);
          _fetch();
        },
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline_rounded,
                      color: AppColors.error, size: 48),
                  const SizedBox(height: 12),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.poppins(
                          color: AppColors.textMedium, fontSize: 13)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _fetch, child: const Text('Retry')),
                ]))
              : _items.isEmpty
                  ? const _EmptyState(
                      icon: Icons.campaign_outlined,
                      label: 'No announcements yet')
                  : RefreshIndicator(
                      onRefresh: _fetch,
                      color: AppColors.primary,
                      backgroundColor: AppColors.card,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                        itemCount: _items.length,
                        itemBuilder: (_, i) => _AnnouncementCard(
                          item: _items[i],
                          onToggle: () => _toggle(_items[i]),
                          onEdit: () async {
                            await _showAnnouncementSheet(context, _items[i]);
                            _fetch();
                          },
                          onDelete: () => _delete(_items[i]),
                        ),
                      ),
                    ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  final AnnouncementModel item;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _AnnouncementCard(
      {required this.item,
      required this.onToggle,
      required this.onEdit,
      required this.onDelete});

  static const _typeIcon = {
    'new_product': Icons.new_releases_rounded,
    'app_update': Icons.system_update_rounded,
    'promotion': Icons.local_offer_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = UploadService.fixUrl(item.imageUrl);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (imageUrl.isNotEmpty)
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            child: CachedNetworkImage(
              imageUrl: imageUrl,
              width: double.infinity,
              height: 140,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(_typeIcon[item.type] ?? Icons.campaign_rounded,
                  size: 14, color: AppColors.primary),
              const SizedBox(width: 5),
              Text(
                item.type.replaceAll('_', ' ').toUpperCase(),
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
              ),
              const Spacer(),
              Transform.scale(
                scale: 0.85,
                child: Switch(
                  value: item.isActive,
                  onChanged: (_) => onToggle(),
                  activeThumbColor: AppColors.success,
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(item.title,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            if (item.body.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(item.body,
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 12),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 10),
            Row(children: [
              _StatusChip(status: item.isActive ? 'active' : 'inactive'),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.edit_rounded,
                    color: AppColors.primary, size: 18),
                onPressed: onEdit,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              IconButton(
                icon: Icon(Icons.delete_rounded,
                    color: AppColors.error, size: 18),
                onPressed: onDelete,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
          ]),
        ),
      ]),
    );
  }
}

Future<void> _showAnnouncementSheet(
    BuildContext context, AnnouncementModel? existing) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AnnouncementFormSheet(existing: existing),
  );
}

class _AnnouncementFormSheet extends StatefulWidget {
  final AnnouncementModel? existing;
  const _AnnouncementFormSheet({this.existing});
  @override
  State<_AnnouncementFormSheet> createState() => _AnnouncementFormSheetState();
}

class _AnnouncementFormSheetState extends State<_AnnouncementFormSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  final _imageUrlCtrl = TextEditingController();
  final _productIdCtrl = TextEditingController();
  String _type = 'promotion';
  bool _isLoading = false;
  String? _formError; // shown inline so it's never hidden behind the sheet
  Uint8List? _imageBytes;
  String? _imageFileName;

  static const _types = ['promotion', 'new_product', 'app_update'];
  static const _typeLabels = {
    'promotion': 'Promotion',
    'new_product': 'New Product',
    'app_update': 'App Update',
  };

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _titleCtrl.text = e.title;
      _bodyCtrl.text = e.body;
      _imageUrlCtrl.text = e.imageUrl;
      _productIdCtrl.text = e.productId;
      _type = e.type;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    _imageUrlCtrl.dispose();
    _productIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    setState(() {
      _imageBytes = bytes;
      _imageFileName = picked.path.split('/').last;
      _imageUrlCtrl.clear();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _formError = null;
    });
    try {
      String imageUrl = _imageUrlCtrl.text.trim();
      if (_imageBytes != null && _imageFileName != null) {
        final token = await AuthService().getIdToken();
        if (token == null) throw Exception('Not authenticated');
        imageUrl = await UploadService()
            .uploadImageBytes(_imageBytes!, _imageFileName!, token);
      }

      // Explicit <String, dynamic> so FieldValue.serverTimestamp() can be
      // inserted by AnnouncementService.create() without a type error on web.
      final data = <String, dynamic>{
        'title': _titleCtrl.text.trim(),
        'body': _bodyCtrl.text.trim(),
        'imageUrl': imageUrl,
        'type': _type,
        'productId': _productIdCtrl.text.trim(),
      };

      final svc = AnnouncementService();
      if (widget.existing == null) {
        await svc.create(data);
        // Broadcast announcement to all users as an in-app notification + FCM push
        _broadcastAnnouncement(
          title: data['title'] as String,
          body: (data['body'] as String).isNotEmpty
              ? data['body'] as String
              : data['title'] as String,
        );
      } else {
        await FirebaseFirestore.instance
            .collection('announcements')
            .doc(widget.existing!.id)
            .update({...data, 'updatedAt': FieldValue.serverTimestamp()});
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      // ScaffoldMessenger snackbars are hidden behind modal bottom sheets,
      // so we show the error both inline (always visible) and via Get.snackbar
      // (global overlay, appears above the sheet).
      if (mounted) setState(() => _formError = e.toString());
      Get.snackbar(
        'Failed to save',
        e.toString(),
        backgroundColor: AppColors.error,
        colorText: Colors.white,
        snackPosition: SnackPosition.BOTTOM,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 6),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Non-fatal: saves individual in-app notifications for every user + sends FCM push.
  // Runs fire-and-forget — never blocks announcement creation.
  void _broadcastAnnouncement({required String title, required String body}) {
    () async {
      try {
        final snap = await FirebaseFirestore.instance
            .collection('users')
            .where('role', isEqualTo: 'user')
            .get();

        // Save an individual notification doc for each user so they see it
        // in their notification screen regardless of Firestore index state.
        for (final doc in snap.docs) {
          try {
            await NotificationModel.save(
              userId: doc.id,
              title: title,
              body: body,
              type: 'promo',
              data: {'source': 'announcement'},
            );
          } catch (e) {
            debugPrint('[Announcement] in-app save failed for ${doc.id}: $e');
          }
        }

        // Send FCM push to all users via backend
        final token = await AuthService().getIdToken();
        if (token == null) return;
        await NotificationService().sendToAllUsers(
          title: title,
          body: body,
          firebaseIdToken: token,
          data: {'type': 'announcement'},
        );
      } catch (e) {
        debugPrint('[Announcement] broadcast failed: $e');
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final previewUrl = _imageUrlCtrl.text.trim().isNotEmpty
        ? UploadService.fixUrl(_imageUrlCtrl.text.trim())
        : '';

    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.97,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(isEdit ? 'Edit Announcement' : 'New Announcement',
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
                IconButton(
                    icon:
                        Icon(Icons.close_rounded, color: AppColors.textMedium),
                    onPressed: () => Navigator.of(context).pop()),
              ],
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: ctrl,
              padding: EdgeInsets.fromLTRB(
                  20, 8, 20, MediaQuery.of(context).viewInsets.bottom + 24),
              child: Form(
                key: _formKey,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Type chips
                      Text('Type',
                          style: GoogleFonts.poppins(
                              color: AppColors.textMedium, fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: _types.map((t) {
                          final sel = _type == t;
                          return ChoiceChip(
                            label: Text(_typeLabels[t] ?? t),
                            selected: sel,
                            onSelected: (_) => setState(() => _type = t),
                            selectedColor: AppColors.primary,
                            labelStyle: GoogleFonts.poppins(
                                color:
                                    sel ? Colors.white : AppColors.textMedium,
                                fontSize: 12,
                                fontWeight: FontWeight.w500),
                            backgroundColor: AppColors.surface,
                            side: BorderSide(
                                color:
                                    sel ? AppColors.primary : AppColors.border),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),

                      _Field(
                          ctrl: _titleCtrl,
                          label: 'Title *',
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Required'
                              : null),
                      const SizedBox(height: 14),
                      _Field(ctrl: _bodyCtrl, label: 'Message', maxLines: 3),
                      const SizedBox(height: 14),

                      // Image
                      Text('Image',
                          style: GoogleFonts.poppins(
                              color: AppColors.textMedium, fontSize: 13)),
                      const SizedBox(height: 6),
                      if (_imageBytes != null)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.memory(_imageBytes!,
                              width: double.infinity,
                              height: 160,
                              fit: BoxFit.cover),
                        )
                      else if (previewUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: CachedNetworkImage(
                            imageUrl: previewUrl,
                            width: double.infinity,
                            height: 160,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      const SizedBox(height: 8),
                      Row(children: [
                        OutlinedButton.icon(
                          icon:
                              const Icon(Icons.photo_library_rounded, size: 16),
                          label: const Text('Gallery'),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.primary,
                              side: BorderSide(color: AppColors.primary)),
                          onPressed: _pickImage,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: _imageUrlCtrl,
                            onChanged: (_) => setState(() {}),
                            style: GoogleFonts.poppins(
                                color: AppColors.textPrimary, fontSize: 13),
                            decoration: InputDecoration(
                              labelText: 'or paste URL',
                              labelStyle: GoogleFonts.poppins(fontSize: 12),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 14),

                      _Field(
                          ctrl: _productIdCtrl,
                          label:
                              'Product ID (optional — adds "View Product" button)'),
                      const SizedBox(height: 24),

                      // Inline error — always visible even inside a bottom sheet
                      if (_formError != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.4)),
                          ),
                          child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.error_outline_rounded,
                                    color: AppColors.error, size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(_formError!,
                                      style: GoogleFonts.poppins(
                                          color: AppColors.error,
                                          fontSize: 12)),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 12),
                      ],

                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submit,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2))
                              : Text(isEdit ? 'Update' : 'Publish',
                                  style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hardware Settings Section
// ─────────────────────────────────────────────────────────────────────────────

class _HardwareSettingsSection extends StatefulWidget {
  const _HardwareSettingsSection();

  @override
  State<_HardwareSettingsSection> createState() =>
      _HardwareSettingsSectionState();
}

class _HardwareSettingsSectionState extends State<_HardwareSettingsSection> {
  static const _keyPaperWidth = 'pos_paper_width';

  int _paperWidth = 80;
  bool _scannerOk = false;
  String _lastScan = '';
  final _scanCtrl = TextEditingController();
  final _scanFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _scanCtrl.dispose();
    _scanFocus.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _paperWidth = prefs.getInt(_keyPaperWidth) ?? 80;
    });
  }

  Future<void> _savePaperWidth(int w) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyPaperWidth, w);
    setState(() => _paperWidth = w);
  }

  void _onScanSubmit(String value) {
    final v = value.trim();
    if (v.isEmpty) return;
    setState(() {
      _scannerOk = true;
      _lastScan = v;
    });
    _scanCtrl.clear();
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _scannerOk = false);
    });
  }

  Future<void> _runTestPrint() async {
    final widthMm = _paperWidth.toDouble();
    await Printing.layoutPdf(
      name: 'Test Print',
      onLayout: (_) async {
        final doc = pw.Document();
        doc.addPage(pw.Page(
          pageFormat: PdfPageFormat(
            widthMm * PdfPageFormat.mm,
            double.infinity,
            marginAll: 4 * PdfPageFormat.mm,
          ),
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text('TSfootwear',
                  style: pw.TextStyle(
                      fontSize: 16, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text('** TEST PRINT **',
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
              pw.Divider(),
              pw.Text('Paper width: ${_paperWidth}mm',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.Text(
                  'Printer: ${BtPrinterService.to.connectedDevice.value?.name ?? "USB / Default"}',
                  style: const pw.TextStyle(fontSize: 10)),
              pw.SizedBox(height: 8),
              pw.Text('Printer is working correctly.',
                  style: const pw.TextStyle(fontSize: 10)),
            ],
          ),
        ));
        return Uint8List.fromList(await doc.save());
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSection(title: 'Hardware', children: [
      _SettingsTile(
        icon: Icons.qr_code_scanner_rounded,
        iconColor: const Color(0xFF00B894),
        title: 'USB Barcode Scanner',
        subtitle: _scannerOk
            ? 'Scanned: $_lastScan'
            : 'Plug in USB scanner — works automatically',
        trailing: _scannerOk
            ? const Icon(Icons.check_circle_rounded,
                color: Color(0xFF00B894), size: 20)
            : TextButton(
                onPressed: () => _showScannerTestDialog(context),
                child: Text('Test',
                    style: GoogleFonts.poppins(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
      ),
      _SettingsTile(
        icon: Icons.receipt_long_rounded,
        iconColor: AppColors.primary,
        title: 'Receipt Paper Width',
        subtitle: 'Affects PDF receipt size',
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          _PaperChip(
              label: '58mm',
              selected: _paperWidth == 58,
              onTap: () => _savePaperWidth(58)),
          const SizedBox(width: 6),
          _PaperChip(
              label: '80mm',
              selected: _paperWidth == 80,
              onTap: () => _savePaperWidth(80)),
        ]),
      ),
      _SettingsTile(
        icon: Icons.print_rounded,
        iconColor: AppColors.accent,
        title: 'USB Thermal Printer',
        subtitle: 'Install driver → appears in print dialog',
        trailing: TextButton(
          onPressed: _runTestPrint,
          child: Text('Test Print',
              style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
        ),
      ),
      Obx(() {
        final bt = BtPrinterService.to;
        final connected = bt.isConnected.value;
        final deviceName = bt.connectedDevice.value?.name ?? '';
        return _SettingsTile(
          icon: connected
              ? Icons.bluetooth_connected_rounded
              : Icons.bluetooth_rounded,
          iconColor:
              connected ? const Color(0xFF00B894) : const Color(0xFF0984E3),
          title: 'Bluetooth Thermal Printer',
          subtitle: connected
              ? 'Connected: $deviceName'
              : (bt.connectedDevice.value?.name != null
                  ? 'Last: ${bt.connectedDevice.value!.name}'
                  : 'Not connected'),
          trailing: TextButton(
            onPressed: () => _showBtSetupDialog(context),
            child: Text(connected ? 'Manage' : 'Connect',
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
        );
      }),
    ]);
  }

  void _showScannerTestDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Text('Test Barcode Scanner',
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF00B894).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: const Color(0xFF00B894).withValues(alpha: 0.3)),
              ),
              child: Column(children: [
                const Icon(Icons.qr_code_scanner_rounded,
                    size: 36, color: Color(0xFF00B894)),
                const SizedBox(height: 8),
                Text('Point the scanner at a barcode',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textMedium)),
              ]),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _scanCtrl,
              focusNode: _scanFocus,
              autofocus: true,
              onSubmitted: (v) {
                _onScanSubmit(v);
                Navigator.pop(context);
              },
              style: GoogleFonts.poppins(
                  fontSize: 14, color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Scan here...',
                filled: true,
                fillColor: AppColors.bg,
                prefixIcon: const Icon(Icons.qr_code_rounded, size: 18),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 8),
            Text('Scanner sends barcode + Enter automatically',
                style: GoogleFonts.poppins(
                    fontSize: 11, color: AppColors.textLight)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
        ],
      ),
    );
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _scanFocus.requestFocus());
  }

  void _showBtSetupDialog(BuildContext context) {
    final bt = BtPrinterService.to;
    // Load devices immediately when dialog opens
    if (!kIsWeb) bt.loadPairedDevices();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        title: Row(children: [
          Icon(Icons.bluetooth_rounded, color: AppColors.primary, size: 22),
          const SizedBox(width: 10),
          Text('Bluetooth Printer',
              style: GoogleFonts.poppins(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.textPrimary)),
        ]),
        content: SizedBox(
          width: 360,
          child: Obx(() {
            final isConnected = bt.isConnected.value;
            final isConnecting = bt.isConnecting.value;
            final isScanning = bt.isScanning.value;
            final devices = bt.devices;
            final connected = bt.connectedDevice.value;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Connection status banner
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isConnected
                        ? const Color(0xFF00B894).withValues(alpha: 0.1)
                        : AppColors.bg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isConnected
                          ? const Color(0xFF00B894).withValues(alpha: 0.4)
                          : AppColors.border,
                    ),
                  ),
                  child: Row(children: [
                    Icon(
                      isConnected
                          ? Icons.bluetooth_connected_rounded
                          : Icons.bluetooth_disabled_rounded,
                      size: 18,
                      color: isConnected
                          ? const Color(0xFF00B894)
                          : AppColors.textLight,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isConnected
                            ? 'Connected: ${connected?.name ?? ''}'
                            : 'Not connected',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isConnected
                              ? const Color(0xFF00B894)
                              : AppColors.textMedium,
                        ),
                      ),
                    ),
                    if (isConnected)
                      TextButton(
                        onPressed: isConnecting ? null : () => bt.disconnect(),
                        child: Text('Disconnect',
                            style: GoogleFonts.poppins(
                                fontSize: 11, color: AppColors.secondary)),
                      ),
                  ]),
                ),

                const SizedBox(height: 14),

                // Paired devices header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Paired Devices',
                        style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textMedium)),
                    TextButton.icon(
                      onPressed:
                          isScanning ? null : () => bt.loadPairedDevices(),
                      icon: isScanning
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, size: 14),
                      label: Text(isScanning ? 'Loading...' : 'Refresh',
                          style: GoogleFonts.poppins(fontSize: 11)),
                      style: TextButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4)),
                    ),
                  ],
                ),

                // Device list
                if (kIsWeb)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'Bluetooth printing requires the Android app.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textMedium),
                    ),
                  )
                else if (isScanning && devices.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (devices.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      'No paired devices found.\n'
                      'Pair your printer in Android Settings → Bluetooth first.',
                      style: GoogleFonts.poppins(
                          fontSize: 12, color: AppColors.textMedium),
                    ),
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: devices.length,
                      itemBuilder: (_, i) {
                        final d = devices[i];
                        final isCurrent =
                            connected?.address == d.address && isConnected;
                        return Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? const Color(0xFF00B894)
                                    .withValues(alpha: 0.08)
                                : AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? const Color(0xFF00B894)
                                      .withValues(alpha: 0.4)
                                  : AppColors.border,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            leading: Icon(
                              isCurrent
                                  ? Icons.bluetooth_connected_rounded
                                  : Icons.bluetooth_rounded,
                              color: isCurrent
                                  ? const Color(0xFF00B894)
                                  : const Color(0xFF0984E3),
                              size: 20,
                            ),
                            title: Text(d.name,
                                style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary)),
                            subtitle: Text(d.address,
                                style: GoogleFonts.poppins(
                                    fontSize: 10, color: AppColors.textLight)),
                            trailing: isCurrent
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF00B894)
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('Connected',
                                        style: GoogleFonts.poppins(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: const Color(0xFF00B894))),
                                  )
                                : isConnecting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2))
                                    : ElevatedButton(
                                        onPressed: () => bt.connect(d),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 6),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                          textStyle: GoogleFonts.poppins(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600),
                                        ),
                                        child: const Text('Connect'),
                                      ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          if (!kIsWeb)
            Obx(() => ElevatedButton.icon(
                  onPressed: BtPrinterService.to.isConnected.value
                      ? _runTestPrint
                      : null,
                  icon: const Icon(Icons.print_rounded, size: 16),
                  label: Text('Test Print',
                      style: GoogleFonts.poppins(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor:
                          AppColors.textLight.withValues(alpha: 0.3)),
                )),
        ],
      ),
    );
  }
}

class _PaperChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PaperChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : AppColors.textMedium)),
      ),
    );
  }
}
