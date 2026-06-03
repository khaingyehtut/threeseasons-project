import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:get/get.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../core/theme.dart';
import '../../models/user_model.dart';
import '../../controllers/auth_controller.dart';
import '../../controllers/chat_controller.dart';
import '../../widgets/login_required.dart';
import 'chat_screen.dart';

class ChatListScreen extends StatefulWidget {
  const ChatListScreen({super.key});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final user = Get.find<AuthController>().user.value;
    final uid = user?.id ?? '';
    final role = user?.role ?? 'user';
    if (uid.isNotEmpty) {
      Get.find<ChatController>().subscribeToConversations(uid, role: role);
    }
    await Get.find<ChatController>().fetchAdmins();
  }

  Future<void> _onRefresh() async {
    await Get.find<ChatController>().fetchAdmins();
  }

  void _openChat({
    required String userId,
    required String userName,
    required String userAvatar,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          userId: userId,
          userName: userName,
          userAvatar: userAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = Get.find<AuthController>().isLoggedIn;
    if (!isLoggedIn) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(context),
        body: LoginRequired(
          title: 'chat_support'.tr,
          subtitle: 'login_to_message'.tr,
          icon: Icons.chat_bubble_outline_rounded,
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: _buildAppBar(context),
      body: Obx(() {
        final chatController = Get.find<ChatController>();
        if (chatController.isLoading.value &&
            chatController.conversations.isEmpty &&
            chatController.admins.isEmpty) {
          return _buildShimmerLoader();
        }

        return RefreshIndicator(
          onRefresh: _onRefresh,
          color: AppColors.primary,
          backgroundColor: AppColors.card,
          child: chatController.conversations.isEmpty
              ? _buildEmptyState(chatController)
              : _buildConversationsList(chatController),
        );
      }),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.bg,
      elevation: 0,
      title: Text(
        'messages'.tr,
        style: GoogleFonts.poppins(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w700,
        ),
      ),
      actions: [
        IconButton(
          onPressed: () async {
            final chatController = Get.find<ChatController>();
            if (chatController.admins.isEmpty) {
              await chatController.fetchAdmins();
            }
            if (!context.mounted) return;
            if (chatController.admins.isEmpty) return;
            final admin = chatController.admins.firstWhere(
              (a) => a.isOnline,
              orElse: () => chatController.admins.first,
            );
            _openChat(
              userId: admin.id,
              userName: admin.name,
              userAvatar: admin.avatar,
            );
          },
          icon: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              gradient: AppColors.gradient1,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.edit_outlined,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 8),
      ],
    );
  }


  Widget _buildConversationsList(ChatController chatController) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: 8)),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final convo = chatController.conversations[index];
              return _ConversationTile(
                conversation: convo,
                onTap: () => _openChat(
                  userId: convo['otherUser']?['_id'] ?? '',
                  userName: convo['otherUser']?['name'] ?? 'Unknown',
                  userAvatar: convo['otherUser']?['avatar'] ?? '',
                ),
              );
            },
            childCount: chatController.conversations.length,
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildEmptyState(ChatController chatController) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          Center(
            child: Column(
              children: [
                Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient1,
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'no_messages'.tr,
                  style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'start_conversation_sub'.tr,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                    color: AppColors.textMedium,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
          if (chatController.admins.isNotEmpty) ...[
            Row(
              children: [
                Container(
                  width: 4,
                  height: 18,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient1,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'support_team'.tr,
                  style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...chatController.admins.map(
              (admin) => _AdminTile(
                admin: admin,
                onTap: () => _openChat(
                  userId: admin.id,
                  userName: admin.name,
                  userAvatar: admin.avatar,
                ),
              ),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildShimmerLoader() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 5,
      itemBuilder: (_, __) => _ShimmerTile(),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Conversation Tile
// ─────────────────────────────────────────────────────────
class _ConversationTile extends StatelessWidget {
  final Map<String, dynamic> conversation;
  final VoidCallback onTap;

  const _ConversationTile({
    required this.conversation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final otherUser = conversation['otherUser'] as Map<String, dynamic>? ?? {};
    final name = otherUser['name'] as String? ?? 'Unknown';
    final avatar = otherUser['avatar'] as String? ?? '';
    final isOnline = otherUser['isOnline'] as bool? ?? false;
    final isAdmin = (otherUser['role'] as String?) == 'admin';

    final lastMessage = conversation['lastMessage'] as String? ?? '';
    final rawTime = conversation['updatedAt'] as String?;
    final unreadCount = conversation['unreadCount'] as int? ?? 0;

    DateTime? updatedAt;
    if (rawTime != null) updatedAt = DateTime.tryParse(rawTime);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border, width: 1),
            ),
            child: Row(
              children: [
                _AvatarWithOnline(
                  avatar: avatar,
                  name: name,
                  isOnline: isOnline,
                  size: 50,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: GoogleFonts.poppins(
                                color: AppColors.textPrimary,
                                fontSize: 14,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (updatedAt != null)
                            Text(
                              timeago.format(updatedAt, locale: 'en_short'),
                              style: GoogleFonts.poppins(
                                color: unreadCount > 0
                                    ? AppColors.primary
                                    : AppColors.textLight,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          if (isAdmin)
                            Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                gradient: AppColors.gradient1,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'Admin',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              lastMessage.isEmpty
                                  ? 'no_last_message'.tr
                                  : lastMessage,
                              style: GoogleFonts.poppins(
                                color: unreadCount > 0
                                    ? AppColors.textPrimary
                                    : AppColors.textMedium,
                                fontSize: 13,
                                fontWeight: unreadCount > 0
                                    ? FontWeight.w500
                                    : FontWeight.normal,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                gradient: AppColors.gradient1,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Admin Tile (for "Start a conversation" section)
// ─────────────────────────────────────────────────────────
class _AdminTile extends StatelessWidget {
  final UserModel admin;
  final VoidCallback onTap;

  const _AdminTile({required this.admin, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.card,
                  AppColors.primary.withValues(alpha: 0.04),
                ],
              ),
            ),
            child: Row(
              children: [
                _AvatarWithOnline(
                  avatar: admin.avatar,
                  name: admin.name,
                  isOnline: admin.isOnline,
                  size: 48,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        admin.name,
                        style: GoogleFonts.poppins(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              gradient: AppColors.gradient1,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'support_agent'.tr,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (admin.isOnline)
                            Text(
                              'online'.tr,
                              style: GoogleFonts.poppins(
                                color: AppColors.accent,
                                fontSize: 12,
                              ),
                            )
                          else
                            Text(
                              'offline'.tr,
                              style: GoogleFonts.poppins(
                                color: AppColors.textLight,
                                fontSize: 12,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: AppColors.gradient1,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Avatar with online indicator
// ─────────────────────────────────────────────────────────
class _AvatarWithOnline extends StatelessWidget {
  final String avatar;
  final String name;
  final bool isOnline;
  final double size;

  const _AvatarWithOnline({
    required this.avatar,
    required this.name,
    required this.isOnline,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        CircleAvatar(
          radius: size / 2,
          backgroundColor: AppColors.surface,
          child: avatar.isNotEmpty
              ? ClipOval(
                  child: CachedNetworkImage(
                    imageUrl: avatar,
                    width: size,
                    height: size,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => _Initials(
                      name: name,
                      size: size,
                    ),
                  ),
                )
              : _Initials(name: name, size: size),
        ),
        if (isOnline)
          Positioned(
            right: 1,
            bottom: 1,
            child: Container(
              width: size * 0.28,
              height: size * 0.28,
              decoration: BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.card, width: 2),
              ),
            ),
          ),
      ],
    );
  }
}

class _Initials extends StatelessWidget {
  final String name;
  final double size;

  const _Initials({required this.name, required this.size});

  @override
  Widget build(BuildContext context) {
    final letters = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: AppColors.gradient1,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        letters,
        style: GoogleFonts.poppins(
          color: Colors.white,
          fontSize: size * 0.32,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Shimmer placeholder tile
// ─────────────────────────────────────────────────────────
class _ShimmerTile extends StatefulWidget {
  @override
  State<_ShimmerTile> createState() => _ShimmerTileState();
}

class _ShimmerTileState extends State<_ShimmerTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.4, end: 1.0).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (_, __) => Opacity(
        opacity: _animation.value,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 13,
                        width: 130,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        height: 11,
                        width: 200,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
