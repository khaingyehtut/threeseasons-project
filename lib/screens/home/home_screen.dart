import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:shimmer/shimmer.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../core/navigation.dart';
import '../../models/banner_model.dart';
import '../../models/category_model.dart';
import '../../models/product_model.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/cart_controller.dart';
import '../../controllers/notification_controller.dart';
import '../../controllers/product_controller.dart';
import '../../controllers/announcement_controller.dart';
import '../../models/announcement_model.dart';
import '../../services/banner_service.dart';
import '../../services/notification_service.dart';
import '../../services/upload_service.dart';
import '../../widgets/category_chip.dart';
import '../../widgets/product_card.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;

  bool _notifPermissionDenied = false;
  bool _isShowingAnnouncement = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadData();
      _checkNotificationPermission();
      _checkAnnouncements();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkAnnouncements();
      if (!kIsWeb) {
        FirebaseInAppMessaging.instance.triggerEvent('app_open');
      }
    }
  }

  Future<void> refreshAnnouncements() => _checkAnnouncements();

  Future<void> _checkNotificationPermission() async {
    // getNotificationSettings() calls Notification.requestPermission() on web,
    // which Chrome blocks unless triggered by a user gesture. Skip on web.
    if (kIsWeb) return;
    try {
      final settings =
          await FirebaseMessaging.instance.getNotificationSettings();
      final denied =
          settings.authorizationStatus == AuthorizationStatus.denied ||
              settings.authorizationStatus == AuthorizationStatus.notDetermined;
      if (mounted && denied != _notifPermissionDenied) {
        setState(() => _notifPermissionDenied = denied);
      }
    } catch (_) {}
  }

  Future<void> _requestNotificationPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional) {
      // Token saving was skipped when denied — retry now
      final auth = Get.find<AuthController>();
      if (auth.user.value != null) {
        final token = await NotificationService().getTokenOrEmpty();
        if (token.isNotEmpty) {
          await FirebaseMessaging.instance
              .getToken()
              .then((_) => null); // warms up token
        }
        await auth.retryFcmToken();
      }
      if (mounted) setState(() => _notifPermissionDenied = false);
    } else {
      // Already permanently denied — tell user where to go manually
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
            'Go to Settings → Apps → TSfootwear → Notifications and enable them.',
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: const Color(0xFF323232),
          duration: const Duration(seconds: 6),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  void _loadData() {
    final pp = Get.find<ProductController>();
    pp.fetchFeaturedProducts();
    pp.fetchCategories();
    pp.fetchProducts(reset: true);
  }

  Future<void> _onRefresh() async {
    final pp = Get.find<ProductController>();
    await Future.wait([
      pp.fetchFeaturedProducts(),
      pp.fetchCategories(),
      pp.fetchProducts(reset: true),
    ]);
  }

  Future<void> _checkAnnouncements() async {
    if (_isShowingAnnouncement) return;
    final ctrl = Get.find<AnnouncementController>();
    await ctrl.fetchActive();
    await _showUnseenIfAny(ctrl);
  }

  Future<void> _showUnseenIfAny(AnnouncementController ctrl) async {
    if (!mounted || _isShowingAnnouncement) return;
    final active = ctrl.announcements;
    if (active.isEmpty || !mounted) return;
    _isShowingAnnouncement = true;
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) {
      _isShowingAnnouncement = false;
      return;
    }
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => _AnnouncementDialog(announcement: active.first),
    );
    _isShowingAnnouncement = false;
  }

  void _onSearchChanged(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      Get.find<ProductController>().setSearch(q);
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    super.dispose();
  }

  // ── Sort options ──────────────────────────────────────────────────────────
  Map<String, String> get _sortOptions => {
        'newest': 'sort_newest'.tr,
        'price_asc': 'sort_price_asc'.tr,
        'price_desc': 'sort_price_desc'.tr,
        'rating': 'sort_rated'.tr,
      };

  @override
  Widget build(BuildContext context) {
    final auth = Get.find<AuthController>();
    final firstName = auth.user.value?.name.split(' ').first ?? 'there';

    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'good_morning'.tr
        : hour < 17
            ? 'good_afternoon'.tr
            : 'good_evening'.tr;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: RefreshIndicator(
        onRefresh: _onRefresh,
        color: AppColors.primary,
        backgroundColor: AppColors.card,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // ── 1. SliverAppBar ──────────────────────────────────────────────
            _buildSliverAppBar(greeting, firstName),

            // ── 2. Notification permission banner (shown only when denied) ──
            if (_notifPermissionDenied)
              SliverToBoxAdapter(child: _buildNotifBanner()),

            // ── 3. Banner Carousel — hidden while searching ──────────────────
            SliverToBoxAdapter(
              child: Obx(() {
                final pp = Get.find<ProductController>();
                if (pp.searchQuery.value.isNotEmpty)
                  return const SizedBox.shrink();
                return const _DynamicBannerCarousel();
              }),
            ),

            // ── 3. Categories ────────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildCategoriesSection()),

            // ── 4. Featured Products ─────────────────────────────────────────
            SliverToBoxAdapter(child: _buildFeaturedSection()),

            // ── 5. All Products grid + sort ──────────────────────────────────
            SliverToBoxAdapter(child: _buildAllProductsHeader()),
            _buildProductsGrid(),

            // ── 6. Load More ─────────────────────────────────────────────────
            SliverToBoxAdapter(child: _buildLoadMore()),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  // ── Notification permission banner ────────────────────────────────────────

  Widget _buildNotifBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Material(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _requestNotificationPermission,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.notifications_off_outlined,
                    color: Color(0xFF856404), size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Enable notifications to get order updates',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF856404),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'Enable',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF856404),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── SliverAppBar ───────────────────────────────────────────────────────────

  Widget _buildSliverAppBar(String greeting, String firstName) {
    final screenHeight = MediaQuery.of(context).size.height;
    final expandedHeight = screenHeight >= 800 ? 140.0 : 120.0;
    return SliverAppBar(
      // toolbarHeight == expandedHeight means the bar never collapses —
      // the full greeting + search bar stays pinned at the top on scroll.
      expandedHeight: expandedHeight,
      toolbarHeight: expandedHeight,
      floating: false,
      snap: false,
      pinned: true,
      backgroundColor: AppColors.bg,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.none,
        background: Container(
          color: AppColors.bg,
          padding: const EdgeInsets.fromLTRB(20, 20, 10, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting row + icons
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$greeting,',
                          style: GoogleFonts.poppins(
                            fontSize: 13,
                            color: AppColors.textMedium,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                        Text(
                          firstName,
                          style: GoogleFonts.poppins(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Orders icon
                  _AppBarIcon(
                    icon: Icons.receipt_long_outlined,
                    onTap: () => pushTo('/orders'),
                    badgeCount: 0,
                  ),
                  const SizedBox(width: 6),
                  // Notification icon
                  Obx(() => _AppBarIcon(
                        icon: Icons.notifications_outlined,
                        onTap: () => pushTo('/notifications'),
                        badgeCount: Get.find<NotificationController>()
                            .unreadCount
                            .value,
                      )),
                  const SizedBox(width: 6),
                  // Cart icon
                  Obx(() => _AppBarIcon(
                        icon: Icons.shopping_bag_outlined,
                        onTap: () => pushTo('/cart'),
                        badgeCount: Get.find<CartController>().totalItems,
                      )),
                ],
              ),
              const SizedBox(height: 10),
              // Search bar is now inside the flexible space — no separate
              // bottom widget, so it cannot stack over the greeting on web.
              _SearchBar(
                controller: _searchController,
                onChanged: _onSearchChanged,
                onSubmit: (q) => Get.find<ProductController>().setSearch(q),
                onClear: () {
                  _searchController.clear();
                  Get.find<ProductController>().setSearch('');
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Categories ─────────────────────────────────────────────────────────────

  Widget _buildCategoriesSection() {
    return Obx(
      () {
        final pp = Get.find<ProductController>();
        if (pp.searchQuery.value.isNotEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(0, 24, 0, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionHeader(
                title: 'categories'.tr,
                onSeeAll: () => _showAllCategoriesSheet(),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 44,
                child: pp.isCategoriesLoading.value
                    ? _buildCategoryShimmer()
                    : pp.categories.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: GestureDetector(
                              onTap: () => pp.fetchCategories(),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(50),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Text(
                                  'Tap to retry',
                                  style: GoogleFonts.poppins(
                                    fontSize: 13,
                                    color: AppColors.textMedium,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ListView(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            physics: const BouncingScrollPhysics(),
                            children: [
                              AllCategoryChip(
                                isSelected: pp.selectedCategory.value.isEmpty,
                                onTap: () => pp.setCategory(''),
                              ),
                              ...pp.categories.map(
                                (cat) => CategoryChip(
                                  category: cat,
                                  isSelected:
                                      pp.selectedCategory.value == cat.id,
                                  onTap: () => pp.setCategory(cat.id),
                                ),
                              ),
                            ],
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryShimmer() {
    return Shimmer.fromColors(
      baseColor: AppColors.card,
      highlightColor: AppColors.surface,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: 5,
        itemBuilder: (_, __) => Container(
          width: 90,
          height: 40,
          margin: const EdgeInsets.only(right: 10),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(50),
          ),
        ),
      ),
    );
  }

  void _showAllCategoriesSheet() {
    final pp = Get.find<ProductController>();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AllCategoriesSheet(
        categories: pp.categories,
        selectedId: pp.selectedCategory.value,
        onSelect: (id) {
          pp.setCategory(id);
          Navigator.pop(context);
        },
      ),
    );
  }

  // ── Featured Products ──────────────────────────────────────────────────────

  Widget _buildFeaturedSection() {
    return Obx(() {
      final pp = Get.find<ProductController>();
      if (pp.searchQuery.value.isNotEmpty) return const SizedBox.shrink();
      final cart = Get.find<CartController>();
      return Padding(
        padding: const EdgeInsets.fromLTRB(0, 28, 0, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.star_rounded, color: AppColors.warning, size: 20),
                  const SizedBox(width: 6),
                  Text(
                    'featured'.tr,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              height: 265,
              child: pp.isLoading.value && pp.featuredProducts.isEmpty
                  ? _buildFeaturedShimmer()
                  : pp.featuredProducts.isEmpty
                      ? _buildEmptyState('no_featured'.tr)
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          physics: const BouncingScrollPhysics(),
                          itemCount: pp.featuredProducts.length,
                          itemBuilder: (context, i) {
                            final product = pp.featuredProducts[i];
                            return Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: SizedBox(
                                width: 160,
                                child: ProductCard(
                                  product: product,
                                  isInCart: cart.isInCart(product.id),
                                  onTap: () => pushTo('/product/${product.id}'),
                                  onAddToCart: () => _addToCart(product),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildFeaturedShimmer() {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      itemCount: 4,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.only(right: 14),
        child: const ProductCardShimmer(),
      ),
    );
  }

  // ── All Products grid header ───────────────────────────────────────────────

  Widget _buildAllProductsHeader() {
    return Obx(() {
      final pp = Get.find<ProductController>();
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 14),
        child: Row(
          children: [
            Text(
              'all_products'.tr,
              style: GoogleFonts.poppins(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const Spacer(),
            _SortDropdown(
              value: pp.sortBy.value,
              options: _sortOptions,
              onChanged: (v) {
                if (v != null) pp.setSort(v);
              },
            ),
          ],
        ),
      );
    });
  }

  // ── Products grid ──────────────────────────────────────────────────────────

  Widget _buildProductsGrid() {
    return Obx(() {
      final pp = Get.find<ProductController>();
      final cart = Get.find<CartController>();
      final isLandscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      final cols = Responsive.isDesktop(context)
          ? 4
          : Responsive.isTablet(context)
              ? (isLandscape ? 4 : 3)
              : 2;

      if (pp.isLoading.value && pp.products.isEmpty) {
        return SliverPadding(
          padding:
              EdgeInsets.symmetric(horizontal: Responsive.pagePadding(context)),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, __) => const ProductCardShimmer(),
              childCount: 6,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 14,
              mainAxisSpacing: 14,
              mainAxisExtent: 265,
            ),
          ),
        );
      }

      if (pp.products.isEmpty && !pp.isLoading.value) {
        return SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: _buildEmptyState(
              pp.searchQuery.value.isNotEmpty
                  ? '${'no_results_for'.tr} "${pp.searchQuery.value}"'
                  : 'no_products'.tr,
            ),
          ),
        );
      }

      return SliverPadding(
        padding:
            EdgeInsets.symmetric(horizontal: Responsive.pagePadding(context)),
        sliver: SliverGrid(
          delegate: SliverChildBuilderDelegate(
            (context, i) {
              final product = pp.products[i];
              return ProductCard(
                product: product,
                isInCart: cart.isInCart(product.id),
                onTap: () => pushTo('/product/${product.id}'),
                onAddToCart: () => _addToCart(product),
              );
            },
            childCount: pp.products.length,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            mainAxisExtent: 265,
          ),
        ),
      );
    });
  }

  // ── Load more ──────────────────────────────────────────────────────────────

  Widget _buildLoadMore() {
    return Obx(() {
      final pp = Get.find<ProductController>();
      if (!pp.hasMore.value && pp.products.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
            child: Text(
              'seen_all'.tr,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textMedium,
              ),
            ),
          ),
        );
      }
      if (!pp.hasMore.value) return const SizedBox.shrink();

      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: pp.isLoading.value ? null : () => pp.fetchProducts(),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: pp.isLoading.value
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2,
                    ),
                  )
                : Text(
                    'load_more'.tr,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ),
      );
    });
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  Widget _buildEmptyState(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              color: AppColors.textMedium, size: 40),
          const SizedBox(height: 10),
          Text(
            message,
            style: GoogleFonts.poppins(
              fontSize: 13,
              color: AppColors.textMedium,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Future<void> _addToCart(ProductModel product) async {
    final auth = Get.find<AuthController>();
    if (!auth.isLoggedIn) {
      pushTo('/login');
      return;
    }
    final uid = auth.user.value?.id ?? '';
    final cart = Get.find<CartController>();
    final ok = await cart.addToCart(uid, product.id, 1);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor:
              ok ? AppColors.surface : AppColors.error.withValues(alpha: 0.9),
          content: Row(
            children: [
              Icon(
                ok
                    ? Icons.check_circle_outline_rounded
                    : Icons.error_outline_rounded,
                color: ok ? AppColors.accent : Colors.white,
                size: 18,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  ok
                      ? 'added_to_cart'.tr
                      : cart.error.value ?? 'failed_add_cart'.tr,
                  style: GoogleFonts.poppins(
                      fontSize: 13, color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _AppBarIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final int badgeCount;

  const _AppBarIcon({
    required this.icon,
    required this.onTap,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Icon(icon, size: 20, color: AppColors.textPrimary),
          ),
          if (badgeCount > 0)
            Positioned(
              top: -4,
              right: -4,
              child: Container(
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                padding: const EdgeInsets.symmetric(horizontal: 4),
                decoration: BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    badgeCount > 99 ? '99+' : '$badgeCount',
                    style: GoogleFonts.poppins(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
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

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final ValueChanged<String> onSubmit;
  final VoidCallback onClear;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onSubmit,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        onSubmitted: onSubmit,
        style: GoogleFonts.poppins(
          fontSize: 13,
          color: AppColors.textPrimary,
        ),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'search_hint'.tr,
          hintStyle: GoogleFonts.poppins(
            fontSize: 13,
            color: AppColors.textMedium,
          ),
          prefixIcon:
              Icon(Icons.search_rounded, color: AppColors.textMedium, size: 20),
          suffixIcon: ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (_, value, __) => value.text.isNotEmpty
                ? GestureDetector(
                    onTap: onClear,
                    child: Icon(Icons.close_rounded,
                        color: AppColors.textMedium, size: 18),
                  )
                : const SizedBox.shrink(),
          ),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
          isDense: true,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final VoidCallback? onSeeAll;

  const _SectionHeader({required this.title, this.onSeeAll});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.poppins(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const Spacer(),
          if (onSeeAll != null)
            GestureDetector(
              onTap: onSeeAll,
              child: Text(
                'see_all'.tr,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SortDropdown extends StatelessWidget {
  final String value;
  final Map<String, String> options;
  final ValueChanged<String?> onChanged;

  const _SortDropdown({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isDense: true,
          dropdownColor: AppColors.card,
          iconEnabledColor: AppColors.textMedium,
          style: GoogleFonts.poppins(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppColors.textPrimary,
          ),
          items: options.entries
              .map(
                (e) => DropdownMenuItem(
                  value: e.key,
                  child: Text(e.value),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dynamic Banner Carousel (Firestore-backed, falls back to static cards)
// ─────────────────────────────────────────────────────────────────────────────

class _DynamicBannerCarousel extends StatefulWidget {
  const _DynamicBannerCarousel();

  @override
  State<_DynamicBannerCarousel> createState() => _DynamicBannerCarouselState();
}

class _DynamicBannerCarouselState extends State<_DynamicBannerCarousel> {
  final _pageCtrl = PageController();
  Timer? _timer;
  int _page = 0;

  static const _staticBanners = [
    _BannerData(
      gradient: AppColors.gradient1,
      emoji: '☀️',
      title: 'summer_sale',
      subtitle: 'summer_sale_sub',
      tag: 'shop_now',
    ),
    _BannerData(
      gradient: AppColors.gradient2,
      emoji: '✨',
      title: 'new_arrivals',
      subtitle: 'new_arrivals_sub',
      tag: 'explore',
    ),
    _BannerData(
      gradient: AppColors.gradient3,
      emoji: '🚚',
      title: 'free_shipping_banner',
      subtitle: 'free_shipping_banner_sub',
      tag: 'learn_more',
    ),
  ];

  void _startTimer(int count) {
    _timer?.cancel();
    if (count <= 1) return;
    _timer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      final next = (_page + 1) % count;
      _pageCtrl.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
      setState(() => _page = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BannerModel>>(
      stream: BannerService().activeBannersStream(),
      builder: (context, snap) {
        final dynamic = snap.data ?? [];
        final count =
            dynamic.isNotEmpty ? dynamic.length : _staticBanners.length;

        // Start / restart timer whenever count changes
        WidgetsBinding.instance.addPostFrameCallback((_) => _startTimer(count));

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 5, 20, 0),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (ctx, constraints) {
                  // Scale height with available width so the full banner
                  // is visible on wide tablets — target ~3.2:1 aspect ratio,
                  // clamped so phones stay at 160 and tablets cap at 220.
                  final h = (constraints.maxWidth / 3.2).clamp(160.0, 220.0);
                  return SizedBox(
                    height: h,
                    child: PageView.builder(
                      controller: _pageCtrl,
                      onPageChanged: (i) => setState(() => _page = i),
                      itemCount: count,
                      itemBuilder: (ctx, i) {
                        if (dynamic.isNotEmpty) {
                          return _DynamicBannerCard(banner: dynamic[i]);
                        }
                        return _BannerCard(data: _staticBanners[i]);
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              SmoothPageIndicator(
                controller: _pageCtrl,
                count: count,
                effect: ExpandingDotsEffect(
                  dotHeight: 6,
                  dotWidth: 6,
                  activeDotColor: AppColors.primary,
                  dotColor: AppColors.border,
                  expansionFactor: 3,
                  spacing: 5,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Network-image banner card for Firestore banners
class _DynamicBannerCard extends StatelessWidget {
  final BannerModel banner;
  const _DynamicBannerCard({required this.banner});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: AppColors.surface,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: UploadService.fixUrl(banner.imageUrl),
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(
              color: AppColors.border,
              child: const Center(
                  child: CircularProgressIndicator(
                      color: AppColors.primary, strokeWidth: 2)),
            ),
            errorWidget: (_, __, ___) => Container(
              decoration: const BoxDecoration(gradient: AppColors.gradient1),
              child: const Center(
                  child: Icon(Icons.image_not_supported_outlined,
                      color: Colors.white54, size: 36)),
            ),
          ),
          // Gradient overlay for text readability
          if (banner.title.isNotEmpty || banner.subtitle.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.55),
                    ],
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (banner.title.isNotEmpty)
                      Text(
                        banner.title,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (banner.subtitle.isNotEmpty)
                      Text(
                        banner.subtitle,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w400,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Static fallback banner card ────────────────────────────────────────────

@immutable
class _BannerData {
  final LinearGradient gradient;
  final String emoji;
  final String title;
  final String subtitle;
  final String tag;

  const _BannerData({
    required this.gradient,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.tag,
  });
}

class _BannerCard extends StatelessWidget {
  final _BannerData data;

  const _BannerCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        gradient: data.gradient,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Stack(
        children: [
          // Decorative circles
          Positioned(
            right: -24,
            top: -24,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08),
              ),
            ),
          ),
          Positioned(
            right: 30,
            bottom: -30,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.06),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          data.tag.tr,
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        data.title.tr,
                        style: GoogleFonts.poppins(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        data.subtitle.tr,
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w400,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  data.emoji,
                  style: const TextStyle(fontSize: 52),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Announcement dialog
// ─────────────────────────────────────────────────────────────────────────────
class _AnnouncementDialog extends StatelessWidget {
  final AnnouncementModel announcement;
  const _AnnouncementDialog({required this.announcement});

  static const _typeIcon = {
    'new_product': Icons.new_releases_rounded,
    'app_update': Icons.system_update_rounded,
    'promotion': Icons.local_offer_rounded,
  };

  static const _typeLabel = {
    'new_product': 'New Product',
    'app_update': 'App Update',
    'promotion': 'Promotion',
  };

  @override
  Widget build(BuildContext context) {
    final imageUrl = UploadService.fixUrl(announcement.imageUrl);
    final icon = _typeIcon[announcement.type] ?? Icons.campaign_rounded;
    final label = _typeLabel[announcement.type] ?? 'Announcement';

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(24),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Image
            if (imageUrl.isNotEmpty)
              CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                height: 200,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Type badge
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: AppColors.gradient1,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: Colors.white, size: 13),
                        const SizedBox(width: 5),
                        Text(
                          label,
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Title
                  Text(
                    announcement.title,
                    style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Body
                  Text(
                    announcement.body,
                    style: GoogleFonts.poppins(
                      color: AppColors.textMedium,
                      fontSize: 13,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Actions
                  Row(
                    children: [
                      if (announcement.productId.isNotEmpty) ...[
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.pop(context);
                              pushTo('/product/${announcement.productId}');
                            },
                            child: Text(
                              'View Product',
                              style: GoogleFonts.poppins(
                                  fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.textMedium,
                            side: BorderSide(color: AppColors.border),
                          ),
                          child: Text(
                            'Got it',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// All-categories bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AllCategoriesSheet extends StatelessWidget {
  final List<CategoryModel> categories;
  final String selectedId;
  final void Function(String id) onSelect;

  const _AllCategoriesSheet({
    required this.categories,
    required this.selectedId,
    required this.onSelect,
  });

  Color _parseHex(String hex) {
    try {
      final cleaned = hex.replaceAll('#', '');
      if (cleaned.length == 6) {
        return Color(int.parse('FF$cleaned', radix: 16));
      }
    } catch (_) {}
    return AppColors.primary;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Handle
            Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 4),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Row(
                children: [
                  Text(
                    'categories'.tr,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${categories.length} ${'categories'.tr.toLowerCase()}',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            // Grid
            Expanded(
              child: GridView.builder(
                controller: ctrl,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.85,
                ),
                itemCount: categories.length + 1,
                itemBuilder: (_, i) {
                  if (i == 0) {
                    return _CategoryGridCard(
                      label: 'All',
                      icon: '🌟',
                      imageUrl: '',
                      accentColor: AppColors.primary,
                      isSelected: selectedId.isEmpty,
                      onTap: () => onSelect(''),
                    );
                  }
                  final cat = categories[i - 1];
                  return _CategoryGridCard(
                    label: cat.name,
                    icon: cat.icon,
                    imageUrl: cat.image,
                    accentColor: _parseHex(cat.color),
                    isSelected: selectedId == cat.id,
                    onTap: () => onSelect(cat.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryGridCard extends StatelessWidget {
  final String label;
  final String icon;
  final String imageUrl;
  final Color accentColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryGridCard({
    required this.label,
    required this.icon,
    required this.imageUrl,
    required this.accentColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isSelected
              ? accentColor.withValues(alpha: 0.12)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? accentColor : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.20),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 52,
              height: 52,
              child: imageUrl.isNotEmpty
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: UploadService.fixUrl(imageUrl),
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Center(
                          child:
                              Text(icon, style: const TextStyle(fontSize: 30)),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(icon, style: const TextStyle(fontSize: 30)),
                    ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? accentColor : AppColors.textPrimary,
                  height: 1.3,
                ),
              ),
            ),
            if (isSelected) ...[
              const SizedBox(height: 4),
              Icon(Icons.check_circle_rounded, color: accentColor, size: 14),
            ],
          ],
        ),
      ),
    );
  }
}
