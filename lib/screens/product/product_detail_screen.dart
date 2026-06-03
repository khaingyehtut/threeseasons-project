import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:get/get.dart';
import 'package:flutter_rating_bar/flutter_rating_bar.dart';
import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/product_controller.dart';
import '../../controllers/cart_controller.dart';
import '../../models/product_model.dart';
import '../../core/constants.dart';
import '../../core/navigation.dart';
import '../../services/product_service.dart';

class ProductDetailScreen extends StatefulWidget {
  final String productId;
  const ProductDetailScreen({super.key, required this.productId});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  final PageController _pageController = PageController();
  int _currentImageIndex = 0;
  String? _selectedSize;
  String? _selectedColor;
  int _quantity = 1;
  bool _showFullDescription = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Get.find<ProductController>().fetchProductById(widget.productId);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Color _parseColor(String colorStr) {
    try {
      final hex = colorStr.replaceAll('#', '');
      if (hex.length == 6) {
        return Color(int.parse('FF$hex', radix: 16));
      }
    } catch (_) {}
    // Map named colors
    final namedColors = {
      'red': Colors.red,
      'blue': Colors.blue,
      'green': Colors.green,
      'black': Colors.black,
      'white': Colors.white,
      'yellow': Colors.yellow,
      'orange': Colors.orange,
      'purple': Colors.purple,
      'pink': Colors.pink,
      'grey': Colors.grey,
      'gray': Colors.grey,
      'brown': Colors.brown,
      'teal': Colors.teal,
      'cyan': Colors.cyan,
      'indigo': Colors.indigo,
      'navy': const Color(0xFF001F5B),
      'beige': const Color(0xFFF5F5DC),
    };
    return namedColors[colorStr.toLowerCase()] ?? AppColors.primary;
  }

