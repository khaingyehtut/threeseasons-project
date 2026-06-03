import 'package:flutter/material.dart';

/// Screen-size breakpoints
/// Mobile  : width < 600
/// Tablet  : 600 <= width < 1024
/// Desktop : width >= 1024
class Responsive {
  static const double _tablet  = 600;
  static const double _desktop = 1440;

  static bool isMobile (BuildContext ctx) => MediaQuery.sizeOf(ctx).width < _tablet;
  static bool isTablet (BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _tablet  && MediaQuery.sizeOf(ctx).width < _desktop;
  static bool isDesktop(BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _desktop;
  static bool isWide   (BuildContext ctx) => MediaQuery.sizeOf(ctx).width >= _tablet;  // tablet OR desktop

  static double width (BuildContext ctx) => MediaQuery.sizeOf(ctx).width;
  static double height(BuildContext ctx) => MediaQuery.sizeOf(ctx).height;

  /// Number of product-grid columns for the current screen width.
  static int gridColumns(BuildContext ctx) {
    final w = width(ctx);
    if (w >= _desktop) return 4;
    if (w >= _tablet)  return 3;
    return 2;
  }

  /// Horizontal page padding — larger on wide screens.
  static double pagePadding(BuildContext ctx) {
    if (isDesktop(ctx)) return 40;
    if (isTablet(ctx))  return 24;
    return 16;
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
