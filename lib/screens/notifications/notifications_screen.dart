import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../core/theme.dart';
import '../../core/navigation.dart';
import '../../controllers/notification_controller.dart';
import '../../models/notification_model.dart';

class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<NotificationController>();

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Obx(() {
            if (ctrl.unreadCount.value == 0) return const SizedBox.shrink();
            return TextButton(
              onPressed: () => ctrl.markAllAsRead(),
              child: Text(
                'Mark all read',
                style: GoogleFonts.poppins(
                  color: AppColors.primary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            );
          }),
        ],
      ),
      body: Obx(() {
        final list = ctrl.notifications;

        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.notifications_off_outlined,
                  color: AppColors.textMedium,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'No notifications yet',
                  style: GoogleFonts.poppins(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'We\'ll let you know when something happens',
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.textMedium,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          itemCount: list.length,
          itemBuilder: (context, i) {
            final n = list[i];
            return _NotificationCard(
              notification: n,
              onTap: () async {
                await ctrl.markAsRead(n.id);
                final hasOrder = n.data.containsKey('orderId');
                if ((n.type == 'order_status' || n.type == 'order_placed') &&
                    hasOrder &&
                    context.mounted) {
                  pushTo('/orders/${n.data['orderId'] as String}');
                }
              },
            );
          },
        );
      }),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final NotificationModel notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  static IconData _iconFor(String type) {
    switch (type) {
      case 'order_placed':
        return Icons.shopping_bag_rounded;
      case 'order_status':
      case 'shipping':
        return Icons.local_shipping_rounded;
      case 'order_success':
        return Icons.check_circle_rounded;
      case 'processing':
        return Icons.hourglass_bottom_rounded;
      case 'promo':
        return Icons.local_offer_rounded;
      case 'system':
        return Icons.shield_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  static Color _colorFor(String type) {
    switch (type) {
      case 'order_placed':
        return const Color(0xFF8B5CF6); // purple  (admin)
      case 'order_status':
      case 'shipping':
        return const Color(0xFFFF9F43); // orange
      case 'order_success':
        return const Color(0xFF10B981); // green
      case 'processing':
        return const Color(0xFFF59E0B); // amber
      case 'promo':
        return const Color(0xFFEC4899); // pink
      case 'system':
        return const Color(0xFF3B82F6); // blue
      default:
        return const Color(0xFF8B5CF6); // purple
    }
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _colorFor(notification.type);

    final bgColor = notification.isRead
        ? Colors.transparent
        : AppColors.primary.withValues(alpha: 0.06);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: notification.isRead ? AppColors.card : bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: notification.isRead
                ? AppColors.border
                : AppColors.primary.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon circle
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                _iconFor(notification.type),
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    notification.title,
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: notification.isRead
                          ? FontWeight.w500
                          : FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    notification.body,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: AppColors.textMedium,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    timeago.format(notification.createdAt, locale: 'en_short'),
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: AppColors.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            // Unread dot
            if (!notification.isRead) ...[
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                margin: const EdgeInsets.only(top: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
