import 'package:flutter/material.dart';

/// Screen-size breakpoints
/// Mobile  : width < 600
/// Tablet  : 600 <= width < 1440
/// Desktop : width >= 1440
class Responsive {
  static const double _tablet  = 600;
  static const double _desktop = 1440;

  static bool isMobile (BuildContext ctx) => MediaQuery.sizeOf(ctx).width < _tablet;
  static bool isTablet (BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _tablet  && MediaQuery.sizeOf(ctx).width < _desktop;
  static bool isDesktop(BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _desktop;
  static bool isWide   (BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _tablet;  // tablet OR desktop

  static bool isLandscape(BuildContext ctx) =>
      MediaQuery.orientationOf(ctx) == Orientation.landscape;

  /// True when the device is a tablet AND in landscape orientation.
  static bool isTabletLandscape(BuildContext ctx) =>
      isTablet(ctx) && isLandscape(ctx);

  static double width (BuildContext ctx) => MediaQuery.sizeOf(ctx).width;
  static double height(BuildContext ctx) => MediaQuery.sizeOf(ctx).height;

  /// Number of product-grid columns for the current screen width.
  static int gridColumns(BuildContext ctx) {
    final w = width(ctx);
    if (w >= _desktop) return 4;
    if (w >= 900)      return 4; // tablet landscape → one extra column
    if (w >= _tablet)  return 3;
    return 2;
  }

  /// Product-card main-axis extent — shorter in landscape to save vertical space.
  static double cardExtent(BuildContext ctx) {
    if (isTabletLandscape(ctx)) return 220;
    return 265;
  }

  /// Horizontal page padding — larger on wide screens.
  static double pagePadding(BuildContext ctx) {
    if (isDesktop(ctx)) return 40;
    if (isTablet(ctx))  return 24;
    return 16;
  }

  /// Max width for bottom-sheet content so it doesn't stretch across a wide
  /// landscape screen. Wrap the sheet builder child with this.
  static Widget constrainSheet(BuildContext ctx, Widget child) {
    final w = width(ctx);
    if (w <= _tablet) return child; // full-width on mobile/portrait tablet
    final maxW = w >= _desktop ? 620.0 : 520.0;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW),
        child: child,
      ),
    );
  }

  /// Constrain a content block to a sensible max width on desktop.
  /// Wraps [child] in a centred, width-limited box when on desktop.
  static Widget maxWidth(BuildContext ctx, Widget child, {double max = 1200}) {
    if (!isDesktop(ctx)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }

  /// Centre a form/card on tablet & desktop (max 480 px wide).
  static Widget centreForm(BuildContext ctx, Widget child, {double max = 480}) {
    if (isMobile(ctx)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }

  /// Centre any content on tablet+ (useful for list/sliver content).
  static Widget centreContent(BuildContext ctx, Widget child, {double max = 720}) {
    if (isMobile(ctx)) return child;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: max),
        child: child,
      ),
    );
  }

  /// Return one of three values depending on current breakpoint.
  static T value<T>(BuildContext ctx, {required T mobile, required T tablet, required T desktop}) {
    if (isDesktop(ctx)) return desktop;
    if (isTablet(ctx))  return tablet;
    return mobile;
  }
}

/// Drop-in builder that rebuilds whenever screen size crosses a breakpoint.
class ResponsiveBuilder extends StatelessWidget {
  final Widget Function(BuildContext context, bool isWide, bool isDesktop) builder;
  const ResponsiveBuilder({super.key, required this.builder});

  @override
  Widget build(BuildContext context) {
    return builder(context, Responsive.isWide(context), Responsive.isDesktop(context));
  }
}
