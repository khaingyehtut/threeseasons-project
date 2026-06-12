import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/cart_controller.dart';
import '../../controllers/order_controller.dart';
import '../../models/cart_model.dart';
import '../../widgets/login_required.dart';
import '../../services/payment_service.dart';
import '../map/map_picker_screen.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  double _mandalayFee = 3000.0;
  StreamSubscription<double>? _deliverySub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = Get.find<AuthController>().user.value?.id;
      if (uid != null) Get.find<CartController>().fetchCart(uid);
    });
    _deliverySub = PaymentService().mandalayFeeStream().listen((fee) {
      if (mounted) setState(() => _mandalayFee = fee);
    });
  }

  @override
  void dispose() {
    _deliverySub?.cancel();
    super.dispose();
  }

  double _computeShipping(double subtotal) => _mandalayFee;

  double _computeTotal(double subtotal) =>
      subtotal + _computeShipping(subtotal);

  void _showCheckoutSheet(CartController cartProvider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CheckoutSheet(
        cartProvider: cartProvider,
        subtotal: cartProvider.totalPrice,
        mandalayFee: _mandalayFee,
        onOrderPlaced: (orderRef, paymentMethod, total, orderId) {
          if (!mounted) return;
          if (paymentMethod == 'KPay' || paymentMethod == 'Wave Money') {
            pushTo('/payment', extra: {'amount': total, 'orderId': orderId});
          } else {
            _showSuccessDialog(orderRef);
          }
        },
      ),
    );
  }

  void _showSuccessDialog(String orderRef) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: AppColors.gradient3,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              'order_placed'.tr,
              style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'order_placed_msg'.tr,
              style: GoogleFonts.poppins(
                color: AppColors.textMedium,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              'order_ref'.trParams({'ref': orderRef}),
              style: GoogleFonts.poppins(
                color: AppColors.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.of(context, rootNavigator: true).pop();
                goTo('/main');
                WidgetsBinding.instance.addPostFrameCallback((_) => pushTo('/orders'));
              },
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: BoxDecoration(
                  gradient: AppColors.gradient1,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'view_orders'.tr,
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: () {
                Navigator.of(context, rootNavigator: true).pop();
                goTo('/main');
              },
              child: Text(
                'continue_shopping'.tr,
                style: GoogleFonts.poppins(
                  color: AppColors.textMedium,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final auth = Get.find<AuthController>();
      final isLoggedIn =
          auth.isLoggedIn || FirebaseAuth.instance.currentUser != null;
      if (!isLoggedIn) {
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: _buildAppBar(),
          body: LoginRequired(
            title: 'cart_awaits'.tr,
            subtitle: 'cart_login_sub'.tr,
            icon: Icons.shopping_cart_outlined,
          ),
        );
      }
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(),
        body: Obx(() {
          final cartProvider = Get.find<CartController>();
          if (cartProvider.isLoading.value && cartProvider.items.isEmpty) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (cartProvider.isEmpty) {
            return _buildEmptyCart();
          }
          return _buildCartContent(cartProvider);
        }),
      );
    });
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      title: Obx(() {
        final cartProvider = Get.find<CartController>();
        return Row(
          children: [
            Text(
              'my_cart'.tr,
              style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (cartProvider.totalItems > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  gradient: AppColors.gradient1,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${cartProvider.totalItems}',
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        );
      }),
    );
  }

  Widget _buildEmptyCart() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              color: AppColors.card,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.border),
            ),
            child: Icon(
              Icons.shopping_bag_outlined,
              size: 68,
              color: AppColors.textMedium,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'cart_empty'.tr,
            style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'cart_empty_sub'.tr,
            style: GoogleFonts.poppins(
              color: AppColors.textMedium,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          GestureDetector(
            onTap: () => goTo('/main'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 14),
              decoration: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                'shop_now'.tr,
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCartContent(CartController cartProvider) {
    final subtotal = cartProvider.totalPrice;
    final shipping = _computeShipping(subtotal);
    final total = _computeTotal(subtotal);

    return Column(
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: cartProvider.items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = cartProvider.items[index];
              return _buildCartItem(item, cartProvider);
            },
          ),
        ),
        _buildOrderSummary(subtotal, shipping, total, cartProvider),
      ],
    );
  }

  Widget _buildCartItem(CartItemModel item, CartController cartProvider) {
    return Dismissible(
      key: Key(item.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: AppColors.secondary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.secondary.withValues(alpha: 0.3)),
        ),
        child: Icon(
          Icons.delete_outline_rounded,
          color: AppColors.secondary,
          size: 26,
        ),
      ),
      confirmDismiss: (_) async {
        return await _confirmRemove(context, item.product.name);
      },
      onDismissed: (_) {
        final uid = Get.find<AuthController>().user.value?.id ?? '';
        cartProvider.removeItem(uid, item.id);
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: item.product.firstImage.isEmpty
                    ? Container(
                        width: 72,
                        height: 72,
                        color: AppColors.surface,
                        child: Icon(
                          Icons.image_not_supported_outlined,
                          color: AppColors.textMedium,
                          size: 28,
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: item.product.firstImage,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: AppColors.surface,
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.textMedium,
                            size: 28,
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.product.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: AppColors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () async {
                            final uid =
                                Get.find<AuthController>().user.value?.id ?? '';
                            final confirmed = await _confirmRemove(
                              context,
                              item.product.name,
                            );
                            if (confirmed == true) {
                              cartProvider.removeItem(uid, item.id);
                            }
                          },
                          child: Icon(
                            Icons.close_rounded,
                            color: AppColors.textMedium,
                            size: 18,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (item.size.isNotEmpty)
                          _buildAttributeChip('${'size'.tr}: ${item.size}'),
                        if (item.color.isNotEmpty)
                          _buildAttributeChip('${'color'.tr}: ${item.color}'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          '${fmtPrice(item.subtotal)}',
                          style: GoogleFonts.poppins(
                            color: AppColors.primary,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        _buildQuantityStepper(item, cartProvider),
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

  Widget _buildAttributeChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.border),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(
          color: AppColors.textMedium,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildQuantityStepper(
    CartItemModel item,
    CartController cartProvider,
  ) {
    return Container(
      height: 30,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: item.quantity > 1
                ? () {
                    final uid = Get.find<AuthController>().user.value?.id ?? '';
                    cartProvider.updateItem(uid, item.id, item.quantity - 1);
                  }
                : null,
            child: SizedBox(
              width: 28,
              height: 30,
              child: Icon(
                Icons.remove_rounded,
                size: 14,
                color: item.quantity > 1 ? AppColors.primary : AppColors.border,
              ),
            ),
          ),
          SizedBox(
            width: 28,
            child: Center(
              child: Text(
                '${item.quantity}',
                style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          GestureDetector(
            onTap: () {
              final uid = Get.find<AuthController>().user.value?.id ?? '';
              cartProvider.updateItem(uid, item.id, item.quantity + 1);
            },
            child: SizedBox(
              width: 28,
              height: 30,
              child: Icon(
                Icons.add_rounded,
                size: 14,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderSummary(
    double subtotal,
    double shipping,
    double total,
    CartController cartProvider,
  ) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.of(context).padding.bottom + 20,
      ),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: AppColors.border)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSummaryRow('subtotal'.tr, '${fmtPrice(subtotal)}'),
          const SizedBox(height: 6),
          _buildSummaryRow(
            'shipping'.tr,
            shipping == 0.0 ? 'free'.tr : '${fmtPrice(shipping)}',
            valueColor: shipping == 0.0 ? AppColors.accent : null,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppColors.border, thickness: 1),
          ),
          _buildSummaryRow(
            'total'.tr,
            '${fmtPrice(total)}',
            isBold: true,
            valueColor: AppColors.primary,
          ),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _showCheckoutSheet(cartProvider),
            child: Container(
              width: double.infinity,
              height: 52,
              decoration: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Text(
                  'proceed_checkout'.tr,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            color: isBold ? AppColors.textPrimary : AppColors.textMedium,
            fontSize: isBold ? 15 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: isBold ? 17 : 13,
            fontWeight: isBold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Future<bool?> _confirmRemove(BuildContext context, String productName) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'remove_item'.tr,
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
        content: Text(
          'remove_confirm'.trParams({'name': productName}),
          style: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'cancel'.tr,
              style: GoogleFonts.poppins(color: AppColors.textMedium),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'remove'.tr,
              style: GoogleFonts.poppins(
                color: AppColors.secondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Checkout bottom sheet
// ─────────────────────────────────────────────────────────────

class _CheckoutSheet extends StatefulWidget {
  final CartController cartProvider;
  final double subtotal;
  final double mandalayFee;
  final void Function(String orderRef, String paymentMethod, double total, String orderId) onOrderPlaced;

  const _CheckoutSheet({
    required this.cartProvider,
    required this.subtotal,
    required this.mandalayFee,
    required this.onOrderPlaced,
  });

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _streetCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  String _paymentMethod = 'Cash on Delivery';
  bool _isPlacing = false;
  double? _pickedLat;
  double? _pickedLng;

  double get _shipping => widget.mandalayFee;

  double get _total => widget.subtotal + _shipping;

  @override
  void initState() {
    super.initState();
    final user = Get.find<AuthController>().user.value;
    if (user != null) {
      if (user.name.isNotEmpty) _nameCtrl.text = user.name;
      if (user.phone.isNotEmpty) _phoneCtrl.text = user.phone;
      final street = user.address?['street']?.toString() ?? '';
      if (street.isNotEmpty) _streetCtrl.text = street;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _streetCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _openMapPicker() async {
    final initialPos = (_pickedLat != null && _pickedLng != null)
        ? LatLng(_pickedLat!, _pickedLng!)
        : null;
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => MapPickerScreen(
          initialPosition: initialPos,
          initialAddress: _streetCtrl.text.trim().isNotEmpty
              ? _streetCtrl.text.trim()
              : null,
        ),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _streetCtrl.text = result['address'] as String? ?? '';
        _pickedLat = result['lat'] as double?;
        _pickedLng = result['lng'] as double?;
      });
    }
  }

  Future<void> _placeOrder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isPlacing = true);

    final orderProvider = Get.find<OrderController>();
    final shippingAddress = {
      'name': _nameCtrl.text.trim(),
      'street': _streetCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      if (_pickedLat != null) 'lat': _pickedLat,
      if (_pickedLng != null) 'lng': _pickedLng,
    };

    final uid = Get.find<AuthController>().user.value?.id ?? '';
    final cartItems = widget.cartProvider.items;
    final order = await orderProvider.placeOrder(
      uid,
      cartItems,
      shippingAddress,
      _paymentMethod,
      shippingPrice: _shipping,
    );
    if (!mounted) return;
    setState(() => _isPlacing = false);

    if (order != null) {
      await widget.cartProvider.clearCart(uid);
      if (!mounted) return;
      final orderRef = order.orderNumber.isNotEmpty ? order.orderNumber : order.id;
      Navigator.pop(context);
      widget.onOrderPlaced(orderRef, _paymentMethod, _total, order.id);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            orderProvider.error.value ?? 'failed_load_orders'.tr,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.92,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'checkout'.tr,
                      style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.close_rounded,
                        color: AppColors.textMedium,
                      ),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionTitle('shipping_address'.tr),
                        const SizedBox(height: 12),
                        _buildField(
                          _nameCtrl,
                          'name_field'.tr,
                          Icons.person_outline_rounded,
                        ),
                        const SizedBox(height: 10),
                        _buildField(
                          _streetCtrl,
                          'street_field'.tr,
                          Icons.location_on_outlined,
                          suffix: IconButton(
                            icon: Icon(Icons.map_outlined,
                                color: AppColors.primary, size: 20),
                            tooltip: 'Pick on map',
                            onPressed: _openMapPicker,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildField(
                          _phoneCtrl,
                          'phone_field'.tr,
                          Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle('payment_method'.tr),
                        const SizedBox(height: 12),
                        _buildPaymentOption(
                          'cash_on_delivery'.tr,
                          Icons.money_rounded,
                          value: 'Cash on Delivery',
                        ),
                        const SizedBox(height: 8),
                        _buildPaymentOption(
                          'KPay (KBZ Pay)',
                          Icons.account_balance_wallet_rounded,
                          value: 'KPay',
                          accentColor: const Color(0xFFE5007E),
                          imagePath: 'assets/icons/kpay.png',
                        ),
                        const SizedBox(height: 8),
                        _buildPaymentOption(
                          'Wave Money',
                          Icons.waves_rounded,
                          value: 'Wave Money',
                          accentColor: const Color(0xFF003087),
                          imagePath: 'assets/icons/wavepay.png',
                        ),
                        const SizedBox(height: 8),
                        _buildPaymentOption(
                          'card'.tr,
                          Icons.credit_card_rounded,
                          value: 'Card',
                          isCosmetic: true,
                        ),
                        const SizedBox(height: 24),
                        _sectionTitle('order_summary'.tr),
                        const SizedBox(height: 12),
                        _buildSheetSummaryRow(
                          'items_label'.tr,
                          fmtPrice(widget.cartProvider.totalPrice),
                        ),
                        const SizedBox(height: 6),
                        _buildSheetSummaryRow(
                          'shipping'.tr,
                          fmtPrice(_shipping),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Divider(color: AppColors.border),
                        ),
                        _buildSheetSummaryRow(
                          'total'.tr,
                          fmtPrice(_total),
                          isBold: true,
                          valueColor: AppColors.primary,
                        ),
                        const SizedBox(height: 24),
                        GestureDetector(
                          onTap: _isPlacing ? null : _placeOrder,
                          child: Container(
                            width: double.infinity,
                            height: 54,
                            decoration: BoxDecoration(
                              gradient: _isPlacing ? null : AppColors.gradient1,
                              color: _isPlacing ? AppColors.surface : null,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: _isPlacing
                                  ? const CircularProgressIndicator(
                                      color: AppColors.primary,
                                      strokeWidth: 2,
                                    )
                                  : Text(
                                      'place_order'.trParams({
                                        'total': fmtPrice(_total),
                                      }),
                                      style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: MediaQuery.of(context).padding.bottom + 16,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        color: AppColors.textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildField(
    TextEditingController ctrl,
    String hint,
    IconData icon, {
    TextInputType keyboardType = TextInputType.text,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: ctrl,
      keyboardType: keyboardType,
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(
          color: AppColors.textMedium,
          fontSize: 13,
        ),
        filled: true,
        fillColor: AppColors.surface,
        prefixIcon: Icon(icon, color: AppColors.textMedium, size: 18),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.secondary),
        ),
      ),
      validator: (v) => (v == null || v.trim().isEmpty) ? 'required'.tr : null,
    );
  }

  Widget _buildPaymentOption(
    String label,
    IconData icon, {
    required String value,
    bool isCosmetic = false,
    Color? accentColor,
    String? imagePath,
  }) {
    final isSelected = _paymentMethod == value;
    final highlight = accentColor ?? AppColors.primary;
    return GestureDetector(
      onTap: () {
        if (!isCosmetic) {
          setState(() => _paymentMethod = value);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'card_coming_soon'.tr,
                style: GoogleFonts.poppins(color: Colors.white),
              ),
              backgroundColor: AppColors.surface,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              isSelected ? highlight.withValues(alpha: 0.1) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? highlight : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            if (imagePath != null)
              Image.asset(imagePath, width: 24, height: 24)
            else
              Icon(
                icon,
                color: isSelected ? highlight : AppColors.textMedium,
                size: 20,
              ),
            const SizedBox(width: 12),
            Text(
              label,
              style: GoogleFonts.poppins(
                color: isSelected ? highlight : AppColors.textMedium,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
            if (isCosmetic) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  'coming_soon'.tr,
                  style: GoogleFonts.poppins(
                    color: AppColors.warning,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const Spacer(),
            if (isSelected && !isCosmetic)
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.check_rounded,
                  color: Colors.white,
                  size: 13,
                ),
              )
            else
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.border, width: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSheetSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
  }) {
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
}
