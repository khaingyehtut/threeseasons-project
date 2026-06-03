import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController extends GetxController {
  // User-facing locale key
  static const _prefKey = 'app_locale';
  // Admin-specific locale key — changing admin language doesn't affect users
  static const _adminPrefKey = 'admin_locale';
  static const _themeKey = 'app_theme';

  final locale      = const Locale('my', 'MM').obs;
  final adminLocale = const Locale('my', 'MM').obs;
  final isDark      = false.obs;

  bool get isMyanmar      => locale.value.languageCode == 'my';
  bool get adminIsMyanmar => adminLocale.value.languageCode == 'my';

  @override
  void onInit() {
    super.onInit();
    _loadSavedLocale();
    _loadSavedTheme();
  }

  // ── User locale ───────────────────────────────────────────────────────────

  Future<void> _loadSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey) ?? 'my';
    _apply(saved == 'en' ? const Locale('en', 'US') : const Locale('my', 'MM'));
  }

  Future<void> setMyanmar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, 'my');
    _apply(const Locale('my', 'MM'));
  }

  Future<void> setEnglish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, 'en');
    _apply(const Locale('en', 'US'));
  }

  void _apply(Locale l) {
    locale.value = l;
    Get.updateLocale(l);
  }

  // ── Admin locale (independent from user locale) ───────────────────────────

  Future<void> loadAdminLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_adminPrefKey) ?? 'my';
    final l = saved == 'en' ? const Locale('en', 'US') : const Locale('my', 'MM');
    adminLocale.value = l;
    Get.updateLocale(l);
    update();
  }

  Future<void> setAdminMyanmar() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminPrefKey, 'my');
    adminLocale.value = const Locale('my', 'MM');
    Get.updateLocale(const Locale('my', 'MM'));
    update();
  }

  Future<void> setAdminEnglish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_adminPrefKey, 'en');
    adminLocale.value = const Locale('en', 'US');
    Get.updateLocale(const Locale('en', 'US'));
    update();
  }

  Future<void> _loadSavedTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final dark = prefs.getBool(_themeKey) ?? false;
    isDark.value = dark;
    Get.changeThemeMode(dark ? ThemeMode.dark : ThemeMode.light);
    update(); // triggers GetBuilder<LocaleController> in main.dart to rebuild
  }

  Future<void> toggleTheme() async {
    final newDark = !isDark.value;
    isDark.value = newDark;
    Get.changeThemeMode(newDark ? ThemeMode.dark : ThemeMode.light);
    update();
    // Rebuild every widget in the tree so StatefulWidget screens (e.g.
    // MainScreen, HomeScreen) also pick up the new AppColors.* values.
    // Obx-based screens handle it reactively; non-reactive ones need this.
    WidgetsBinding.instance.reassembleApplication();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeKey, newDark);
  }
}
