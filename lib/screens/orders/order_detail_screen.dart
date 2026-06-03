import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../controllers/order_controller.dart';
import '../../models/order_model.dart';

class OrderDetailScreen extends StatefulWidget {
  final String orderId;
  const OrderDetailScreen({super.key, required this.orderId});

  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<OrderController>().listenToOrder(widget.orderId);
    });
  }

  @override
  void dispose() {
    Get.find<OrderController>().cancelOrderStream();
    super.dispose();
  }

  static const _timelineSteps = [
    _TimelineStep(labelKey: 'status_pending', icon: Icons.receipt_outlined, status: 'pending'),
    _TimelineStep(labelKey: 'status_confirmed', icon: Icons.check_circle_outline_rounded, status: 'confirmed'),
    _TimelineStep(labelKey: 'status_processing', icon: Icons.inventory_2_outlined, status: 'processing'),
    _TimelineStep(labelKey: 'status_shipped', icon: Icons.local_shipping_outlined, status: 'shipped'),
    _TimelineStep(labelKey: 'status_delivered', icon: Icons.home_outlined, status: 'delivered'),
  ];

  int _currentStepIndex(OrderModel order) {
    final s = order.status.toLowerCase();
    if (s == 'cancelled' || s == 'refunded') return -1;
    for (int i = 0; i < _timelineSteps.length; i++) {
      if (_timelineSteps[i].status == s) return i;
    }
    return 0;
  }

  void _confirmCancel(OrderModel order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'cancel_order'.tr,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'cancel_order_confirm'.tr,
          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('keep_order'.tr,
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('cancel_order'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.secondary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      final orderController = Get.find<OrderController>();
      final success = await orderController.cancelOrder(order.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'order_cancelled'.tr
                : (orderController.error.value ?? 'failed_cancel_order'.tr),
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: success ? AppColors.accent : AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(),
      body: Obx(() {
        final orderController = Get.find<OrderController>();
        if (orderController.isLoading.value &&
            orderController.selectedOrder.value == null) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        if (orderController.error.value != null &&
            orderController.selectedOrder.value == null) {
          return _buildErrorState(orderController);
        }
        final order = orderController.selectedOrder.value;
        if (order == null) {
          return const Center(
              child: CircularProgressIndicator(color: AppColors.primary));
        }
        return _buildBody(order);
      }),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary),
        onPressed: () => Navigator.pop(context),
      ),
      title: Text(
        'order_detail'.tr,
        style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildErrorState(OrderController orderController) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline_rounded,
              color: AppColors.secondary, size: 56),
          const SizedBox(height: 14),
          Text(
            'failed_load_order'.tr,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            orderController.error.value ?? '',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => orderController.listenToOrder(widget.orderId),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                  gradient: AppColors.gradient1,
                  borderRadius: BorderRadius.circular(12)),
              child: Text('retry'.tr,
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(OrderModel order) {
    final orderRef = order.orderNumber.isNotEmpty
        ? order.orderNumber
        : '#${order.id.substring(0, 8).toUpperCase()}';
    final dateStr = order.createdAt != null
        ? DateFormat('MMMM dd, yyyy  •  hh:mm a').format(order.createdAt!)
        : 'Date unknown';
    final isCancellable = order.status.toLowerCase() == 'pending' ||
        order.status.toLowerCase() == 'confirmed';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Order ref + date + status
          _buildOrderHeader(order, orderRef, dateStr),
          const SizedBox(height: 20),
          // Timeline
          _buildTimeline(order),
          const SizedBox(height: 20),
          // Tracking number
          if (order.trackingNumber.isNotEmpty)
            _buildTrackingCard(order.trackingNumber),
          if (order.trackingNumber.isNotEmpty) const SizedBox(height: 16),
          // Items list
          _buildItemsCard(order),
          const SizedBox(height: 16),
          // Shipping address
          _buildShippingCard(order),
          const SizedBox(height: 16),
          // Payment summary
          _buildPaymentCard(order),
          const SizedBox(height: 20),
          // Cancel button
          if (isCancellable) _buildCancelButton(order),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  Widget _buildOrderHeader(OrderModel order, String orderRef, String dateStr) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                orderRef,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              _buildStatusChip(order),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            dateStr,
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(OrderModel order) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: order.statusColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: order.statusColor.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: order.statusColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            order.statusLabel,
            style: GoogleFonts.poppins(
                color: order.statusColor,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(OrderModel order) {
    final currentStep = _currentStepIndex(order);
    final isCancelled = order.status.toLowerCase() == 'cancelled' ||
        order.status.toLowerCase() == 'refunded';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'order_status'.tr,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          if (isCancelled)
            _buildCancelledBanner(order)
          else
            Column(
              children: List.generate(_timelineSteps.length, (index) {
                final step = _timelineSteps[index];
                final isDone = currentStep >= index;
                final isActive = currentStep == index;
                final isLast = index == _timelineSteps.length - 1;
                return _buildTimelineStep(
                  step: step,
                  isDone: isDone,
                  isActive: isActive,
                  isLast: isLast,
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _buildCancelledBanner(OrderModel order) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.cancel_outlined,
              color: AppColors.secondary, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.statusLabel,
                  style: GoogleFonts.poppins(
                      color: AppColors.secondary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  'This order has been ${order.status.toLowerCase()}.',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineStep({
    required _TimelineStep step,
    required bool isDone,
    required bool isActive,
    required bool isLast,
  }) {
    final Color nodeColor = isDone
        ? (isActive ? AppColors.primary : AppColors.accent)
        : AppColors.border;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 40,
            child: Column(
              children: [
                // Node
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: isDone
                        ? nodeColor.withValues(alpha: 0.15)
                        : AppColors.surface,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: nodeColor, width: isActive ? 2 : 1.5),
                  ),
                  child: Icon(
                    step.icon,
                    size: 16,
                    color: isDone ? nodeColor : AppColors.textMedium,
                  ),
                ),
                // Connector line
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      decoration: BoxDecoration(
                        color: isDone && !isActive
                            ? AppColors.accent
                            : AppColors.border,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 16, top: 6),
              child: Text(
                step.labelKey.tr,
                style: GoogleFonts.poppins(
                  color: isDone ? AppColors.textPrimary : AppColors.textMedium,
                  fontSize: 13,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingCard(String trackingNumber) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.local_shipping_outlined,
                color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'tracking_number'.tr,
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 11),
                ),
                Text(
                  trackingNumber,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('tracking_copied'.tr,
                      style: GoogleFonts.poppins(color: Colors.white)),
                  backgroundColor: AppColors.accent,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: Icon(Icons.copy_rounded,
                color: AppColors.primary, size: 18),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsCard(OrderModel order) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'order_items'.tr,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700),
                ),
                Text(
                  '${order.items.length} item${order.items.length == 1 ? '' : 's'}',
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 12),
                ),
              ],
            ),
          ),
          Divider(color: AppColors.border, height: 1),
          ...order.items.map((item) => _buildOrderItemRow(item)),
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(OrderItemModel item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: item.image.isEmpty
                ? Container(
                    width: 60,
                    height: 60,
                    color: AppColors.surface,
                    child: Icon(Icons.image_not_supported_outlined,
                        color: AppColors.textMedium, size: 24),
                  )
                : CachedNetworkImage(
                    imageUrl: item.image,
                    width: 60,
                    height: 60,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                      width: 60,
                      height: 60,
                      color: AppColors.surface,
                      child: Icon(Icons.broken_image_outlined,
                          color: AppColors.textMedium, size: 24),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (item.size.isNotEmpty)
                      _buildAttrChip('Size: ${item.size}'),
                    if (item.size.isNotEmpty && item.color.isNotEmpty)
                      const SizedBox(width: 6),
                    if (item.color.isNotEmpty)
                      _buildAttrChip('Color: ${item.color}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fmtPrice(item.subtotal)}',
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                'x${item.quantity}  @${fmtPrice(item.price)}',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAttrChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 10),
      ),
    );
  }

  Widget _buildShippingCard(OrderModel order) {
    final addr = order.shippingAddress;
    final lines = [
      addr['name'] as String? ?? '',
      addr['street'] as String? ?? '',
      if ((addr['phone'] as String? ?? '').isNotEmpty)
        'Phone: ${addr['phone']}',
    ].where((s) => s.isNotEmpty).toList();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.location_on_outlined,
                    color: AppColors.accent, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'shipping_address'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            Text('no_address'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 13))
          else
            ...lines.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  line,
                  style: GoogleFonts.poppins(
                      color: AppColors.textMedium, fontSize: 13),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPaymentCard(OrderModel order) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.receipt_outlined,
                    color: AppColors.warning, size: 18),
              ),
              const SizedBox(width: 10),
              Text(
                'payment_summary'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _summaryRow('Items', '${fmtPrice(order.itemsPrice)}'),
          const SizedBox(height: 6),
          _summaryRow(
            'Shipping',
            order.shippingPrice == 0.0
                ? 'FREE'
                : '${fmtPrice(order.shippingPrice)}',
            valueColor: order.shippingPrice == 0.0 ? AppColors.accent : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: AppColors.border),
          ),
          _summaryRow('Total', '${fmtPrice(order.totalPrice)}',
              isBold: true, valueColor: AppColors.primary),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(Icons.payment_rounded,
                  color: AppColors.textMedium, size: 15),
              const SizedBox(width: 6),
              Text(
                '${'payment_label'.tr} ',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 12),
              ),
              Text(
                order.paymentMethod.isNotEmpty ? order.paymentMethod : 'N/A',
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: (order.isPaid ? AppColors.accent : AppColors.warning)
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  order.isPaid ? 'paid'.tr : 'unpaid'.tr,
                  style: GoogleFonts.poppins(
                    color: order.isPaid ? AppColors.accent : AppColors.warning,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value,
      {bool isBold = false, Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isBold ? AppColors.textPrimary : AppColors.textMedium,
            fontSize: isBold ? 14 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: isBold ? 16 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildCancelButton(OrderModel order) {
    return Obx(() {
      final orderController = Get.find<OrderController>();
      return GestureDetector(
        onTap: orderController.isLoading.value
            ? null
            : () => _confirmCancel(order),
        child: Container(
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: AppColors.secondary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: AppColors.secondary.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Center(
            child: orderController.isLoading.value
                ? const CircularProgressIndicator(
                    color: AppColors.secondary, strokeWidth: 2)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cancel_outlined,
                          color: AppColors.secondary, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'cancel_order'.tr,
                        style: GoogleFonts.poppins(
                            color: AppColors.secondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
          ),
        ),
      );
    });
  }
}

class _TimelineStep {
  final String labelKey;
  final IconData icon;
  final String status;
  const _TimelineStep(
      {required this.labelKey, required this.icon, required this.status});
}
