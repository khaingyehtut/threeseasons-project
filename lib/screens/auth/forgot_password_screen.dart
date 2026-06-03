import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:animate_do/animate_do.dart';
import '../../core/theme.dart';
import '../../core/responsive.dart';
import '../../controllers/auth_controller.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  bool _emailSent = false;

  late AnimationController _orbController;
  late Animation<double> _orbAnimation;

  @override
  void initState() {
    super.initState();
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    )..repeat(reverse: true);
    _orbAnimation =
        CurvedAnimation(parent: _orbController, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _orbController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? v) {
    if (v == null || v.trim().isEmpty) return 'email_required'.tr;
    final emailRegex = RegExp(r'^[\w-.]+@([\w-]+\.)+[\w-]{2,4}$');
    if (!emailRegex.hasMatch(v.trim())) return 'email_invalid'.tr;
    return null;
  }

  Future<void> _handleSendReset(AuthController auth) async {
    if (!_formKey.currentState!.validate()) return;
    final success = await auth.sendPasswordReset(_emailCtrl.text.trim());
    if (!mounted) return;
    if (success) {
      setState(() => _emailSent = true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.error.value ?? 'error'.tr,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
          ),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          // Top-left orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: -60 + (_orbAnimation.value * 24),
              left: -80 + (_orbAnimation.value * 18),
              child: Container(
                width: 260,
                height: 260,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.32),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Bottom-right orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              bottom: -80 + (_orbAnimation.value * 20),
              right: -60 + (_orbAnimation.value * 14),
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withValues(alpha: 0.20),
                      AppColors.secondary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // Accent orb
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: size.height * 0.4 + (_orbAnimation.value * 16),
              right: -40,
              child: Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.14),
                      AppColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: Responsive.pagePadding(context),
                vertical: 0,
              ),
              child: Responsive.centreForm(
                context,
                _emailSent ? _buildSuccessState() : _buildFormState(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormState() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 56),

          // Back arrow
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary,
              size: 22,
            ),
          ),

          const SizedBox(height: 28),

          // Lock icon
          FadeInDown(
            duration: const Duration(milliseconds: 600),
            child: Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: AppColors.gradient1,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.40),
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                color: Colors.white,
                size: 30,
              ),
            ),
          ),

          const SizedBox(height: 28),

          FadeInDown(
            duration: const Duration(milliseconds: 650),
            delay: const Duration(milliseconds: 80),
            child: Text(
              'forgot_password_title'.tr,
              style: GoogleFonts.poppins(
                fontSize: 25,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                height: 1.1,
              ),
            ),
          ),

          const SizedBox(height: 8),

          FadeInDown(
            duration: const Duration(milliseconds: 650),
            delay: const Duration(milliseconds: 130),
            child: Text(
              'forgot_password_subtitle'.tr,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textMedium,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),

          const SizedBox(height: 44),

          // Email label
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 200),
            child: Text(
              'email'.tr,
              style: GoogleFonts.poppins(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.textLight,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 230),
            child: TextFormField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary, fontSize: 14),
              validator: _validateEmail,
              decoration: _inputDecoration(
                hint: 'you@example.com',
                icon: Icons.email_outlined,
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Send button
          Obx(() {
            final auth = Get.find<AuthController>();
            return FadeInUp(
              duration: const Duration(milliseconds: 600),
              delay: const Duration(milliseconds: 300),
              child: _GradientButton(
                isLoading: auth.isLoading.value,
                label: 'send_reset_email'.tr,
                onTap: auth.isLoading.value
                    ? null
                    : () => _handleSendReset(auth),
              ),
            );
          }),

          const SizedBox(height: 28),

          // Back to login
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            delay: const Duration(milliseconds: 370),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.arrow_back_rounded,
                    size: 15, color: AppColors.textMedium),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text(
                    'back_to_login'.tr,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.primary,
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
    );
  }

  Widget _buildSuccessState() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 80),

        // Checkmark circle
        FadeInDown(
          duration: const Duration(milliseconds: 600),
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppColors.gradient1,
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.40),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),

        const SizedBox(height: 36),

        FadeInUp(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 100),
          child: Text(
            'check_your_email'.tr,
            style: GoogleFonts.poppins(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ),

        const SizedBox(height: 12),

        FadeInUp(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 160),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              'reset_email_sent_desc'.tr,
              style: GoogleFonts.poppins(
                fontSize: 14,
                color: AppColors.textMedium,
                height: 1.6,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),

        const SizedBox(height: 16),

        FadeInUp(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(
              _emailCtrl.text.trim(),
              style: GoogleFonts.poppins(
                fontSize: 13,
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),

        const SizedBox(height: 48),

        FadeInUp(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 260),
          child: _GradientButton(
            isLoading: false,
            label: 'back_to_login'.tr,
            onTap: () => Navigator.pop(context),
          ),
        ),

        const SizedBox(height: 24),

        FadeInUp(
          duration: const Duration(milliseconds: 600),
          delay: const Duration(milliseconds: 320),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${'reset_email_not_received'.tr} ',
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: AppColors.textMedium,
                ),
              ),
              Obx(() {
                final auth = Get.find<AuthController>();
                return GestureDetector(
                  onTap: auth.isLoading.value
                      ? null
                      : () async {
                          final success = await auth
                              .sendPasswordReset(_emailCtrl.text.trim());
                          if (mounted && !success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  auth.error.value ?? 'error'.tr,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontSize: 13),
                                ),
                                backgroundColor: AppColors.error,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          } else if (mounted && success) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'password_reset_sent'.tr,
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontSize: 13),
                                ),
                                backgroundColor: AppColors.success,
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                margin: const EdgeInsets.all(16),
                              ),
                            );
                          }
                        },
                  child: Text(
                    'resend'.tr,
                    style: GoogleFonts.poppins(
                      fontSize: 13,
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }),
            ],
          ),
        ),

        const SizedBox(height: 40),
      ],
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: AppColors.textMedium, size: 20),
      filled: true,
      fillColor: AppColors.surface,
      hintStyle:
          GoogleFonts.poppins(color: AppColors.textLight, fontSize: 14),
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
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      errorStyle:
          GoogleFonts.poppins(fontSize: 11, color: AppColors.error),
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
                    color: AppColors.primary.withValues(alpha: 0.40),
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
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
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
