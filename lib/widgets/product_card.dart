import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:shimmer/shimmer.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/product_model.dart';

class ProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;
  final VoidCallback? onAddToCart;
  final bool isInCart;
  final double imageHeight;

  const ProductCard({
    super.key,
    required this.product,
    required this.onTap,
    this.onAddToCart,
    this.isInCart = false,
    this.imageHeight = 148,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border, width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Image + discount badge ───────────────────────
            Stack(
              children: [
                ClipRRect(
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    height: imageHeight,
                    width: double.infinity,
                    child: product.firstImage.isNotEmpty
                        ? Stack(
                            fit: StackFit.expand,
                            children: [
                              // Blurred background layer
                              CachedNetworkImage(
                                imageUrl: product.firstImage,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => _ShimmerBox(
                                  height: imageHeight,
                                  width: double.infinity,
                                  borderRadius: const BorderRadius.vertical(
                                    top: Radius.circular(16),
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    _ImageFallback(height: imageHeight),
                              ),
                              BackdropFilter(
                                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                                child: const ColoredBox(
                                    color: Colors.transparent),
                              ),
                              // Clear image on top
                              CachedNetworkImage(
                                imageUrl: product.firstImage,
                                fit: BoxFit.contain,
                                errorWidget: (context, url, error) =>
                                    _ImageFallback(height: imageHeight),
                              ),
                            ],
                          )
                        : _ImageFallback(height: imageHeight),
                  ),
                ),
                if (product.hasDiscount)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.secondary,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${product.discount}% OFF',
                        style: GoogleFonts.poppins(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ),
                  ),
                // Out of stock overlay
                if (!product.isInStock)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(16)),
                      child: Container(
                        color: Colors.black.withValues(alpha: 0.55),
                        alignment: Alignment.center,
                        child: Text(
                          'Out of Stock',
                          style: GoogleFonts.poppins(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),

            // ── Details ────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Brand / category
                    Text(
                      product.brand.isNotEmpty
                          ? product.brand
                          : (product.category?.name ?? ''),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: AppColors.textMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Product name
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Rating row
                    Row(
                      children: [
                        Icon(Icons.star_rounded,
                            size: 11, color: AppColors.warning),
                        const SizedBox(width: 2),
                        Text(
                          product.rating.toStringAsFixed(1),
                          style: GoogleFonts.poppins(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppColors.warning,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          '(${product.numReviews})',
                          style: GoogleFonts.poppins(
                            fontSize: 9,
                            color: AppColors.textMedium,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Price row + cart button
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                fmtPrice(product.discountedPrice),
                                style: GoogleFonts.poppins(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                              if (product.hasDiscount)
                                Text(
                                  fmtPrice(product.price),
                                  style: GoogleFonts.poppins(
                                    fontSize: 9,
                                    color: AppColors.textMedium,
                                    decoration: TextDecoration.lineThrough,
                                    decorationColor: AppColors.textMedium,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        // Add to cart button
                        GestureDetector(
                          onTap: product.isInStock ? onAddToCart : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: isInCart
                                  ? AppColors.accent
                                  : (product.isInStock
                                      ? AppColors.primary
                                      : AppColors.surface),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              isInCart
                                  ? Icons.check_rounded
                                  : Icons.add_shopping_cart_rounded,
                              size: 14,
                              color: product.isInStock
                                  ? Colors.white
                                  : AppColors.textMedium,
                            ),
                          ),
                        ),
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
}

// ── Shimmer placeholder box ──────────────────────────────────────────────────

class _ShimmerBox extends StatelessWidget {
  final double height;
  final double? width;
  final BorderRadius? borderRadius;

  const _ShimmerBox({
    required this.height,
    this.width,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.surface,
      highlightColor: AppColors.border,
      child: Container(
        height: height,
        width: width ?? double.infinity,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: borderRadius ?? BorderRadius.circular(0),
        ),
      ),
    );
  }
}

// ── Fallback widget when no image or load fails ──────────────────────────────

class _ImageFallback extends StatelessWidget {
  final double height;

  const _ImageFallback({required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Icon(
        Icons.image_not_supported_rounded,
        color: AppColors.textMedium,
        size: 36,
      ),
    );
  }
}

// ── Shimmer ProductCard skeleton for loading states ──────────────────────────

class ProductCardShimmer extends StatelessWidget {
  const ProductCardShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppColors.card,
      highlightColor: AppColors.surface,
      child: Container(
        width: 160,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 148,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 7, 9, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ShimmerLine(width: 55, height: 9),
                  const SizedBox(height: 3),
                  _ShimmerLine(width: double.infinity, height: 11),
                  const SizedBox(height: 3),
                  _ShimmerLine(width: 90, height: 11),
                  const SizedBox(height: 5),
                  _ShimmerLine(width: 70, height: 9),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      _ShimmerLine(width: 50, height: 12),
                      const Spacer(),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(8),
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

class _ShimmerLine extends StatelessWidget {
  final double width;
  final double height;

  const _ShimmerLine({required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}
