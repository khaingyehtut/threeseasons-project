import 'dart:async';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:get/get.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../controllers/auth_controller.dart';
import '../../controllers/chat_controller.dart';
import '../../core/theme.dart';
import '../../models/message_model.dart';

class ChatScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userAvatar;

  const ChatScreen({
    super.key,
    required this.userId,
    required this.userName,
    this.userAvatar = '',
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();

  int _prevMessageCount = 0;
  Timer? _typingTimer;
  bool _isTyping = false;

  String get _convId {
    final myId = Get.find<AuthController>().user.value?.id ?? '';
    return ([myId, widget.userId]..sort()).join('_');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initChat());
  }

  Future<void> _initChat() async {
    final authController = Get.find<AuthController>();
    final chatController = Get.find<ChatController>();

    final myId = authController.user.value?.id ?? '';
    if (myId.isEmpty) return;

    // Block user-to-user chat — only user↔admin is allowed
    final myRole = authController.user.value?.role ?? 'user';
    if (myRole != 'admin') {
      final admins = chatController.admins;
      final otherIsAdmin = admins.any((a) => a.id == widget.userId);
      if (!otherIsAdmin) {
        // Fetch from Firestore to double-check (admins list may not be loaded yet)
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(widget.userId)
            .get();
        final role = doc.data()?['role'] as String? ?? 'user';
        if (role != 'admin') {
          if (mounted) Navigator.pop(context);
          return;
        }
      }
    }

    chatController.subscribeToMessages(myId, widget.userId);
    chatController.subscribeToTyping(_convId, widget.userId);
    _scrollToBottom(animate: false);
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    final myId = Get.find<AuthController>().user.value?.id ?? '';
    if (myId.isNotEmpty) {
      Get.find<ChatController>().setTyping(_convId, myId, false);
    }
    Get.find<ChatController>()
      ..cancelTypingSubscription()
      ..unsubscribeFromMessages();
    _inputController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      if (animate) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(0);
      }
    });
  }

  void _onTextChanged(String text) {
    final myId = Get.find<AuthController>().user.value?.id ?? '';
    if (myId.isEmpty) return;
    final chatController = Get.find<ChatController>();

    if (text.isNotEmpty && !_isTyping) {
      _isTyping = true;
      chatController.setTyping(_convId, myId, true);
    } else if (text.isEmpty && _isTyping) {
      _isTyping = false;
      _typingTimer?.cancel();
      chatController.setTyping(_convId, myId, false);
      return;
    }

    if (text.isNotEmpty) {
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 2), () {
        _isTyping = false;
        chatController.setTyping(_convId, myId, false);
      });
    }
  }

  Future<void> _sendQuickReply(String text) async {
    final me = Get.find<AuthController>().user.value;
    if (me == null) return;
    await Get.find<ChatController>().sendMessage(
      me.id,
      me.name,
      me.avatar,
      widget.userId,
      text,
      senderRole: me.role,
    );
    _scrollToBottom();
  }

  Future<void> _sendMessage() async {
    final content = _inputController.text.trim();
    if (content.isEmpty) return;

    _inputController.clear();
    _typingTimer?.cancel();
    if (_isTyping) {
      _isTyping = false;
      final myId = Get.find<AuthController>().user.value?.id ?? '';
      if (myId.isNotEmpty) {
        Get.find<ChatController>().setTyping(_convId, myId, false);
      }
    }

    final authController = Get.find<AuthController>();
    final me = authController.user.value;
    if (me == null) return;

    await Get.find<ChatController>().sendMessage(
      me.id,
      me.name,
      me.avatar,
      widget.userId,
      content,
      senderRole: me.role,
    );
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final chatController = Get.find<ChatController>();
      final myId = Get.find<AuthController>().user.value?.id ?? '';
      final messages = chatController.messages;

      // Auto-scroll when new messages arrive
      if (messages.length != _prevMessageCount) {
        _prevMessageCount = messages.length;
        // Mark incoming messages as read using the deterministic conversation ID
        final ids = [myId, widget.userId]..sort();
        final convId = ids.join('_');
        chatController.markRead(convId, myId);
        _scrollToBottom();
      }

      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: _buildAppBar(chatController),
        body: Column(
          children: [
            Expanded(
              child: chatController.isLoading.value && messages.isEmpty
                  ? _buildLoadingState()
                  : messages.isEmpty
                      ? _buildEmptyMessagesState()
                      : _buildMessagesList(messages, myId),
            ),
            if (messages.isEmpty) _buildQuickReplies(),
            if (chatController.isOtherUserTyping.value) _buildTypingIndicator(),
            _buildInputBar(),
          ],
        ),
      );
    });
  }

  PreferredSizeWidget _buildAppBar(ChatController chatController) {
    // Check if the other user is an admin via the fetched admins list
    final adminEntry =
        chatController.admins.where((a) => a.id == widget.userId).toList();
    final isAdmin = adminEntry.isNotEmpty;
    final isOnline = isAdmin ? adminEntry.first.isOnline : false;

    return AppBar(
      backgroundColor: AppColors.card,
      elevation: 0,
      leading: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(Icons.arrow_back_ios_new_rounded,
            color: AppColors.textPrimary, size: 20),
      ),
      title: Row(
        children: [
          _AvatarWithOnline(
            avatar: widget.userAvatar,
            name: widget.userName,
            isOnline: isOnline,
            size: 38,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.userName,
                  style: GoogleFonts.poppins(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Row(
                  children: [
                    if (isAdmin) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
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
                      const SizedBox(width: 6),
                    ],
                    Text(
                      isOnline ? 'online'.tr : 'offline'.tr,
                      style: GoogleFonts.poppins(
                        color:
                            isOnline ? AppColors.accent : AppColors.textLight,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      titleSpacing: 0,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: AppColors.border),
      ),
    );
  }

  Widget _buildMessagesList(
    List<MessageModel> messages,
    String myId,
  ) {
    // Build a reversed list with date separators
    final reversedMessages = messages.reversed.toList();

    return ListView.builder(
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: reversedMessages.length,
      itemBuilder: (context, index) {
        final adjustedIndex = index;
        final message = reversedMessages[adjustedIndex];
        final isMe = message.isFromMe(myId);

        // Check if we should show a date separator
        bool showDateSeparator = false;
        if (adjustedIndex < reversedMessages.length - 1) {
          final nextMessage = reversedMessages[adjustedIndex + 1];
          showDateSeparator = !_isSameDay(
            message.createdAt,
            nextMessage.createdAt,
          );
        } else {
          showDateSeparator = true; // Show for the very last (oldest) message
        }

        // Determine if last sent message (for read receipt)
        final isLastSentMessage = isMe &&
            adjustedIndex == 0 &&
            messages.isNotEmpty &&
            messages.last.isFromMe(myId);

        return Column(
          children: [
            if (showDateSeparator) _buildDateSeparator(message.createdAt),
            _MessageBubble(
              message: message,
              isMe: isMe,
              showReadReceipt: isLastSentMessage,
              prevMessage: adjustedIndex + 1 < reversedMessages.length
                  ? reversedMessages[adjustedIndex + 1]
                  : null,
              nextMessage: adjustedIndex > 0
                  ? reversedMessages[adjustedIndex - 1]
                  : null,
              myId: myId,
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateSeparator(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDay = DateTime(date.year, date.month, date.day);

    String label;
    if (messageDay == today) {
      label = 'today'.tr;
    } else if (messageDay == yesterday) {
      label = 'yesterday'.tr;
    } else {
      label = DateFormat('MMMM d, y').format(date);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border, thickness: 1)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.border),
              ),
              child: Text(
                label,
                style: GoogleFonts.poppins(
                  color: AppColors.textLight,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border, thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildQuickReplies() {
    final replies = [
      '👋 Hello!',
      '🙋 I need help',
      '❓ I have a question',
      '📦 Order issue',
    ];
    return Container(
      color: AppColors.bg,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: replies.map((text) {
            return GestureDetector(
              onTap: () => _sendQuickReply(text),
              child: Container(
                margin: const EdgeInsets.only(right: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.4)),
                ),
                child: Text(
                  text,
                  style: GoogleFonts.poppins(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 10 : 20,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                controller: _inputController,
                focusNode: _focusNode,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.poppins(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  hintText: 'type_message'.tr,
                  hintStyle: GoogleFonts.poppins(
                    color: AppColors.textLight,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                ),
                onChanged: _onTextChanged,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _inputController,
            builder: (_, value, __) {
              final hasText = value.text.trim().isNotEmpty;
              return GestureDetector(
                onTap: hasText ? _sendMessage : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: hasText ? AppColors.gradient1 : null,
                    color: hasText ? null : AppColors.surface,
                    shape: BoxShape.circle,
                    boxShadow: hasText
                        ? [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.4),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    Icons.send_rounded,
                    color: hasText ? Colors.white : AppColors.textLight,
                    size: 20,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: 6,
      itemBuilder: (_, index) => _ShimmerMessage(isMe: index.isEven),
    );
  }

  Widget _buildEmptyMessagesState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: AppColors.gradient1,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withValues(alpha: 0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(
              Icons.waving_hand_rounded,
              color: Colors.white,
              size: 34,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'say_hello'.tr,
            style: GoogleFonts.poppins(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'start_with_name'.trParams({'name': widget.userName}),
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: AppColors.textMedium,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _SmallAvatar(
            avatar: widget.userAvatar,
            name: widget.userName,
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(6),
                bottomRight: Radius.circular(18),
              ),
              border: Border.all(color: AppColors.border),
            ),
            child: const _TypingDots(),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

// ─────────────────────────────────────────────────────────
// Message Bubble
// ─────────────────────────────────────────────────────────
class _MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool showReadReceipt;
  final MessageModel? prevMessage;
  final MessageModel? nextMessage;
  final String myId;

  const _MessageBubble({
    required this.message,
    required this.isMe,
    required this.showReadReceipt,
    required this.myId,
    this.prevMessage,
    this.nextMessage,
  });

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  void _showMessageOptions(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
                color: AppColors.border,
                borderRadius: BorderRadius.circular(2)),
          ),
          ListTile(
            leading: Icon(Icons.edit_outlined, color: AppColors.primary),
            title: Text('Edit Message',
                style: GoogleFonts.poppins(color: AppColors.textPrimary)),
            onTap: () {
              Navigator.pop(context);
              _showEditDialog(context);
            },
          ),
          ListTile(
            leading: Icon(Icons.delete_outline_rounded, color: AppColors.error),
            title: Text('Delete Message',
                style: GoogleFonts.poppins(color: AppColors.error)),
            onTap: () {
              Navigator.pop(context);
              Get.find<ChatController>().deleteMessage(
                  widget.message.conversationId, widget.message.id);
            },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final ctrl = TextEditingController(text: widget.message.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Edit Message',
            style: GoogleFonts.poppins(
                color: AppColors.textPrimary, fontWeight: FontWeight.w600)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          style: GoogleFonts.poppins(color: AppColors.textPrimary),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.surface,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel',
                style: GoogleFonts.poppins(color: AppColors.textMedium)),
          ),
          ElevatedButton(
            onPressed: () {
              final newText = ctrl.text.trim();
              if (newText.isNotEmpty && newText != widget.message.content) {
                Get.find<ChatController>().editMessage(
                    widget.message.conversationId, widget.message.id, newText);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child:
                Text('Save', style: GoogleFonts.poppins(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final message = widget.message;
    final isMe = widget.isMe;
    final isDeleted = message.type == 'deleted';

    final sameAsPrev = widget.prevMessage != null &&
        widget.prevMessage!.isFromMe(widget.myId) == isMe;
    final sameAsNext = widget.nextMessage != null &&
        widget.nextMessage!.isFromMe(widget.myId) == isMe;

    final topRadius = sameAsPrev ? 6.0 : 18.0;
    final bottomRadius = sameAsNext ? 6.0 : 18.0;

    final borderRadius = isMe
        ? BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: Radius.circular(topRadius),
            bottomLeft: const Radius.circular(18),
            bottomRight: Radius.circular(bottomRadius),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(topRadius),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(bottomRadius),
            bottomRight: const Radius.circular(18),
          );

    final showAvatar = !isMe && !sameAsNext;
    final verticalPadding = sameAsPrev ? 2.0 : 4.0;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: verticalPadding),
      child: Row(
        mainAxisAlignment:
            isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMe) ...[
            if (showAvatar)
              _SmallAvatar(
                  avatar: message.senderAvatar, name: message.senderName)
            else
              const SizedBox(width: 32),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onLongPress: isMe && !isDeleted
                      ? () => _showMessageOptions(context)
                      : null,
                  child: Container(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.72),
                    decoration: BoxDecoration(
                      gradient: isMe && !isDeleted ? AppColors.gradient1 : null,
                      color: isDeleted
                          ? AppColors.surface
                          : isMe
                              ? null
                              : AppColors.card,
                      borderRadius: borderRadius,
                      border: isDeleted || !isMe
                          ? Border.all(color: AppColors.border)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: isMe && !isDeleted
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : Colors.black.withValues(alpha: 0.15),
                          blurRadius: isMe && !isDeleted ? 10 : 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: isDeleted
                        ? Text(
                            'msg_deleted'.tr,
                            style: GoogleFonts.poppins(
                              color: AppColors.textLight,
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                            ),
                          )
                        : Text(
                            message.content,
                            style: GoogleFonts.poppins(
                              color:
                                  isMe ? Colors.white : AppColors.textPrimary,
                              fontSize: 14,
                              height: 1.4,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (message.isEdited)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: Text(
                          'edited',
                          style: GoogleFonts.poppins(
                              color: AppColors.textLight,
                              fontSize: 9,
                              fontStyle: FontStyle.italic),
                        ),
                      ),
                    Text(
                      timeago.format(message.createdAt, locale: 'en_short'),
                      style: GoogleFonts.poppins(
                          color: AppColors.textLight, fontSize: 10),
                    ),
                    if (isMe && widget.showReadReceipt) ...[
                      const SizedBox(width: 4),
                      Icon(
                        message.isRead
                            ? Icons.done_all_rounded
                            : Icons.done_rounded,
                        size: 13,
                        color: message.isRead
                            ? AppColors.accent
                            : AppColors.textLight,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        message.isRead ? 'read'.tr : 'sent'.tr,
                        style: GoogleFonts.poppins(
                          color: message.isRead
                              ? AppColors.accent
                              : AppColors.textLight,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          if (isMe) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────
// Small avatar for message list
// ─────────────────────────────────────────────────────────
class _SmallAvatar extends StatelessWidget {
  final String avatar;
  final String name;

  const _SmallAvatar({required this.avatar, required this.name});

  @override
  Widget build(BuildContext context) {
    final letters = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

    return CircleAvatar(
      radius: 16,
      backgroundColor: AppColors.surface,
      child: avatar.isNotEmpty
          ? ClipOval(
              child: CachedNetworkImage(
                imageUrl: avatar,
                width: 32,
                height: 32,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _InitialsAvatar(
                  letters: letters,
                  size: 32,
                ),
              ),
            )
          : _InitialsAvatar(letters: letters, size: 32),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String letters;
  final double size;

  const _InitialsAvatar({required this.letters, required this.size});

  @override
  Widget build(BuildContext context) {
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
// Avatar with online dot (reused from chat_list)
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
    final letters = name.trim().isNotEmpty
        ? name.trim().split(' ').take(2).map((w) => w[0].toUpperCase()).join()
        : '?';

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
                    errorWidget: (_, __, ___) => _InitialsAvatar(
                      letters: letters,
                      size: size,
                    ),
                  ),
                )
              : _InitialsAvatar(letters: letters, size: size),
        ),
        if (isOnline)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: size * 0.3,
              height: size * 0.3,
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

// ─────────────────────────────────────────────────────────
// Animated typing dots
// ─────────────────────────────────────────────────────────
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (_, __) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.33;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final scale = (t < 0.5) ? 1.0 + t * 0.8 : 1.0 + (1.0 - t) * 0.8;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2.5),
              child: Transform.scale(
                scale: scale,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: AppColors.textLight,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────
// Shimmer message placeholder
// ─────────────────────────────────────────────────────────
class _ShimmerMessage extends StatefulWidget {
  final bool isMe;
  const _ShimmerMessage({required this.isMe});

  @override
  State<_ShimmerMessage> createState() => _ShimmerMessageState();
}

class _ShimmerMessageState extends State<_ShimmerMessage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.3, end: 0.8).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Opacity(
        opacity: _anim.value,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            mainAxisAlignment:
                widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              if (!widget.isMe) ...[
                CircleAvatar(
                  radius: 16,
                  backgroundColor: AppColors.surface,
                ),
                const SizedBox(width: 8),
              ],
              Container(
                width: 160 + (widget.isMe ? 20.0 : 0.0),
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
