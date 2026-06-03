import 'package:flutter/material.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/notifications/notifications_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/product/product_detail_screen.dart';
import '../screens/cart/cart_screen.dart';
import '../screens/chat/chat_list_screen.dart';
import '../screens/chat/chat_screen.dart';
import '../screens/orders/orders_screen.dart';
import '../screens/orders/order_detail_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/wishlist/wishlist_screen.dart';
import '../screens/admin/admin_dashboard.dart';
import '../screens/payment/payment_screen.dart';
import '../screens/splash_screen.dart';
import '../screens/main_screen.dart';

class AppRoutes {
  static const splash = '/';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';
  static const main = '/main';
  static const home = '/home';
  static const productDetail = '/product/:id';
  static const cart = '/cart';
  static const chatList = '/chats';
  static const chat = '/chat/:userId';
  static const orders = '/orders';
  static const orderDetail = '/orders/:id';
  static const profile = '/profile';
  static const wishlist = '/wishlist';
  static const adminDashboard = '/admin';
  static const notifications = '/notifications';
  static const payment = '/payment';

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final args = settings.arguments;
    switch (settings.name) {
      case splash:
        return _slide(const SplashScreen());
      case login:
        return _slide(const LoginScreen());
      case register:
        return _slide(const RegisterScreen());
      case forgotPassword:
        return _slide(const ForgotPasswordScreen());
      case main:
        return _fade(const MainScreen());
      case productDetail:
        return _slide(ProductDetailScreen(productId: args as String));
      case cart:
        return _slide(const CartScreen());
      case chatList:
        return _slide(const ChatListScreen());
      case chat:
        final map = args as Map<String, dynamic>;
        return _slide(ChatScreen(
            userId: map['userId'],
            userName: map['userName'],
            userAvatar: map['userAvatar'] ?? ''));
      case orders:
        return _slide(const OrdersScreen());
      case orderDetail:
        return _slide(OrderDetailScreen(orderId: args as String));
      case profile:
        return _slide(const ProfileScreen());
      case wishlist:
        return _slide(const WishlistScreen());
      case adminDashboard:
        return _slide(const AdminDashboard());
      case notifications:
        return _slide(const NotificationsScreen());
      case payment:
        final map = args as Map<String, dynamic>;
        return _slide(PaymentScreen(
          amount: (map['amount'] as num).toDouble(),
          orderId: map['orderId'] as String?,
        ));
      default:
        return _slide(const LoginScreen());
    }
  }

  static PageRouteBuilder _slide(Widget page) => PageRouteBuilder(
        pageBuilder: (_, a, __) => page,
        transitionsBuilder: (_, a, __, child) => SlideTransition(
          position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
              .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
          child: child,
        ),
        transitionDuration: const Duration(milliseconds: 300),
      );

  static PageRouteBuilder _fade(Widget page) => PageRouteBuilder(
        pageBuilder: (_, a, __) => page,
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      );
}
