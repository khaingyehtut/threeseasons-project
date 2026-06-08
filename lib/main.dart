import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:get/get.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'core/theme.dart';
import 'core/app_router.dart';
import 'core/translations.dart';
import 'controllers/auth_controller.dart';
import 'controllers/product_controller.dart';
import 'controllers/cart_controller.dart';
import 'controllers/order_controller.dart';
import 'controllers/chat_controller.dart';
import 'controllers/locale_controller.dart';
import 'controllers/notification_controller.dart';
import 'controllers/announcement_controller.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_in_app_messaging/firebase_in_app_messaging.dart';
import 'services/notification_service.dart';
import 'services/bt_printer_service.dart';
import 'features/pos/data/repositories/pos_repository.dart';
import 'services/barcode_server_service.dart';

// Repository implementations
import 'package:three_seasons_project/features/auth/data/repositories/auth_repository.dart';
import 'package:three_seasons_project/features/auth/domain/repositories/i_auth_repository.dart';
import 'package:three_seasons_project/features/product/data/repositories/product_repository.dart';
import 'package:three_seasons_project/features/product/domain/repositories/i_product_repository.dart';
import 'package:three_seasons_project/features/cart/data/repositories/cart_repository.dart';
import 'package:three_seasons_project/features/cart/domain/repositories/i_cart_repository.dart';
import 'package:three_seasons_project/features/order/data/repositories/order_repository.dart';
import 'package:three_seasons_project/features/order/domain/repositories/i_order_repository.dart';
import 'package:three_seasons_project/features/chat/data/repositories/chat_repository.dart';
import 'package:three_seasons_project/features/chat/domain/repositories/i_chat_repository.dart';
import 'package:three_seasons_project/features/notification/data/repositories/notification_repository.dart';
import 'package:three_seasons_project/features/notification/domain/repositories/i_notification_repository.dart';
import 'package:three_seasons_project/features/payment/data/repositories/payment_repository.dart';
import 'package:three_seasons_project/features/payment/domain/repositories/i_payment_repository.dart';

void main() async {
  usePathUrlStrategy();
  WidgetsFlutterBinding.ensureInitialized();

  // Poppins is bundled in assets/fonts/ — no network call needed.
  GoogleFonts.config.allowRuntimeFetching = false;

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Firebase Analytics — required for In-App Messaging campaigns to trigger.
  // Must be enabled before FIAM is initialized.
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(true);

  if (!kIsWeb) {
    // Enable Firestore offline persistence so reads/writes survive no-network
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );

    // Background message handler — mobile only.
    // On web, push is handled by firebase-messaging-sw.js (service worker).
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // Firebase In-App Messaging — Android/iOS/macOS only (not supported on web).
    // Calling it on web causes firebase_auth_web interop errors.
    FirebaseInAppMessaging.instance.setAutomaticDataCollectionEnabled(true);
  }
  await NotificationService().init();

  // Initialize LocaleController before runApp so theme/locale are ready
  Get.put(LocaleController(), permanent: true);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const ThreeSeasonsApp());
}

class ThreeSeasonsApp extends StatelessWidget {
  const ThreeSeasonsApp({super.key});

  @override
  Widget build(BuildContext context) {
    // GetBuilder listens to LocaleController.update() calls so the entire
    // GetMaterialApp (and therefore the whole widget tree) rebuilds when the
    // theme or locale changes — the most reliable way to trigger theme rebuilds.
    return GetBuilder<LocaleController>(
      builder: (ctrl) => GetMaterialApp.router(
        title: 'TSfootwear',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ctrl.isDark.value ? ThemeMode.dark : ThemeMode.light,
        translations: AppTranslations(),
        locale: ctrl.locale.value,
        fallbackLocale: const Locale('en', 'US'),
        routerDelegate: AppRouter.router.routerDelegate,
        routeInformationParser: AppRouter.router.routeInformationParser,
        routeInformationProvider: AppRouter.router.routeInformationProvider,
        initialBinding: BindingsBuilder(() {
          Get.put<IAuthRepository>(AuthRepository(), permanent: true);
          Get.put<IProductRepository>(ProductRepository(), permanent: true);
          Get.put<ICartRepository>(CartRepository(), permanent: true);
          Get.put<IOrderRepository>(OrderRepository(), permanent: true);
          Get.put<IChatRepository>(ChatRepository(), permanent: true);
          Get.put<INotificationRepository>(NotificationRepository(), permanent: true);
          Get.put<IPaymentRepository>(PaymentRepository(), permanent: true);
          Get.put(AuthController(), permanent: true);
          Get.put(ProductController(), permanent: true);
          Get.put(CartController(), permanent: true);
          Get.put(OrderController(), permanent: true);
          Get.put(ChatController(), permanent: true);
          Get.put(NotificationController(), permanent: true);
          Get.put(AnnouncementController(), permanent: true);
          Get.put(BtPrinterService(), permanent: true);
          Get.put(PosRepository(), permanent: true);
          Get.put(BarcodeScannerService(), permanent: true);
        }),
      ),
    );
  }
}
