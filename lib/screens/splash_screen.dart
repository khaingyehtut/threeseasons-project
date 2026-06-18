import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import '../core/theme.dart';
import '../core/navigation.dart';
import '../controllers/auth_controller.dart';
import '../services/notification_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late AnimationController _scaleController;
  late AnimationController _orbController;
  late AnimationController _shimmerController;

  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _orbAnimation;
  late Animation<double> _shimmerAnimation;

  @override
  void initState() {
    super.initState();

    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scaleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _orbController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _scaleAnimation = Tween<double>(begin: 0.72, end: 1.0).animate(
      CurvedAnimation(parent: _scaleController, curve: Curves.easeOutBack),
    );
    _orbAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _orbController, curve: Curves.easeInOut),
    );
    _shimmerAnimation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _shimmerController, curve: Curves.linear),
    );

    _fadeController.forward();
    _scaleController.forward();

    _startNavigation();
  }

  Future<void> _startNavigation() async {
    await Future.delayed(const Duration(milliseconds: 2200));
    if (!mounted) return;
    final auth = Get.find<AuthController>();
    await auth.initialize();
    if (!mounted) return;
    if (auth.isAdmin) {
      goTo('/admin');
    } else {
      goTo('/main');
    }
    // After the new screen is rendered, process any notification tap that
    // launched the app from a terminated (fully-closed) state.
    // By this point routes are live and Get.toNamed() works correctly.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().handlePendingMessage();
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _scaleController.dispose();
    _orbController.dispose();
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(
        children: [
          // Animated purple orb - top left
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: -80 + (_orbAnimation.value * 30),
              left: -60 + (_orbAnimation.value * 20),
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.primary.withValues(alpha: 0.38),
                      AppColors.primary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // Animated secondary orb - bottom right
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              bottom: -100 + (_orbAnimation.value * 25),
              right: -70 + (_orbAnimation.value * 15),
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.secondary.withValues(alpha: 0.22),
                      AppColors.secondary.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // Accent orb - center-ish
          AnimatedBuilder(
            animation: _orbAnimation,
            builder: (_, __) => Positioned(
              top: size.height * 0.55 - (_orbAnimation.value * 20),
              left: size.width * 0.6,
              child: Container(
                width: 180,
                height: 180,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      AppColors.accent.withValues(alpha: 0.18),
                      AppColors.accent.withValues(alpha: 0.0),
                    ],
                  ),
                ),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),

          // Main content
          Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.45),
                            blurRadius: 32,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: Image.asset(
                          'assets/images/logo.png',
                          width: 110,
                          height: 110,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Brand name with shimmer
                    AnimatedBuilder(
                      animation: _shimmerAnimation,
                      builder: (_, __) {
                        return ShaderMask(
                          shaderCallback: (rect) {
                            return LinearGradient(
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                              colors: const [
                                AppColors.textWhite,
                                Color(0xFFFFFFFF),
                                AppColors.primary,
                                AppColors.textWhite,
                              ],
                              stops: [
                                (_shimmerAnimation.value - 0.3).clamp(0.0, 1.0),
                                (_shimmerAnimation.value).clamp(0.0, 1.0),
                                (_shimmerAnimation.value + 0.05)
                                    .clamp(0.0, 1.0),
                                (_shimmerAnimation.value + 0.3).clamp(0.0, 1.0),
                              ],
                            ).createShader(rect);
                          },
                          child: Text(
                            '၅၄သုံးရာသီ ဖိနပ်ဆိုင်',
                            style: GoogleFonts.poppins(
                              fontSize: 34,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        );
                      },
                    ),

                    const SizedBox(height: 8),

                    Text(
                      '54လမ်း၊ ၁၁၅Dလမ်းထောင့်',
                      style: GoogleFonts.poppins(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                        color: AppColors.textLight,
                        letterSpacing: 2.2,
                      ),
                    ),

                    const SizedBox(height: 56),

                    // Loading indicator
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.primary.withValues(alpha: 0.8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Bottom version text
          Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Text(
                'v1.0.0',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12,
                  color: AppColors.textLight.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
