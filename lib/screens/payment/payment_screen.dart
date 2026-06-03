import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';

import '../../controllers/auth_controller.dart';
import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../services/payment_service.dart';
import '../../models/payment_model.dart';

class _Account {
  final String method;
  final String name;
  final String number;
  final String bankName;
  final Color color;
  final Color bgColor;
  const _Account({
    required this.method,
    required this.name,
    required this.number,
    required this.bankName,
    required this.color,
    required this.bgColor,
  });
}

// ─────────────────────────────────────────────────────────────────────────────

class PaymentScreen extends StatefulWidget {
  final double amount;
  final String? orderId;

  const PaymentScreen({super.key, required this.amount, this.orderId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  Uint8List? _screenshotBytes;
  String _screenshotFilename = 'screenshot.jpg';
  bool _isSubmitting = false;
  PaymentModel? _submitted;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadExisting();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    if (widget.orderId == null) return;
    final uid = Get.find<AuthController>().user.value?.id ?? '';
    if (uid.isEmpty) return;
    final snap = await PaymentService()
        .userPaymentsStream(uid)
        .first
        .catchError((_) => <PaymentModel>[]);
    final existing = snap.where((p) => p.orderId == widget.orderId).toList();
    if (existing.isNotEmpty && mounted) {
      setState(() => _submitted = existing.first);
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      final bytes = await picked.readAsBytes();
      final name = picked.name.isNotEmpty ? picked.name : 'screenshot.jpg';
      setState(() {
        _screenshotBytes = bytes;
        _screenshotFilename = name;
      });
    }
  }

  Future<void> _submit() async {
    if (_screenshotBytes == null) {
      _showSnack('Please select your payment screenshot', isError: true);
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final idToken = await AuthService().getIdToken();
      if (idToken == null) throw Exception('Please log in again.');

      final payment = await PaymentService().submitPayment(
        screenshotBytes: _screenshotBytes!,
        screenshotFilename: _screenshotFilename,
        amount: widget.amount,
        paymentMethod: _tabCtrl.index == 0 ? 'KPay' : 'Wave Money',
        firebaseIdToken: idToken,
        orderId: widget.orderId,
      );
      if (mounted)
        setState(() {
          _submitted = payment;
          _isSubmitting = false;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _error = e.toString();
          _isSubmitting = false;
        });
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 13)),
      backgroundColor: isError ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Manual Payment',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700)),
      ),
      body: _submitted != null ? _buildStatusView() : _buildPaymentForm(),
    );
  }

  // ── Status view (after submission) ────────────────────────────────────────

  Widget _buildStatusView() {
    final p = _submitted!;
    final isApproved = p.isApproved;
    final isRejected = p.isRejected;
    final color = isApproved
        ? AppColors.success
        : isRejected
            ? AppColors.error
            : AppColors.warning;
    final icon = isApproved
        ? Icons.check_circle_rounded
        : isRejected
            ? Icons.cancel_rounded
            : Icons.hourglass_top_rounded;
    final label = isApproved
        ? 'Payment Approved!'
        : isRejected
            ? 'Payment Rejected'
            : 'Awaiting Verification';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        const SizedBox(height: 16),
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 44),
        ),
        const SizedBox(height: 16),
        Text(label,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        if (isRejected && p.adminNote.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              Icon(Icons.info_outline_rounded,
                  color: AppColors.error, size: 16),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Reason: ${p.adminNote}',
                    style: GoogleFonts.poppins(
                        color: AppColors.error, fontSize: 13)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (!isApproved)
          Text(
            isRejected
                ? 'Please retransfer and submit a new screenshot.'
                : 'Admin will verify your payment shortly.',
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 24),
        _InfoRow('Method', p.paymentMethod),
        _InfoRow('Amount', '${p.amount.toStringAsFixed(0)} MMK'),
        _InfoRow('Status', p.status.toUpperCase()),
        if (p.orderId != null) _InfoRow('Order ID', p.orderId!),
        const SizedBox(height: 24),
        if (p.screenshotUrl.isNotEmpty)
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: CachedNetworkImage(
              imageUrl: p.screenshotUrl,
              height: 260,
              width: double.infinity,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => Container(
                height: 260,
                color: AppColors.surface,
                child: Icon(Icons.image_not_supported_outlined,
                    color: AppColors.textMedium, size: 48),
              ),
            ),
          ),
        if (isRejected) ...[
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius: BorderRadius.circular(16),
              ),
              child: ElevatedButton(
                onPressed: () => setState(() {
                  _submitted = null;
                  _screenshotBytes = null;
                }),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.transparent,
                  shadowColor: Colors.transparent,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('Try Again',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  // ── Payment form ──────────────────────────────────────────────────────────

  Widget _buildPaymentForm() {
    return StreamBuilder<Map<String, String>>(
      stream: PaymentService().accountSettingsStream(),
      builder: (context, snap) {
        final s = snap.data;
        final kpay = _Account(
          method: 'KPay',
          name: s?['kpayName'] ?? 'TSfootwear',
          number: s?['kpayNumber'] ?? '—',
          bankName: 'KBZ Pay',
          color: const Color(0xFFE5007E),
          bgColor: const Color(0xFFFFF0F8),
        );
        final wave = _Account(
          method: 'Wave Money',
          name: s?['waveName'] ?? 'TSfootwear',
          number: s?['waveNumber'] ?? '—',
          bankName: 'Wave Money',
          color: const Color(0xFF003087),
          bgColor: const Color(0xFFF0F4FF),
        );

        return Column(children: [
          // Tab bar: KPay / Wave
          Container(
            margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: TabBar(
              controller: _tabCtrl,
              indicator: BoxDecoration(
                gradient: AppColors.gradient1,
                borderRadius: BorderRadius.circular(12),
              ),
              indicatorSize: TabBarIndicatorSize.tab,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.textMedium,
              labelStyle: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w600),
              unselectedLabelStyle: GoogleFonts.poppins(
                  fontSize: 14, fontWeight: FontWeight.w500),
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/icons/kpay.png', width: 20, height: 20),
                    const SizedBox(width: 6),
                    const Text('KPay'),
                  ]),
                ),
                Tab(
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Image.asset('assets/icons/wavepay.png',
                        width: 20, height: 20),
                    const SizedBox(width: 6),
                    const Text('Wave Money'),
                  ]),
                ),
              ],
            ),
          ),

          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildTabContent(kpay),
                _buildTabContent(wave),
              ],
            ),
          ),
        ]);
      },
    );
  }

  Widget _buildTabContent(_Account account) {
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).viewInsets.bottom + 32),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ── Step 1: Account details ──────────────────────────────────────
        _StepHeader(number: '1', title: 'Transfer to this account'),
        const SizedBox(height: 12),
        _buildAccountCard(account),

        const SizedBox(height: 24),
        // ── Step 2: Amount ───────────────────────────────────────────────
        _StepHeader(number: '2', title: 'Amount to transfer'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
          ),
          child: Row(children: [
            Text(
              '${widget.amount.toStringAsFixed(0)} MMK',
              style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            Icon(Icons.payments_rounded, color: AppColors.primary, size: 32),
          ]),
        ),

        const SizedBox(height: 24),
        // ── Step 3: Upload screenshot ────────────────────────────────────
        _StepHeader(number: '3', title: 'Upload transfer screenshot'),
        const SizedBox(height: 12),
        _buildScreenshotPicker(),

        if (_error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
            ),
            child: Text(_error!,
                style:
                    GoogleFonts.poppins(color: AppColors.error, fontSize: 13)),
          ),
        ],

        const SizedBox(height: 28),
        // ── Submit button ────────────────────────────────────────────────
        SizedBox(
          width: double.infinity,
          height: 54,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: AppColors.gradient1,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4)),
              ],
            ),
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.send_rounded,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 8),
                      Text('Submit Payment',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildAccountCard(_Account account) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(children: [
        // Logo circle
        Container(
          width: 54,
          height: 54,
          decoration:
              BoxDecoration(color: account.bgColor, shape: BoxShape.circle),
          child: Center(
            child: Image.asset(
              account.method == 'KPay'
                  ? 'assets/icons/kpay.png'
                  : 'assets/icons/wavepay.png',
              width: 32,
              height: 32,
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(account.bankName,
                style: GoogleFonts.poppins(
                    color: AppColors.textMedium,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(account.name,
                style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: account.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8)),
              child: Text(account.number,
                  style: GoogleFonts.poppins(
                      color: account.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5)),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildScreenshotPicker() {
    if (_screenshotBytes != null) {
      return Stack(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.memory(
            _screenshotBytes!,
            height: 220,
            width: double.infinity,
            fit: BoxFit.cover,
          ),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: () => setState(() => _screenshotBytes = null),
            child: Container(
              width: 32,
              height: 32,
              decoration:
                  BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
              child: const Icon(Icons.close_rounded,
                  color: Colors.white, size: 18),
            ),
          ),
        ),
      ]);
    }

    return GestureDetector(
      onTap: () => _showImageSourceSheet(),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.primary.withValues(alpha: 0.3),
              width: 1.5,
              style: BorderStyle.solid),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_photo_alternate_outlined,
              color: AppColors.primary, size: 40),
          const SizedBox(height: 10),
          Text('Tap to upload screenshot',
              style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('PNG, JPG up to 10 MB',
              style: GoogleFonts.poppins(
                  color: AppColors.textMedium, fontSize: 12)),
        ]),
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          Text('Select Screenshot',
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: _SourceButton(
                icon: Icons.photo_library_outlined,
                label: 'Gallery',
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ),
            if (!kIsWeb) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _SourceButton(
                  icon: Icons.camera_alt_outlined,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickImage(ImageSource.camera);
                  },
                ),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

// ── Small helper widgets ───────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final String number;
  final String title;
  const _StepHeader({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            gradient: AppColors.gradient1, shape: BoxShape.circle),
        child: Center(
          child: Text(number,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      ),
      const SizedBox(width: 10),
      Text(title,
          style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600)),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Text(label,
            style:
                GoogleFonts.poppins(color: AppColors.textMedium, fontSize: 13)),
        const Spacer(),
        Text(value,
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _SourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SourceButton(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(children: [
          Icon(icon, color: AppColors.primary, size: 28),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}
