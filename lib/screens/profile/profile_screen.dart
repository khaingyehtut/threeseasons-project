import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:animate_do/animate_do.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/locale_controller.dart';
import '../../widgets/login_required.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final auth = Get.find<AuthController>();
        if (!auth.isLoggedIn) {
          return Scaffold(
            backgroundColor: AppColors.bg,
            body: SafeArea(
              child: LoginRequired(
                title: 'your_profile'.tr,
                subtitle: 'login_to_profile'.tr,
                icon: Icons.person_outline_rounded,
              ),
            ),
          );
        }

        final user = auth.user.value;
        final initial = (user?.name.isNotEmpty == true)
            ? user!.name[0].toUpperCase()
            : '?';

        return Scaffold(
          backgroundColor: AppColors.bg,
          body: CustomScrollView(
            slivers: [
              // Header sliver
              SliverToBoxAdapter(
                child: _ProfileHeader(
                  initial: initial,
                  name: user?.name ?? 'Guest',
                  email: user?.email ?? '',
                  avatarUrl: user?.avatar ?? '',
                  isAdmin: auth.isAdmin,
                ),
              ),

              // Menu items
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: const Duration(milliseconds: 200),
                      child: _SectionLabel('account'.tr),
                    ),
                    const SizedBox(height: 10),
                    FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: const Duration(milliseconds: 250),
                      child: _MenuCard(
                        children: [
                          _MenuItem(
                            icon: Icons.shopping_bag_outlined,
                            iconColor: AppColors.primary,
                            label: 'my_orders_menu'.tr,
                            onTap: () => pushTo('/orders'),
                          ),
                          _Divider(),
                          _MenuItem(
                            icon: Icons.favorite_border_rounded,
                            iconColor: AppColors.secondary,
                            label: 'my_wishlist'.tr,
                            onTap: () => pushTo('/wishlist'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: const Duration(milliseconds: 310),
                      child: _SectionLabel('settings'.tr),
                    ),
                    const SizedBox(height: 10),
                    FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: const Duration(milliseconds: 360),
                      child: _MenuCard(
                        children: [
                          _MenuItem(
                            icon: Icons.lock_outline_rounded,
                            iconColor: AppColors.accent,
                            label: 'change_password'.tr,
                            onTap: () => _showChangePasswordDialog(context, auth),
                          ),
                          _Divider(),
                          _MenuItem(
                            icon: Icons.language_rounded,
                            iconColor: AppColors.primary,
                            label: 'language'.tr,
                            onTap: () => _showLanguageSheet(context),
                          ),
                          _Divider(),
                          _ThemeToggleItem(),
                          _Divider(),
                          _MenuItem(
                            icon: Icons.info_outline_rounded,
                            iconColor: AppColors.textMedium,
                            label: 'about'.tr,
                            onTap: () => _showAboutDialog(context),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Logout button
                    FadeInUp(
                      duration: const Duration(milliseconds: 500),
                      delay: const Duration(milliseconds: 420),
                      child: _LogoutButton(auth: auth),
                    ),
                    const SizedBox(height: 40),
                  ]),
                ),
              ),
            ],
          ),
        );
    });
  }

  void _showLanguageSheet(BuildContext context) {
    final locale = Get.find<LocaleController>();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Obx(() {
        final isMM = locale.isMyanmar;
        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                'select_language'.tr,
                style: GoogleFonts.poppins(
                  fontSize: 16, fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              _LangOption(
                label: 'lang_myanmar'.tr,
                flag: '🇲🇲',
                isSelected: isMM,
                onTap: () { locale.setMyanmar(); Navigator.pop(context); },
              ),
              const SizedBox(height: 10),
              _LangOption(
                label: 'lang_english'.tr,
                flag: '🇬🇧',
                isSelected: !isMM,
                onTap: () { locale.setEnglish(); Navigator.pop(context); },
              ),
            ],
          ),
        );
      }),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'about_title'.tr,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Text(
          'about_content'.tr,
          style: GoogleFonts.poppins(
              fontSize: 13, color: AppColors.textMedium, height: 1.6),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('ok'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, AuthController auth) {
    final currentCtrl = TextEditingController();
    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'change_password'.tr,
          style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DialogField(
                  controller: currentCtrl,
                  hint: 'current_password'.tr,
                  obscure: true),
              const SizedBox(height: 12),
              _DialogField(
                  controller: newCtrl,
                  hint: 'new_password'.tr,
                  obscure: true,
                  validator: (v) => (v == null || v.length < 6)
                      ? 'min_6_chars'.tr
                      : null),
              const SizedBox(height: 12),
              _DialogField(
                controller: confirmCtrl,
                hint: 'confirm_new_password'.tr,
                obscure: true,
                validator: (v) =>
                    v != newCtrl.text ? 'passwords_no_match'.tr : null,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('cancel'.tr,
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          TextButton(
            onPressed: () async {
              if (!formKey.currentState!.validate()) return;
              final success = await auth.changePassword(
                  currentCtrl.text, newCtrl.text);
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    success
                        ? 'password_changed'.tr
                        : auth.error.value ?? 'failed_change_password'.tr,
                    style: GoogleFonts.poppins(
                        color: Colors.white, fontSize: 13),
                  ),
                  backgroundColor:
                      success ? AppColors.success : AppColors.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.all(16),
                ),
              );
            },
            child: Text('save'.tr,
                style: GoogleFonts.poppins(
                    color: AppColors.primary, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Profile Header
// ─────────────────────────────────────────────────────────────
class _ProfileHeader extends StatelessWidget {
  final String initial;
  final String name;
  final String email;
  final String avatarUrl;
  final bool isAdmin;

  const _ProfileHeader({
    required this.initial,
    required this.name,
    required this.email,
    required this.avatarUrl,
    required this.isAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          24, MediaQuery.of(context).padding.top + 24, 24, 32),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.card, AppColors.bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          FadeInDown(
            duration: const Duration(milliseconds: 600),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9C8FFF)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.40),
                        blurRadius: 24,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: avatarUrl.isNotEmpty
                      ? ClipOval(
                          child: Image.network(
                            avatarUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                initial,
                                style: GoogleFonts.poppins(
                                  fontSize: 34,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Center(
                          child: Text(
                            initial,
                            style: GoogleFonts.poppins(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                ),
                // Camera edit icon
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.bg, width: 2),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: 14,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          FadeInDown(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 80),
            child: Text(
              name,
              style: GoogleFonts.poppins(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),

          const SizedBox(height: 4),

          FadeInDown(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 130),
            child: Text(
              email,
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.textMedium,
              ),
            ),
          ),

          if (isAdmin) ...[
            const SizedBox(height: 12),
            FadeInDown(
              duration: const Duration(milliseconds: 600),
              delay: const Duration(milliseconds: 180),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFFF6584), Color(0xFFFF9A9E)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.verified_rounded,
                        size: 13, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(
                      'Admin',
                      style: GoogleFonts.poppins(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Menu card wrapper
// ─────────────────────────────────────────────────────────────
class _MenuCard extends StatelessWidget {
  final List<Widget> children;
  const _MenuCard({required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: children,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Menu item row
// ─────────────────────────────────────────────────────────────
class _MenuItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _MenuItem({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: AppColors.textLight,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Internal divider
// ─────────────────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: AppColors.border,
      indent: 70,
      endIndent: 0,
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Theme toggle row
// ─────────────────────────────────────────────────────────────
class _ThemeToggleItem extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final localeCtrl = Get.find<LocaleController>();
    return Obx(() {
      final isDark = localeCtrl.isDark.value;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded,
                color: AppColors.warning,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                isDark ? 'Dark Mode' : 'Light Mode',
                style: GoogleFonts.poppins(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Switch(
              value: isDark,
              onChanged: (_) => localeCtrl.toggleTheme(),
              activeThumbColor: AppColors.primary,
            ),
          ],
        ),
      );
    });
  }
}

// ─────────────────────────────────────────────────────────────
// Section label
// ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppColors.textMedium,
        letterSpacing: 1.0,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Logout button
// ─────────────────────────────────────────────────────────────
class _LogoutButton extends StatelessWidget {
  final AuthController auth;
  const _LogoutButton({required this.auth});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: auth.isLoading.value
          ? null
          : () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: AppColors.card,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  title: Text(
                    'Sign Out',
                    style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary),
                  ),
                  content: Text(
                    'Are you sure you want to sign out?',
                    style: GoogleFonts.poppins(
                        fontSize: 13, color: AppColors.textMedium),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel',
                          style: GoogleFonts.poppins(
                              color: AppColors.textMedium)),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(
                        'Sign Out',
                        style: GoogleFonts.poppins(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await auth.logout();
                if (context.mounted) {
                  goTo('/login');
                }
              }
            },
      child: Container(
        width: double.infinity,
        height: 54,
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppColors.error.withValues(alpha: 0.30), width: 1),
        ),
        child: Center(
          child: auth.isLoading.value
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(AppColors.error),
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.logout_rounded,
                        color: AppColors.error, size: 20),
                    const SizedBox(width: 10),
                    Text(
                      'Sign Out',
                      style: GoogleFonts.poppins(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.error,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Dialog text field helper
// ─────────────────────────────────────────────────────────────
class _DialogField extends StatefulWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final String? Function(String?)? validator;

  const _DialogField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.validator,
  });

  @override
  State<_DialogField> createState() => _DialogFieldState();
}

class _DialogFieldState extends State<_DialogField> {
  late bool _obscure;

  @override
  void initState() {
    super.initState();
    _obscure = widget.obscure;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      obscureText: _obscure,
      validator: widget.validator,
      style: GoogleFonts.poppins(color: AppColors.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        hintText: widget.hint,
        hintStyle:
            GoogleFonts.poppins(color: AppColors.textLight, fontSize: 13),
        filled: true,
        fillColor: AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.error, width: 1.5),
        ),
        errorStyle:
            GoogleFonts.poppins(fontSize: 10, color: AppColors.error),
        suffixIcon: widget.obscure
            ? IconButton(
                icon: Icon(
                  _obscure
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  color: AppColors.textMedium,
                  size: 18,
                ),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  final String label;
  final String flag;
  final bool isSelected;
  final VoidCallback onTap;

  const _LangOption({
    required this.label,
    required this.flag,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.15)
              : AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Text(flag, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppColors.primary : AppColors.textPrimary,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded,
                  color: AppColors.primary, size: 22),
          ],
        ),
      ),
    );
  }
}
