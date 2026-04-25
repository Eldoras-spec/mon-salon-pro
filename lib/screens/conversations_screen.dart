import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/conversation_model.dart';
import '../services/message_service.dart';
import 'chat_screen.dart';
import '../services/app_localizations.dart';

class ConversationsScreen extends StatelessWidget {
  const ConversationsScreen({
    super.key,
    required this.currentUserId,
    required this.isClient,
    this.salonId,
  });

  final String currentUserId;
  final bool isClient;

  /// Required when [isClient] is false — the owner's salon ID.
  final String? salonId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final stream = isClient
        ? MessageService().getClientConversations(currentUserId)
        : MessageService().getOwnerConversations(salonId!);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.brand950, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              l?.tr('conversations_title') ?? 'Messages',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
          ),

          StreamBuilder<List<ConversationModel>>(
            stream: stream,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.brand600),
                  ),
                );
              }

              final convs = snap.data ?? [];

              if (convs.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 52, color: AppColors.secondary200),
                        const SizedBox(height: 16),
                        Text(
                          l?.tr('conversations_empty_title') ?? 'Aucune conversation',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            color: AppColors.secondary400,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isClient
                              ? (l?.tr('conversations_empty_client') ?? 'Contactez un salon depuis son profil.')
                              : (l?.tr('conversations_empty_owner') ?? 'Les clients peuvent vous envoyer des messages depuis votre profil.'),
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary300),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.only(bottom: 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) => _ConversationTile(
                      key: ValueKey(convs[i].id),
                      conv: convs[i],
                      currentUserId: currentUserId,
                      isClient: isClient,
                    ),
                    childCount: convs.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Conversation tile ─────────────────────────────────────────────────────────

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    super.key,
    required this.conv,
    required this.currentUserId,
    required this.isClient,
  });
  final ConversationModel conv;
  final String currentUserId;
  final bool isClient;

  @override
  Widget build(BuildContext context) {
    final unread = isClient ? conv.unreadByClient : conv.unreadByOwner;
    final hasUnread = unread > 0;
    final otherName = isClient ? conv.salonName : conv.clientName;

    final now = DateTime.now();
    final msgDate = conv.lastMessageAt;
    final isToday = msgDate.year == now.year &&
        msgDate.month == now.month &&
        msgDate.day == now.day;
    final timeLabel = isToday
        ? DateFormat('HH:mm').format(msgDate)
        : DateFormat('d MMM', 'fr_FR').format(msgDate);

    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: conv.id,
            currentUserId: currentUserId,
            isClient: isClient,
            otherPartyName: otherName,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.brand50,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.brand100),
              ),
              child: Center(
                child: Text(
                  otherName.isNotEmpty
                      ? otherName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: AppColors.brand700,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),

            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          otherName,
                          style: TextStyle(
                            fontWeight: hasUnread
                                ? FontWeight.bold
                                : FontWeight.w600,
                            fontSize: 14,
                            color: AppColors.brand950,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        timeLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: hasUnread
                              ? AppColors.brand600
                              : AppColors.secondary400,
                          fontWeight: hasUnread
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.lastMessage.isNotEmpty
                              ? conv.lastMessage
                              : '…',
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread
                                ? AppColors.secondary700
                                : AppColors.secondary400,
                            fontWeight: hasUnread
                                ? FontWeight.w500
                                : FontWeight.normal,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand600,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$unread',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
