import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../controllers/locale_controller.dart';

class AppColors {
  static const primary = Color(0xFF6C63FF);
  static const primaryDark = Color(0xFF4A42D8);
  static const primaryLight = Color(0xFFEEEDFF);
  static const secondary = Color(0xFFFF6584);
  static const accent = Color(0xFF43D9AD);
  static const warning = Color(0xFFFF9F43);
  static const error = Color(0xFFFF6B6B);
  static const success = Color(0xFF1DD1A1);

  static const darkBg = Color(0xFF0F0E1A);
  static const darkCard = Color(0xFF1A1928);
  static const darkSurface = Color(0xFF242339);
  static const darkBorder = Color(0xFF2E2D45);

  static const lightBg = Color(0xFFF8F7FF);
  static const lightCard = Color(0xFFFFFFFF);
  static const lightSurface = Color(0xFFF0EFFA);
  static const lightBorder = Color(0xFFE8E7F5);

  static const textDark = Color(0xFF1A1928);
  static const textMedium = Color(0xFF6B6B8D);
  static const textLight = Color(0xFFA0A0BD);
  static const textWhite = Color(0xFFF8F7FF);

  static const gradient1 = LinearGradient(
    colors: [Color(0xFF6C63FF), Color(0xFF9C8FFF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradient2 = LinearGradient(
    colors: [Color(0xFFFF6584), Color(0xFFFF9A9E)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
  static const gradient3 = LinearGradient(
    colors: [Color(0xFF43D9AD), Color(0xFF4ECDC4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  // Read isDark directly from the controller so these getters work correctly
  // with GoRouter (Get.isDarkMode breaks because Get.key.currentContext is null
  // when using an external routerDelegate).
  static bool get _dark {
    try {
      return Get.find<LocaleController>().isDark.value;
    } catch (_) {
      return false;
    }
  }

  static Color get bg => _dark ? darkBg : lightBg;
  static Color get card => _dark ? darkCard : lightCard;
  static Color get surface => _dark ? darkSurface : lightSurface;
  static Color get border => _dark ? darkBorder : lightBorder;
  static Color get textPrimary => _dark ? textWhite : textDark;
}

class AppTheme {
  static ThemeData get darkTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.darkBg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.dark(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.darkCard,
          error: AppColors.error,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme).copyWith(
          displayLarge: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textWhite),
          displayMedium: GoogleFonts.poppins(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textWhite),
          headlineLarge: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textWhite),
          headlineMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textWhite),
          titleLarge: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textWhite),
          titleMedium: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.textWhite),
          bodyLarge: GoogleFonts.poppins(fontSize: 14, color: AppColors.textWhite),
          bodyMedium: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMedium),
          bodySmall: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight),
        ),
        cardTheme: CardThemeData(
          color: AppColors.darkCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.darkBg,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textWhite),
          iconTheme: const IconThemeData(color: AppColors.textWhite),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.darkCard,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textLight,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.darkSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.darkBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.error)),
          hintStyle: GoogleFonts.poppins(color: AppColors.textLight, fontSize: 14),
          labelStyle: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.darkBorder, thickness: 1),
        iconTheme: const IconThemeData(color: AppColors.textWhite),
      );

  static ThemeData get lightTheme => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: AppColors.lightBg,
        primaryColor: AppColors.primary,
        colorScheme: const ColorScheme.light(
          primary: AppColors.primary,
          secondary: AppColors.secondary,
          surface: AppColors.lightCard,
          error: AppColors.error,
        ),
        textTheme: GoogleFonts.poppinsTextTheme(ThemeData.light().textTheme).copyWith(
          displayLarge: GoogleFonts.poppins(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textDark),
          headlineLarge: GoogleFonts.poppins(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textDark),
          headlineMedium: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textDark),
          titleLarge: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textDark),
          bodyLarge: GoogleFonts.poppins(fontSize: 14, color: AppColors.textDark),
          bodyMedium: GoogleFonts.poppins(fontSize: 13, color: AppColors.textMedium),
          bodySmall: GoogleFonts.poppins(fontSize: 12, color: AppColors.textLight),
        ),
        cardTheme: CardThemeData(
          color: AppColors.lightCard,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.lightBg,
          elevation: 0,
          centerTitle: false,
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.dark,
            statusBarBrightness: Brightness.light,
          ),
          titleTextStyle: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textDark),
          iconTheme: const IconThemeData(color: AppColors.textDark),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: AppColors.lightCard,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.textLight,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.lightSurface,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.lightBorder)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
          hintStyle: GoogleFonts.poppins(color: AppColors.textLight, fontSize: 14),
          labelStyle: GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 14),
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            textStyle: GoogleFonts.poppins(fontSize: 15, fontWeight: FontWeight.w600),
          ),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.lightBorder, thickness: 1),
      );
}
