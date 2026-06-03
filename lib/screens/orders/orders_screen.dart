import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/order_controller.dart';
import '../../models/order_model.dart';
import '../../widgets/login_required.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  static const _tabs = [
    _TabInfo(labelKey: 'tab_all', filter: null),
    _TabInfo(labelKey: 'tab_pending', filter: 'pending'),
    _TabInfo(labelKey: 'tab_processing', filter: 'processing'),
    _TabInfo(labelKey: 'tab_shipped', filter: 'shipped'),
    _TabInfo(labelKey: 'tab_delivered', filter: 'delivered'),
    _TabInfo(labelKey: 'tab_cancelled', filter: 'cancelled'),
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = Get.find<AuthController>().user.value?.id ?? '';
      Get.find<OrderController>().listenToUserOrders(uid);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<OrderModel> _filterOrders(List<OrderModel> orders, String? filter) {
    if (filter == null) return orders;
    return orders.where((o) => o.status.toLowerCase() == filter).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = Get.find<AuthController>().isLoggedIn;
    if (!isLoggedIn) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(),
        body: LoginRequired(
          title: 'my_orders'.tr,
          subtitle: 'orders_login_sub'.tr,
          icon: Icons.receipt_long_outlined,
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Obx(() {
        final orderProvider = Get.find<OrderController>();
        if (orderProvider.isLoading.value && orderProvider.orders.isEmpty) {
          return const Center(child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (orderProvider.error.value != null && orderProvider.orders.isEmpty) {
          return _buildErrorState(orderProvider);
        }
        return TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final filtered = _filterOrders(orderProvider.orders, tab.filter);
            return _buildOrderList(filtered, orderProvider.isLoading.value);
          }).toList(),
        );
      }),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'my_orders'.tr,
        style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 20, fontWeight: FontWeight.w700),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(46),
        child: Container(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 16),
            indicatorColor: AppColors.primary,
            indicatorWeight: 2.5,
            indicatorSize: TabBarIndicatorSize.label,
            labelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400),
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textMedium,
            dividerColor: Colors.transparent,
            tabs: _tabs.map((t) => Tab(text: t.labelKey.tr)).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(OrderController orderProvider) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded, color: AppColors.secondary, size: 56),
          const SizedBox(height: 14),
          Text(
            'failed_load_orders'.tr,
            style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            orderProvider.error.value ?? '',
            style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => orderProvider.fetchUserOrders(
              Get.find<AuthController>().user.value?.id ?? '',
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'retry'.tr,
                style: GoogleFonts.poppins(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderList(List<OrderModel> orders, bool isLoading) {
    if (orders.isEmpty && !isLoading) {
      return _buildEmptyState();
    }
    return RefreshIndicator(
      color: AppColors.primary,
      backgroundColor: AppColors.card,
      onRefresh: () async => Get.find<OrderController>().listenToUserOrders(
        Get.find<AuthController>().user.value?.id ?? '',
      ),
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) => _buildOrderCard(orders[index]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(Icons.receipt_long_outlined, size: 52, color: AppColors.textMedium),
          ),
          const SizedBox(height: 20),
          Text(
            'no_orders'.tr,
            style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            'no_orders_sub'.tr,
            style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderCard(OrderModel order) {
    final dateStr = order.createdAt != null
        ? DateFormat('MMM dd, yyyy').format(order.createdAt!)
        : 'Date unknown';
    final orderRef = order.orderNumber.isNotEmpty ? order.orderNumber : '#${order.id.substring(0, 8).toUpperCase()}';
    final previewItems = order.items.take(3).toList();

    return GestureDetector(
      onTap: () => pushTo('/orders/${order.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          orderRef,
                          style: GoogleFonts.poppins(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          dateStr,
                          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  // Status chip
                  _buildStatusChip(order),
                ],
              ),
              const SizedBox(height: 12),
              // Item thumbnails
              if (previewItems.isNotEmpty)
                Row(
                  children: [
                    ...previewItems.map((item) => _buildItemThumbnail(item)),
                    if (order.items.length > 3)
                      Container(
                        width: 44,
                        height: 44,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Text(
                            '+${order.items.length - 3}',
                            style: GoogleFonts.poppins(
                              color: AppColors.textMedium,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    const Spacer(),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${fmtPrice(order.totalPrice)}',
                          style: GoogleFonts.poppins(
                            color: AppColors.primary,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              // View details arrow
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    'view_details'.tr,
                    style: GoogleFonts.poppins(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_forward_ios_rounded, color: AppColors.primary, size: 12),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemThumbnail(OrderItemModel item) {
    return Container(
      width: 44,
      height: 44,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: item.image.isEmpty
            ? Icon(Icons.image_not_supported_outlined, color: AppColors.textMedium, size: 18)
            : CachedNetworkImage(
                imageUrl: item.image,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(
                  Icons.broken_image_outlined,
                  color: AppColors.textMedium,
                  size: 18,
                ),
              ),
      ),
    );
  }

  Widget _buildStatusChip(OrderModel order) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: order.statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: order.statusColor.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: order.statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            order.statusLabel,
            style: GoogleFonts.poppins(
              color: order.statusColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabInfo {
  final String labelKey;
  final String? filter;
  const _TabInfo({required this.labelKey, required this.filter});
}