  bool _validateSelections(ProductModel product) {
    if (product.sizes.isNotEmpty && _selectedSize == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('select_size'.tr,
            style: GoogleFonts.poppins(color: Colors.white)),
        backgroundColor: AppColors.warning,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ));
      return false;
    }
    return true;
  }

  void _addToCart(ProductModel product) async {
    if (!_validateSelections(product)) return;
    final uid = Get.find<AuthController>().user.value?.id ?? '';
    if (uid.isEmpty) {
      pushTo('/login');
      return;
    }
    final cartController = Get.find<CartController>();
    final success = await cartController.addToCart(
      uid,
      product.id,
      _quantity,
      size: _selectedSize,
      color: _selectedColor,
    );
    if (!mounted) return;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'added_to_cart'.tr,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: AppColors.accent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            cartController.error.value ?? 'failed_add_cart'.tr,
            style: GoogleFonts.poppins(color: Colors.white),
          ),
          backgroundColor: AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  void _buyNow(ProductModel product) async {
    if (!_validateSelections(product)) return;
    final uid = Get.find<AuthController>().user.value?.id ?? '';
    if (uid.isEmpty) {
      pushTo('/login');
      return;
    }
    final cartController = Get.find<CartController>();
    final success = await cartController.addToCart(
      uid,
      product.id,
      _quantity,
      size: _selectedSize,
      color: _selectedColor,
    );
    if (!mounted) return;
    if (success) {
      pushTo('/cart');
    }
  }

  Widget _buildLoadingState() {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, color: AppColors.secondary, size: 60),
            const SizedBox(height: 16),
            Text(
              'failed_load_product'.tr,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final productController = Get.find<ProductController>();
      if (productController.isLoading.value &&
          productController.selectedProduct.value == null) {
        return _buildLoadingState();
      }
      if (productController.error.value != null &&
          productController.selectedProduct.value == null) {
        return _buildErrorState(productController.error.value!);
      }
      final product = productController.selectedProduct.value;
      if (product == null) return _buildLoadingState();

      final allImages = [
        if (product.thumbnail.isNotEmpty) product.thumbnail,
        ...List<String>.from(product.images)
            .where((img) => img != product.thumbnail),
      ];
      if (allImages.isEmpty) allImages.add('');

      return AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          appBar: Responsive.isWide(context)
              ? AppBar(
                  backgroundColor: AppColors.bg,
                  elevation: 0,
                  leading: IconButton(
                    icon: Icon(Icons.arrow_back_ios_new_rounded,
                        color: AppColors.textPrimary),
                    onPressed: () => Navigator.pop(context),
                  ),
                  actions: [
                    Obx(() {
                      final auth = Get.find<AuthController>();
                      final isFav = auth.isFavorite(product.id);
                      return IconButton(
                        icon: Icon(
                          isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          color: isFav
                              ? AppColors.secondary
                              : AppColors.textPrimary,
                        ),
                        onPressed: () async {
                          await auth.toggleWishlist(product.id);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(
                                auth.isFavorite(product.id)
                                    ? 'added_to_wishlist'.tr
                                    : 'removed_from_wishlist'.tr,
                              ),
                              backgroundColor: AppColors.card,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              duration: const Duration(seconds: 1),
                            ));
                          }
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                  ],
                )
              : null,
          body: Responsive.isWide(context)
              // ── Wide: image left | details right ─────────────────────────
              ? Responsive.maxWidth(
                  context,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Left: image carousel (40% width)
                      SizedBox(
                        width: Responsive.width(context) *
                            (Responsive.isDesktop(context) ? 0.38 : 0.42),
                        child: _buildImageSection(allImages, product,
                            fixedHeight: true),
                      ),
                      // Right: scrollable product info (remaining width)
                      Expanded(
                        child: SingleChildScrollView(
                          child: _buildProductInfo(product, productController),
                        ),
                      ),
                    ],
                  ),
                )
              // ── Mobile/tablet narrow: original vertical scroll ─────────
              : Stack(
                  children: [
                    CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                            child: _buildImageSection(allImages, product)),
                        SliverToBoxAdapter(
                            child:
                                _buildProductInfo(product, productController)),
                      ],
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      left: 16,
                      child: _buildFloatingButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () => Navigator.pop(context),
                      ),
                    ),
                    Positioned(
                      top: MediaQuery.of(context).padding.top + 8,
                      right: 16,
                      child: Obx(() {
                        final auth = Get.find<AuthController>();
                        final isFav = auth.isFavorite(product.id);
                        return _buildFloatingButton(
                          icon: isFav
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          iconColor: isFav
                              ? AppColors.secondary
                              : AppColors.textPrimary,
                          onTap: () async {
                            await auth.toggleWishlist(product.id);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context)
                                  .showSnackBar(SnackBar(
                                content: Text(
                                  auth.isFavorite(product.id)
                                      ? 'added_to_wishlist'.tr
                                      : 'removed_from_wishlist'.tr,
                                ),
                                backgroundColor: AppColors.card,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10)),
                                duration: const Duration(seconds: 1),
                              ));
                            }
                          },
                        );
                      }),
                    ),
                  ],
                ),
          bottomNavigationBar: _buildBottomBar(product),
        ),
      );
    });
  }

  Widget _buildFloatingButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? iconColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: AppColors.card.withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Icon(icon, color: iconColor ?? AppColors.textPrimary, size: 20),
      ),
    );
  }

  Widget _buildImageSection(List<String> images, ProductModel product,
      {bool fixedHeight = false}) {
    // On wide screens the image sits in an Expanded column — use LayoutBuilder
    // to get the real available height instead of double.infinity (illegal).
    if (fixedHeight) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : MediaQuery.of(context).size.height;
          return _imageStack(images, product, h);
        },
      );
    }
    final height = MediaQuery.of(context).size.height * 0.48;
    return _imageStack(images, product, height);
  }

  Widget _imageStack(List<String> images, ProductModel product, double height) {
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: images.length,
            onPageChanged: (i) => setState(() => _currentImageIndex = i),
            itemBuilder: (context, index) {
              final img = images[index];
              return img.isEmpty
                  ? Container(
                      color: AppColors.card,
                      child: const Center(
                        child: Icon(Icons.image_not_supported_outlined,
                            color: AppColors.textMedium, size: 60),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: img,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.card,
                        child: const Center(
                            child: CircularProgressIndicator(
                                color: AppColors.primary)),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.card,
                        child: const Center(
                          child: Icon(Icons.broken_image_outlined,
                              color: AppColors.textMedium, size: 60),
                        ),
                      ),
                    );
            },
          ),
          // Gradient overlay at bottom
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 80,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    AppColors.bg.withValues(alpha: 0.95)
                  ],
                ),
              ),
            ),
          ),
          // Dots indicator
          if (images.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (i) {
                  final isActive = i == _currentImageIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 20 : 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.primary : AppColors.border,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          // Discount badge
          if (product.hasDiscount)
            Positioned(
              top: MediaQuery.of(context).padding.top + 64,
              left: 16,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  gradient: AppColors.gradient2,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '-${product.discount}%',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductInfo(
      ProductModel product, ProductController productController) {
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          // Brand chip
          if (product.brand.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
                border:
                    Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Text(
                product.brand,
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 10),
          // Product name
          Text(
            product.name,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.3),
          ),
          const SizedBox(height: 12),
          // Rating row
          Row(
            children: [
              ...List.generate(5, (i) {
                final starVal = i + 1;
                return Icon(
                  starVal <= product.rating.round()
                      ? Icons.star_rounded
                      : (starVal - product.rating < 1
                          ? Icons.star_half_rounded
                          : Icons.star_outline_rounded),
                  color: AppColors.warning,
                  size: 18,
                );
              }),
              const SizedBox(width: 8),
              Text(
                product.rating.toStringAsFixed(1),
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Text(
                '(${product.numReviews} reviews)',
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 13),
              ),
              const Spacer(),
              // Stock indicator
              _buildStockIndicator(product),
            ],
          ),
          const SizedBox(height: 14),
          // Price row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${fmtPrice(product.discountedPrice)}',
                style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (product.hasDiscount) ...[
                const SizedBox(width: 10),
                Text(
                  '${fmtPrice(product.price)}',
                  style: GoogleFonts.poppins(
                    color: AppColors.textMedium,
                    fontSize: 16,
                    fontWeight: FontWeight.w400,
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppColors.textMedium,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 20),
          // Description
          _buildDescription(product),
          const SizedBox(height: 20),
          // Size selector
          if (product.sizes.isNotEmpty) _buildSizeSelector(product.sizes),
          // Color selector
          if (product.colors.isNotEmpty) _buildColorSelector(product.colors),
          const SizedBox(height: 20),
          // Quantity selector
          _buildQuantitySelector(product),
          const SizedBox(height: 28),
          // Divider
          Divider(color: AppColors.border, thickness: 1),
          const SizedBox(height: 20),
          // Reviews section
          _buildReviewsSection(product),
          const SizedBox(height: 20),
          // Related products
          _buildRelatedProducts(productController),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildStockIndicator(ProductModel product) {
    Color color;
    String label;
    IconData icon;
    if (product.stock == 0) {
      color = AppColors.secondary;
      label = 'out_of_stock'.tr;
      icon = Icons.remove_circle_outline_rounded;
    } else if (product.stock <= 5) {
      color = AppColors.warning;
      label = 'low_stock'.tr;
      icon = Icons.warning_amber_rounded;
    } else {
      color = AppColors.accent;
      label = 'in_stock'.tr;
      icon = Icons.check_circle_outline_rounded;
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: GoogleFonts.poppins(
                color: color, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildDescription(ProductModel product) {
    const maxLines = 3;
    final lines = product.description.split('\n');
    final isLong = product.description.length > 150 || lines.length > maxLines;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'description'.tr,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Text(
          product.description.isEmpty
              ? 'no_description'.tr
              : product.description,
          style: GoogleFonts.poppins(
              color: AppColors.textMedium, fontSize: 13, height: 1.6),
          maxLines: _showFullDescription ? null : maxLines,
          overflow: _showFullDescription
              ? TextOverflow.visible
              : TextOverflow.ellipsis,
        ),
        if (isLong && product.description.isNotEmpty)
          GestureDetector(
            onTap: () =>
                setState(() => _showFullDescription = !_showFullDescription),
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _showFullDescription ? 'show_less'.tr : 'show_more'.tr,
                style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSizeSelector(List<String> sizes) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'size'.tr,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            Text(' *',
                style: GoogleFonts.poppins(
                    color: AppColors.secondary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            if (_selectedSize != null) ...[
              const SizedBox(width: 8),
              Text(
                _selectedSize!,
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: sizes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final size = sizes[index];
              final isSelected = _selectedSize == size;
              return GestureDetector(
                onTap: () => setState(() => _selectedSize = size),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 44,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary : AppColors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : AppColors.border,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      size,
                      style: GoogleFonts.poppins(
                        color: isSelected ? Colors.white : AppColors.textMedium,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildColorSelector(List<String> colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'color'.tr,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600),
            ),
            if (_selectedColor != null) ...[
              const SizedBox(width: 8),
              Text(
                _selectedColor!,
                style: GoogleFonts.poppins(
                    color: AppColors.primary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: colors.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final colorStr = colors[index];
              final isSelected = _selectedColor == colorStr;
              final color = _parseColor(colorStr);
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = colorStr),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color:
                          isSelected ? AppColors.primary : Colors.transparent,
                      width: 2.5,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                                color: AppColors.primary.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 1)
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? Icon(Icons.check_rounded, color: Colors.white, size: 16)
                      : null,
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildQuantitySelector(ProductModel product) {
    return Row(
      children: [
        Text(
          'quantity'.tr,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              _buildQtyButton(
                icon: Icons.remove_rounded,
                onTap: _quantity > 1 ? () => setState(() => _quantity--) : null,
              ),
              SizedBox(
                width: 44,
                child: Center(
                  child: Text(
                    '$_quantity',
                    style: GoogleFonts.poppins(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              _buildQtyButton(
                icon: Icons.add_rounded,
                onTap: _quantity < product.stock
                    ? () => setState(() => _quantity++)
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQtyButton({required IconData icon, VoidCallback? onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: onTap != null
              ? AppColors.primary.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          icon,
          color: onTap != null ? AppColors.primary : AppColors.border,
          size: 18,
        ),
      ),
    );
  }

  Widget _buildReviewsSection(ProductModel product) {
    final auth = Get.find<AuthController>();
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: ProductService().reviewsStream(widget.productId),
      builder: (context, snap) {
        final reviews = snap.data ?? [];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'reviews'.tr,
                  style: GoogleFonts.poppins(
                      color: AppColors.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700),
                ),
                Row(children: [
                  if (reviews.isNotEmpty)
                    Text(
                      '${reviews.length} total',
                      style: GoogleFonts.poppins(
                          color: AppColors.textMedium, fontSize: 13),
                    ),
                  if (auth.isLoggedIn) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => _showWriteReviewDialog(product),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          gradient: AppColors.gradient1,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'write_review'.tr,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ]),
              ],
            ),
            const SizedBox(height: 14),
            if (reviews.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                  child: Text(
                    'no_reviews'.tr,
                    style: GoogleFonts.poppins(
                        color: AppColors.textMedium, fontSize: 13),
                  ),
                ),
              )
            else
              ...reviews.map((r) => _buildReviewCard(r)),
          ],
        );
      },
    );
  }

  Future<void> _showWriteReviewDialog(ProductModel product) async {
    double _rating = 5.0;
    final _commentCtrl = TextEditingController();
    bool _submitting = false;

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
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              'write_review'.tr,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),
            RatingBar.builder(
              initialRating: 5,
              minRating: 1,
              itemCount: 5,
              itemSize: 36,
              glow: false,
              itemBuilder: (_, __) =>
                  const Icon(Icons.star_rounded, color: Colors.amber),
              onRatingUpdate: (r) => _rating = r,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _commentCtrl,
              maxLines: 4,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Share your experience...',
                hintStyle: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 13),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        BorderSide(color: AppColors.primary, width: 1.5)),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _submitting
                    ? null
                    : () async {
                        final comment = _commentCtrl.text.trim();
                        if (comment.isEmpty) return;
                        setSheet(() => _submitting = true);
                        final auth = Get.find<AuthController>();
                        final ok = await Get.find<ProductController>()
                            .addReview(
                          widget.productId,
                          _rating,
                          comment,
                          auth.user.value?.id ?? '',
                          auth.user.value?.name ?? 'User',
                        );
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (ok && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Review submitted!',
                                style: GoogleFonts.poppins(
                                    color: Colors.white)),
                            backgroundColor: AppColors.success,
                            behavior: SnackBarBehavior.floating,
                          ));
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text('Submit Review',
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
    _commentCtrl.dispose();
  }

  Widget _buildReviewCard(Map<String, dynamic> review) {
    final name = review['userName'] as String? ?? 'User';
    final rating = (review['rating'] as num?)?.toDouble() ?? 0.0;
    final comment = review['comment'] as String? ?? '';
    final ts = review['createdAt'];
    String date = '';
    if (ts != null) {
      try {
        final dt = ts is DateTime
            ? ts
            : (ts.runtimeType.toString().contains('Timestamp')
                ? (ts as dynamic).toDate()
                : DateTime.now());
        final diff = DateTime.now().difference(dt);
        if (diff.inDays == 0) {
          date = 'Today';
        } else if (diff.inDays < 7) {
          date = '${diff.inDays}d ago';
        } else if (diff.inDays < 30) {
          date = '${(diff.inDays / 7).round()}w ago';
        } else {
          date = '${(diff.inDays / 30).round()}mo ago';
        }
      } catch (_) {}
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'U',
                  style: GoogleFonts.poppins(
                      color: AppColors.primary, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: List.generate(5, (i) {
                        return Icon(
                          i < rating.round()
                              ? Icons.star_rounded
                              : Icons.star_outline_rounded,
                          color: AppColors.warning,
                          size: 13,
                        );
                      }),
                    ),
                  ],
                ),
              ),
              Text(
                date,
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            comment,
            style: GoogleFonts.poppins(
                color: AppColors.textMedium, fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }

  Widget _buildRelatedProducts(ProductController productController) {
    final related = productController.products
        .where((p) => p.id != widget.productId)
        .take(8)
        .toList();

    if (related.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'related_products'.tr,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: related.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final p = related[index];
              return GestureDetector(
                onTap: () {
                  pushTo('/product/${p.id}');
                },
                child: Container(
                  width: 140,
                  decoration: BoxDecoration(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(14)),
                        child: p.firstImage.isEmpty
                            ? Container(
                                height: 110,
                                color: AppColors.surface,
                                child: const Center(
                                  child: Icon(
                                      Icons.image_not_supported_outlined,
                                      color: AppColors.textMedium,
                                      size: 30),
                                ),
                              )
                            : CachedNetworkImage(
                                imageUrl: p.firstImage,
                                height: 110,
                                width: double.infinity,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => Container(
                                  height: 110,
                                  color: AppColors.surface,
                                  child: const Center(
                                    child: Icon(Icons.broken_image_outlined,
                                        color: AppColors.textMedium, size: 30),
                                  ),
                                ),
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${fmtPrice(p.discountedPrice)}',
                              style: GoogleFonts.poppins(
                                  color: AppColors.primary,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ProductModel product) {
    final isOutOfStock = product.stock == 0;
    return Container(
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        children: [
          // Add to Cart
          Expanded(
            flex: 3,
            child: GestureDetector(
              onTap: isOutOfStock ? null : () => _addToCart(product),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  gradient: isOutOfStock ? null : AppColors.gradient1,
                  color: isOutOfStock ? AppColors.surface : null,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Obx(() {
                    final cartController = Get.find<CartController>();
                    if (cartController.isLoading.value) {
                      return const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      );
                    }
                    return Text(
                      isOutOfStock ? 'out_of_stock'.tr : 'add_to_cart'.tr,
                      style: GoogleFonts.poppins(
                        color:
                            isOutOfStock ? AppColors.textMedium : Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Buy Now
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: isOutOfStock ? null : () => _buyNow(product),
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isOutOfStock ? AppColors.border : AppColors.primary,
                    width: 1.5,
                  ),
                ),
                child: Center(
                  child: Text(
                    'buy_now'.tr,
                    style: GoogleFonts.poppins(
                      color: isOutOfStock
                          ? AppColors.textMedium
                          : AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
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

