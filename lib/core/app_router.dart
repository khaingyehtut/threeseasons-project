import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:go_router/go_router.dart';

// Eagerly-loaded screens (small / always needed)
import '../screens/splash_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/main_screen.dart';
import '../controllers/auth_controller.dart';

// Deferred (heavy) screens — loaded only when first navigated to.
// On Flutter Web each deferred import becomes its own JS chunk.
import '../screens/admin/admin_dashboard.dart' deferred as admin_dash;
import '../screens/product/product_detail_screen.dart' deferred as product_detail;
import '../screens/cart/cart_screen.dart' deferred as cart_screen;
import '../screens/chat/chat_list_screen.dart' deferred as chat_list;
import '../screens/chat/chat_screen.dart' deferred as chat_screen;
import '../screens/orders/orders_screen.dart' deferred as orders_screen;
import '../screens/orders/order_detail_screen.dart' deferred as order_detail;
import '../screens/profile/profile_screen.dart' deferred as profile_screen;
import '../screens/wishlist/wishlist_screen.dart' deferred as wishlist_screen;
import '../screens/notifications/notifications_screen.dart' deferred as noti_screen;
import '../screens/payment/payment_screen.dart' deferred as payment_screen;

// ── Auth listenable ───────────────────────────────────────────────────────────

// Notifies GoRouter whenever the Firebase Auth session changes so the redirect
// is re-evaluated automatically — without requiring a new navigation event.
class _AuthListenable extends ChangeNotifier {
  late final StreamSubscription<User?> _sub;
  _AuthListenable() {
    _sub = FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

// ── Deferred loading helper ───────────────────────────────────────────────────

/// Shows a spinner while a deferred library loads, then builds [create()].
class _Deferred extends StatefulWidget {
  final Future<void> Function() load;
  final Widget Function() create;
  const _Deferred({required this.load, required this.create});

  @override
  State<_Deferred> createState() => _DeferredState();
}

class _DeferredState extends State<_Deferred> {
  late Future<void> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.load();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 12),
                Text('Failed to load screen',
                    style: Theme.of(ctx).textTheme.bodyMedium),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: () => setState(() => _future = widget.load()),
                  child: const Text('Retry'),
                ),
              ]),
            ),
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.create();
      },
    );
  }
}

// ── Router ────────────────────────────────────────────────────────────────────

class AppRouter {
  AppRouter._();

  static final _rootKey = GlobalKey<NavigatorState>();
  static GoRouter get router => _router;

  /// Starts downloading the admin JS chunk in the background.
  /// Call this right after confirming a user is admin so the chunk is
  /// ready (or already cached) by the time the admin dashboard mounts.
  static void prefetchAdminBundle() => admin_dash.loadLibrary();

  static final _authListenable = _AuthListenable();

  static final GoRouter _router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/',
    debugLogDiagnostics: false,
    // Re-evaluate redirect whenever Firebase Auth session changes.
    refreshListenable: _authListenable,
    redirect: (context, state) {
      final auth = Get.find<AuthController>();
      final loc  = state.matchedLocation;

      // Use Firebase Auth directly — it's synchronous and always up-to-date,
      // even while AuthController.initialize() is still fetching the profile.
      final firebaseUser = FirebaseAuth.instance.currentUser;
      final isLoggedIn   = firebaseUser != null || auth.isLoggedIn;
      final isAdmin      = auth.isAdmin;

      const protected = [
        '/cart', '/orders', '/profile',
        '/wishlist', '/notifications', '/payment', '/chats',
      ];
      if (protected.any((p) => loc.startsWith(p)) && !isLoggedIn) {
        return '/login';
      }
      if (loc.startsWith('/admin') && !isAdmin) return '/main';
      return null;
    },
    routes: [
      GoRoute(path: '/',                builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login',           builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/register',        builder: (_, __) => const RegisterScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/main',            builder: (_, __) => const MainScreen()),

      GoRoute(
        path: '/admin',
        builder: (_, __) => _Deferred(
          load: admin_dash.loadLibrary,
          create: () => admin_dash.AdminDashboard(),
        ),
      ),
      GoRoute(
        path: '/admin/products',
        builder: (_, __) => _Deferred(
          load: admin_dash.loadLibrary,
          create: () => admin_dash.AdminProductsPage(),
        ),
      ),
      GoRoute(
        path: '/product/:id',
        builder: (_, state) => _Deferred(
          load: product_detail.loadLibrary,
          create: () => product_detail.ProductDetailScreen(
              productId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/cart',
        builder: (_, __) => _Deferred(
          load: cart_screen.loadLibrary,
          create: () => cart_screen.CartScreen(),
        ),
      ),
      GoRoute(
        path: '/chats',
        builder: (_, __) => _Deferred(
          load: chat_list.loadLibrary,
          create: () => chat_list.ChatListScreen(),
        ),
      ),
      GoRoute(
        path: '/chat/:userId',
        builder: (_, state) => _Deferred(
          load: chat_screen.loadLibrary,
          create: () => chat_screen.ChatScreen(
            userId:     state.pathParameters['userId']!,
            userName:   state.uri.queryParameters['name']   ?? '',
            userAvatar: state.uri.queryParameters['avatar'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (_, __) => _Deferred(
          load: orders_screen.loadLibrary,
          create: () => orders_screen.OrdersScreen(),
        ),
      ),
      GoRoute(
        path: '/orders/:id',
        builder: (_, state) => _Deferred(
          load: order_detail.loadLibrary,
          create: () => order_detail.OrderDetailScreen(
              orderId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/profile',
        builder: (_, __) => _Deferred(
          load: profile_screen.loadLibrary,
          create: () => profile_screen.ProfileScreen(),
        ),
      ),
      GoRoute(
        path: '/wishlist',
        builder: (_, __) => _Deferred(
          load: wishlist_screen.loadLibrary,
          create: () => wishlist_screen.WishlistScreen(),
        ),
      ),
      GoRoute(
        path: '/notifications',
        builder: (_, __) => _Deferred(
          load: noti_screen.loadLibrary,
          create: () => noti_screen.NotificationsScreen(),
        ),
      ),
      GoRoute(
        path: '/payment',
        builder: (_, state) {
          final extra = state.extra as Map<String, dynamic>? ?? {};
          return _Deferred(
            load: payment_screen.loadLibrary,
            create: () => payment_screen.PaymentScreen(
              amount:  (extra['amount'] as num?)?.toDouble() ?? 0.0,
              orderId: extra['orderId'] as String?,
            ),
          );
        },
      ),
    ],
  );
}
