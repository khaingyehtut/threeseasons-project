import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:animate_do/animate_do.dart';
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../controllers/auth_controller.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  late AnimationController _orbController;
  late Animation<double> _orbAnimation;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4500),
    )..repeat(reverse: true);
    _orbAnimation =
        CurvedAnimation(parent: _orbController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _orbController.dispose();
    super.dispose();
  }

  String? _validateName(String? v) {
    if (v == null || v.trim().isEmpty) return 'name_required'.tr;
    if (v.trim().length < 2) return 'name_min'.tr;
    return null;
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'email_required'.tr;
    final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(v.trim())) return 'email_invalid'.tr;
    return null;
  }

  String? _validatePassword(String? v) {
    if (v == null || v.isEmpty) return 'password_required'.tr;
    if (v.length < 6) return 'password_min'.tr;
    return null;
  }

  String? _validateConfirm(String? v) {
    if (v == null || v.isEmpty) return 'confirm_password_prompt'.tr;
    if (v != _passwordCtrl.text) return 'passwords_no_match'.tr;
    return null;
  }

  Future<void> _handleRegister(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final success = await auth.register(
      _nameCtrl.text.trim(),
      _emailCtrl.text.trim(),
      _passwordCtrl.text,
      _phoneCtrl.text.trim(),
    );
    if (!mounted) return;
    if (success) {
      goTo('/main');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.error.value ?? 'register_failed'.tr,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          margin: const EdgeInsets.all(16),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Top-right orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: -50 + (_orbAnimation.value * 28),
              right: -70 + (_orbAnimation.value * 20),
              child: Container(
                width: 270,
                height: 270,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.30),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom-left orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              bottom: -70 + (_orbAnimation.value * 18),
              left: -60 + (_orbAnimation.value * 12),
              child: Container(
                width: 290,
                height: 290,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.16),
                      AppColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Mid accent orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: size.height * 0.45 - (_orbAnimation.value * 18),
              left: -30,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withValues(alpha: 0.14),
                      AppColors.secondary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                // App bar row
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
                  child: Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: AppColors.textPrimary,
                          size: 20,
                        ),
                        onPressed: () => goTo('/login'),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: 12),

                          // Header
                          FadeInDown(
                            duration: const Duration(milliseconds: 600),
                            child: Text(
                              'create_account'.tr,
                              style: GoogleFonts.poppins(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                                height: 1.1,
                              ),
                            ),
                          ),

                          const SizedBox(height: 8),

                          FadeInDown(
                            duration: const Duration(milliseconds: 600),
                            delay: const Duration(milliseconds: 80),
                            child: Text(
                              'join_three_seasons'.tr,
                              style: GoogleFonts.poppins(
                                fontSize: 14,
                                color: AppColors.textMedium,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                          ),

                          const SizedBox(height: 36),

                          // Full Name
                          FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 150),
                              child: _buildLabel('full_name'.tr)),
                          const SizedBox(height: 8),
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 180),
                            child: TextFormField(
                              controller: _nameCtrl,
                              textInputAction: TextInputAction.next,
                              textCapitalization: TextCapitalization.words,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary, fontSize: 14),
                              validator: _validateName,
                              decoration: _inputDecoration(
                                hint: 'full_name_hint'.tr,
                                icon: Icons.person_outline_rounded,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Email
                          FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 220),
                              child: _buildLabel('email'.tr)),
                          const SizedBox(height: 8),
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 250),
                            child: TextFormField(
                              controller: _emailCtrl,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary, fontSize: 14),
                              validator: _validateEmail,
                              decoration: _inputDecoration(
                                hint: 'you@example.com',
                                icon: Icons.email_outlined,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Phone (optional)
                          FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 290),
                              child: _buildLabel('phone_optional'.tr)),
                          const SizedBox(height: 8),
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 320),
                            child: TextFormField(
                              controller: _phoneCtrl,
                              keyboardType: TextInputType.phone,
                              textInputAction: TextInputAction.next,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary, fontSize: 14),
                              decoration: _inputDecoration(
                                hint: 'phone_hint'.tr,
                                icon: Icons.phone_outlined,
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Password
                          FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 360),
                              child: _buildLabel('password'.tr)),
                          const SizedBox(height: 8),
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 390),
                            child: TextFormField(
                              controller: _passwordCtrl,
                              obscureText: _obscurePassword,
                              textInputAction: TextInputAction.next,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary, fontSize: 14),
                              validator: _validatePassword,
                              decoration: _inputDecoration(
                                hint: '••••••••',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textMedium,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(() =>
                                      _obscurePassword = !_obscurePassword),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 18),

                          // Confirm Password
                          FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 430),
                              child: _buildLabel('confirm_password'.tr)),
                          const SizedBox(height: 8),
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 460),
                            child: TextFormField(
                              controller: _confirmPasswordCtrl,
                              obscureText: _obscureConfirm,
                              textInputAction: TextInputAction.done,
                              style: GoogleFonts.poppins(
                                  color: AppColors.textPrimary, fontSize: 14),
                              validator: _validateConfirm,
                              decoration: _inputDecoration(
                                hint: '••••••••',
                                icon: Icons.lock_outline_rounded,
                                suffix: IconButton(
                                  icon: Icon(
                                    _obscureConfirm
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: AppColors.textMedium,
                                    size: 20,
                                  ),
                                  onPressed: () => setState(
                                      () => _obscureConfirm = !_obscureConfirm),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Register button
                          Obx(() {
                            final auth = Get.find<AuthController>();
                            return FadeInUp(
                              duration: const Duration(milliseconds: 550),
                              delay: const Duration(milliseconds: 500),
                              child: _GradientButton(
                                isLoading: auth.isLoading.value,
                                label: 'create_account'.tr,
                                onTap: auth.isLoading.value
                                    ? null
                                    : () => _handleRegister(auth),
                              ),
                            );
                          }),

                          const SizedBox(height: 28),

                          // Login link
                          FadeInUp(
                            duration: const Duration(milliseconds: 550),
                            delay: const Duration(milliseconds: 540),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  '${'already_have_account'.tr} ',
                                  style: GoogleFonts.poppins(
                                    color: AppColors.textMedium,
                                    fontSize: 13,
                                  ),
                                ),
                                GestureDetector(
                                  onTap: () => goTo('/login'),
                                  child: Text(
                                    'sign_in'.tr,
                                    style: GoogleFonts.poppins(
                                      color: AppColors.primary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: GoogleFonts.poppins(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: AppColors.textLight,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.textMedium, size: 20),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppColors.surface,
      hintStyle: GoogleFonts.poppins(color: AppColors.textLight, fontSize: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: AppColors.error, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      errorStyle: GoogleFonts.poppins(fontSize: 11, color: AppColors.error),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final bool isLoading;
  final String label;
  final VoidCallback? onTap;

  const _GradientButton({
    required this.isLoading,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        height: 56,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: onTap == null
              ? LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: 0.5),
                    const Color(0xFF9C8FFF).withValues(alpha: 0.5),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                )
              : const LinearGradient(
                  colors: [Color(0xFF6C63FF), Color(0xFF9C8FFF)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          boxShadow: onTap == null
              ? []
              : [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.38),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Text(
                  label,
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
        ),
      ),
    );
  }
}
