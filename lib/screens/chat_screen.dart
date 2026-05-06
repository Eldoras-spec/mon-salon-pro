import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../models/message_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import '../services/notification_service.dart';
import '../services/app_localizations.dart';
import '../utils/currency_helper.dart';
import '../widgets/member_avatar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({
    super.key,
    required this.conversationId,
    required this.currentUserId,
    required this.isClient,
    required this.otherPartyName,
  });

  /// The deterministic conversation doc ID.
  final String conversationId;

  /// UID of the currently logged-in user.
  final String currentUserId;

  /// True if the current user is a client, false if owner.
  final bool isClient;

  /// Display name shown in the app-bar (salon name for client, client name for owner).
  final String otherPartyName;

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _svc = MessageService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;
  SalonModel? _salon;

  /// Heartbeat that refreshes `users/{uid}.activeConversationLastSeen`
  /// every 30s while the user is on this chat. The `onNewMessage` CF
  /// uses the freshness check to skip the FCM `notification` payload
  /// (silencing the iOS auto-banner) when the recipient is currently
  /// viewing the matching chat.
  Timer? _activeChatHeartbeat;

  // ── Owner quick-reply templates ──────────────────────────────────────
  List<Map<String, String>> _getQuickReplies(AppLocalizations? l) => [
    {'label': l?.tr('chat_quick_rdv_confirmed') ?? 'RDV confirmé', 'text': l?.tr('chat_quick_rdv_confirmed_text') ?? 'Votre rendez-vous est bien confirmé. À bientôt !'},
    {'label': l?.tr('chat_quick_rdv_reminder') ?? 'Rappel RDV', 'text': l?.tr('chat_quick_rdv_reminder_text') ?? 'N\'oubliez pas votre rendez-vous prévu prochainement.'},
    {'label': l?.tr('chat_quick_salon_closed') ?? 'Salon fermé', 'text': l?.tr('chat_quick_salon_closed_text') ?? 'Notre salon est actuellement fermé. Nous serons ravis de vous accueillir à la réouverture.'},
    {'label': l?.tr('chat_quick_thanks') ?? 'Merci', 'text': l?.tr('chat_quick_thanks_text') ?? 'Merci beaucoup ! N\'hésitez pas si vous avez d\'autres questions.'},
    {'label': l?.tr('chat_quick_cancellation') ?? 'Annulation', 'text': l?.tr('chat_quick_cancellation_text') ?? 'Votre rendez-vous a été annulé. N\'hésitez pas à reprendre rendez-vous quand vous le souhaitez.'},
  ];

  @override
  void initState() {
    super.initState();
    // Silence foreground push banners for the conversation being viewed.
    NotificationService.activeConversationId = widget.conversationId;
    WidgetsBinding.instance.addObserver(this);
    _markActiveChat();
    if (widget.isClient) {
      _svc.markReadByClient(widget.conversationId);
      _loadSalon();
    } else {
      _svc.markReadByOwner(widget.conversationId);
    }
  }

  void _markActiveChat() {
    _writeActiveChat();
    _activeChatHeartbeat?.cancel();
    _activeChatHeartbeat = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _writeActiveChat(),
    );
  }

  Future<void> _writeActiveChat() async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.currentUserId)
          .update({
        'activeConversationId': widget.conversationId,
        'activeConversationLastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // best-effort; user logged out or doc gone — ignore
    }
  }

  void _clearActiveChat() {
    _activeChatHeartbeat?.cancel();
    _activeChatHeartbeat = null;
    FirebaseFirestore.instance
        .collection('users')
        .doc(widget.currentUserId)
        .update({
      'activeConversationId': FieldValue.delete(),
      'activeConversationLastSeen': FieldValue.delete(),
    }).catchError((_) {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _markActiveChat();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _clearActiveChat();
    }
  }

  /// Load salon data for working-hours check (client side only).
  Future<void> _loadSalon() async {
    final salonId = _salonIdFromConv(widget.conversationId);
    final salon = await DatabaseService().getSalon(salonId);
    if (mounted && salon != null) {
      setState(() => _salon = salon);
    }
  }

  String _salonIdFromConv(String convId) {
    final parts = convId.split('_');
    return parts.length > 1 ? parts.sublist(1).join('_') : convId;
  }

  /// Check if the salon is currently open based on workingHours.
  bool _isSalonOpen() {
    if (_salon == null) return true; // assume open if unknown
    final now = DateTime.now();
    const dayKeys = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
    final dayKey = dayKeys[now.weekday - 1];
    final dayData = _salon!.workingHours[dayKey];
    if (dayData == null) return false;
    if (dayData is Map) {
      if (dayData['isClosed'] == true) return false;
      final open = dayData['open'] as String?;
      final close = dayData['close'] as String?;
      if (open == null || close == null) return false;
      final openParts = open.split(':');
      final closeParts = close.split(':');
      final openMinutes = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
      final closeMinutes = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
      final nowMinutes = now.hour * 60 + now.minute;
      return nowMinutes >= openMinutes && nowMinutes <= closeMinutes;
    }
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clearActiveChat();
    if (NotificationService.activeConversationId == widget.conversationId) {
      NotificationService.activeConversationId = null;
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send({String? overrideText}) async {
    final text = (overrideText ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    if (overrideText == null) _controller.clear();
    try {
      await _svc.sendMessage(
        convId: widget.conversationId,
        senderId: widget.currentUserId,
        text: text,
        senderIsClient: widget.isClient,
      );

      // If client sends outside working hours → auto-reply
      if (widget.isClient && !_isSalonOpen()) {
        final salonId = _salonIdFromConv(widget.conversationId);
        await _svc.sendOutsideHoursReply(
          convId: widget.conversationId,
          salonId: salonId,
        );
      }

      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text((AppLocalizations.of(context)?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.brand950, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.otherPartyName,
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 17,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Messages list
          Expanded(
            child: StreamBuilder<List<MessageModel>>(
              stream: _svc.getMessages(widget.conversationId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(
                        color: AppColors.brand600),
                  );
                }

                final messages = snap.data ?? [];

                if (messages.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 48, color: AppColors.secondary200),
                        const SizedBox(height: 12),
                        Text(
                          l?.tr('chat_start_conversation') ?? 'Démarrez la conversation',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            color: AppColors.secondary400,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          l?.tr('chat_start_hint') ?? 'Envoyez un message pour commencer.',
                          style: TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary300),
                        ),
                      ],
                    ),
                  );
                }

                // Auto-scroll when new messages arrive
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.animateTo(
                      _scrollController.position.maxScrollExtent,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  }
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  itemCount: messages.length,
                  itemBuilder: (context, i) {
                    final msg = messages[i];
                    final isMine = msg.senderId == widget.currentUserId;
                    final showDate = i == 0 ||
                        !_sameDay(
                            messages[i - 1].sentAt, msg.sentAt);

                    return Column(
                      children: [
                        if (showDate) _DateDivider(date: msg.sentAt),
                        _MessageBubble(
                          message: msg,
                          isMine: isMine,
                          conversationId: widget.conversationId,
                          isClient: widget.isClient,
                          currencyCode: _salon?.currency ?? 'MAD',
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // Quick replies for owner
          if (!widget.isClient)
            _QuickReplyBar(
              replies: _getQuickReplies(l),
              onTap: (text) => _send(overrideText: text),
            ),

          // Input bar
          _InputBar(
            controller: _controller,
            sending: _sending,
            onSend: _send,
            hintText: l?.tr('chat_input_hint') ?? 'Écrivez un message…',
          ),
        ],
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Date divider ──────────────────────────────────────────────────────────────

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final label = isToday
        ? (l?.tr('chat_today') ?? "Aujourd'hui")
        : DateFormat('d MMMM yyyy', 'fr_FR').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(child: Divider(color: AppColors.secondary200)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary400,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const Expanded(child: Divider(color: AppColors.secondary200)),
        ],
      ),
    );
  }
}

// ── Message bubble ────────────────────────────────────────────────────────────

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    required this.conversationId,
    required this.isClient,
    this.currencyCode = 'MAD',
  });
  final MessageModel message;
  final bool isMine;
  final String conversationId;
  final bool isClient;
  final String currencyCode;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  MessageModel get message => widget.message;
  bool get isMine => widget.isMine;
  bool get _isBot => message.senderId.startsWith('bot_');
  String? _localStatus;

  String get _status => _localStatus ?? message.customRequestStatus ?? 'pending';

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final timeStr = DateFormat('HH:mm').format(message.sentAt);

    if (_isBot) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 24),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.brand100),
        ),
        child: Column(
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_toy_outlined, size: 14, color: AppColors.brand600),
                const SizedBox(width: 6),
                Text(l?.tr('chat_auto_reply') ?? 'Réponse automatique',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.brand600)),
              ],
            ),
            const SizedBox(height: 8),
            Text(message.text, textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: AppColors.brand950, height: 1.5)),
            const SizedBox(height: 6),
            Text(timeStr, style: const TextStyle(fontSize: 10, color: AppColors.secondary400)),
          ],
        ),
      );
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        child: Container(
          margin: EdgeInsets.only(top: 3, bottom: 3, left: isMine ? 48 : 0, right: isMine ? 0 : 48),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: isMine ? AppColors.brand700 : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16), topRight: const Radius.circular(16),
              bottomLeft: isMine ? const Radius.circular(16) : const Radius.circular(4),
              bottomRight: isMine ? const Radius.circular(4) : const Radius.circular(16),
            ),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              // Image
              if (message.imageUrl != null && message.imageUrl!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.network(message.imageUrl!, width: 200, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(width: 200, height: 100, color: AppColors.secondary100,
                      child: const Icon(Icons.broken_image_outlined, color: AppColors.secondary300))),
                ),
                const SizedBox(height: 6),
              ],
              // Custom request badge
              if (message.type == 'custom_request') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isMine ? Colors.white.withValues(alpha: 0.15) : AppColors.brand50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.brush_outlined, size: 12, color: isMine ? Colors.white70 : AppColors.brand600),
                      const SizedBox(width: 4),
                      Text(l?.tr('chat_custom_request') ?? 'Demande personnalisée',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                          color: isMine ? Colors.white70 : AppColors.brand600)),
                    ],
                  ),
                ),
                if (message.clientPhone != null && message.clientPhone!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phone_outlined, size: 12, color: isMine ? Colors.white70 : AppColors.brand600),
                    const SizedBox(width: 4),
                    Text('📞 ${message.clientPhone!}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                        color: isMine ? Colors.white70 : AppColors.brand600)),
                  ]),
                ],
                const SizedBox(height: 6),
              ],
              // Custom request status (if already responded)
              if (message.type == 'custom_request' && _status != 'pending') ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 6),
                  decoration: BoxDecoration(
                    color: _status == 'approved' ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(_status == 'approved' ? Icons.check_circle : Icons.cancel, size: 14,
                          color: _status == 'approved' ? const Color(0xFF16A34A) : const Color(0xFFDC2626)),
                        const SizedBox(width: 4),
                        Text(_status == 'approved' ? (l?.tr('chat_request_approved') ?? 'Accepté') : (l?.tr('chat_request_rejected') ?? 'Refusé'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                            color: _status == 'approved' ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                      ]),
                      if (message.proposedPrice != null) ...[
                        const SizedBox(height: 4),
                        Text('${CurrencyHelper.format(message.proposedPrice!, widget.currencyCode)} · ${message.proposedDuration ?? 30} min',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.brand950)),
                      ],
                    ],
                  ),
                ),
              ],
              // Text
              if (message.text.isNotEmpty)
                Text(message.text, style: TextStyle(fontSize: 14, color: isMine ? Colors.white : AppColors.brand950, height: 1.4)),
              const SizedBox(height: 4),
              Text(timeStr, style: TextStyle(fontSize: 10, color: isMine ? Colors.white.withValues(alpha: 0.7) : AppColors.secondary400)),

              // Accept/Reject buttons for owner on pending custom requests
              if (message.type == 'custom_request' && _status == 'pending' && !widget.isClient) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 32,
                      child: ElevatedButton.icon(
                        onPressed: () => _showApproveDialog(l),
                        icon: const Icon(Icons.check, size: 14),
                        label: Text(l?.tr('chat_accept') ?? 'Accepter', style: const TextStyle(fontSize: 12)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A), foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      height: 32,
                      child: OutlinedButton(
                        onPressed: () => _rejectRequest(l),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFDC2626),
                          side: const BorderSide(color: Color(0xFFDC2626)),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(l?.tr('chat_reject') ?? 'Refuser', style: const TextStyle(fontSize: 12)),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _showApproveDialog(AppLocalizations? l) async {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final durationCtrl = TextEditingController(text: '30');

    // Load team members for assignment
    final parts = widget.conversationId.split('_');
    List<TeamMemberModel> teamMembers = [];
    if (parts.length >= 2) {
      final salonId = parts.sublist(1).join('_');
      final snap = await FirebaseFirestore.instance
          .collection('salons').doc(salonId).collection('teamMembers')
          .where('isActive', isEqualTo: true).get();
      teamMembers = snap.docs.map((d) => TeamMemberModel.fromFirestore(d)).toList();
    }

    TeamMemberModel? selectedMember;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l?.tr('chat_approve_title') ?? 'Créer la prestation'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: l?.tr('chat_approve_name') ?? 'Nom de la prestation',
                    hintText: l?.tr('chat_approve_name_hint') ?? 'Ex: Coupe dégradé personnalisée',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l?.tr('chat_approve_price') ?? 'Prix (${widget.currencyCode})',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: durationCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l?.tr('chat_approve_duration') ?? 'Durée (min)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                if (teamMembers.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      l?.tr('chat_approve_assign') ?? 'Assigner à',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.secondary600),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: teamMembers.map((m) {
                      final isSelected = selectedMember?.id == m.id;
                      return GestureDetector(
                        onTap: () => setDialogState(() {
                          selectedMember = isSelected ? null : m;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected ? AppColors.brand50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isSelected ? AppColors.brand500 : AppColors.secondary200,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              MemberAvatar(name: m.name, photoUrl: m.photoUrl, radius: 14),
                              const SizedBox(width: 8),
                              Text(m.name, style: TextStyle(
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                                color: isSelected ? AppColors.brand700 : AppColors.brand950,
                              )),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l?.tr('common_cancel') ?? 'Annuler')),
            ElevatedButton(
              onPressed: () async {
                final name = nameCtrl.text.trim();
                final price = double.tryParse(priceCtrl.text.trim());
                final duration = int.tryParse(durationCtrl.text.trim()) ?? 30;
                if (price == null || price <= 0) return;

                Navigator.pop(ctx);
                await _approveRequest(name.isEmpty ? null : name, price, duration, assignedMember: selectedMember);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand600),
              child: Text(l?.tr('chat_approve_confirm') ?? 'Confirmer', style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveRequest(String? customName, double price, int duration, {TeamMemberModel? assignedMember}) async {
    await MessageService().updateCustomRequest(
      convId: widget.conversationId,
      messageId: message.id,
      status: 'approved',
      proposedPrice: price,
      proposedDuration: duration,
    );

    final parts = widget.conversationId.split('_');
    if (parts.length >= 2) {
      final clientId = parts[0];
      final salonId = parts.sublist(1).join('_');

      final salonDoc = await FirebaseFirestore.instance.collection('salons').doc(salonId).get();
      if (salonDoc.exists) {
        final salonName = salonDoc.data()?['name'] ?? 'Salon';
        final serviceName = customName ?? (message.text.isNotEmpty ? message.text : 'Prestation personnalisée');

        // Create personalized service visible only to this client
        final services = List<Map<String, dynamic>>.from(salonDoc.data()?['services'] ?? []);
        services.add({
          'name': serviceName,
          'category': 'Personnalisé',
          'price': price,
          'duration': duration,
          'description': '',
          'visibleTo': [clientId],
          if (message.imageUrl != null) 'imageUrl': message.imageUrl,
          if (assignedMember != null) 'assignedMembers': [assignedMember.name],
        });
        await FirebaseFirestore.instance.collection('salons').doc(salonId).update({'services': services});

        // Send in-app notification to the client.
        // pushSent: false so the onNewNotification Cloud Function sends a FCM push
        // to the client device (we want a real push here since the client isn't active).
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': clientId,
          'title': 'Demande acceptée ✅',
          'body': '$salonName a accepté votre demande "$serviceName" — ${CurrencyHelper.format(price, widget.currencyCode)}, $duration min. Vous pouvez maintenant réserver !',
          'type': 'custom_request_approved',
          'salonId': salonId,
          'createdAt': FieldValue.serverTimestamp(),
          'isRead': false,
          'pushSent': false,
        });
      }
    }

    if (mounted) setState(() => _localStatus = 'approved');
  }

  Future<void> _rejectRequest(AppLocalizations? l) async {
    await MessageService().updateCustomRequest(
      convId: widget.conversationId,
      messageId: message.id,
      status: 'rejected',
    );
    if (mounted) setState(() => _localStatus = 'rejected');
  }
}

// ── Quick reply bar (owner only) ──────────────────────────────────────────────

class _QuickReplyBar extends StatelessWidget {
  const _QuickReplyBar({required this.replies, required this.onTap});
  final List<Map<String, String>> replies;
  final void Function(String text) onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: replies.map((r) {
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => onTap(r['text']!),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: AppColors.brand200),
                  ),
                  child: Text(
                    r['label']!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand600,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

// ── Input bar ─────────────────────────────────────────────────────────────────

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.hintText,
  });
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 4,
              minLines: 1,
              textCapitalization: TextCapitalization.sentences,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.secondary800),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                    color: AppColors.secondary400, fontSize: 14),
                filled: true,
                fillColor: AppColors.secondary50,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide:
                      const BorderSide(color: AppColors.secondary200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(
                      color: AppColors.brand400, width: 1.5),
                ),
              ),
              onSubmitted: (_) => onSend(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: sending ? null : onSend,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: sending
                    ? AppColors.secondary200
                    : AppColors.brand700,
                shape: BoxShape.circle,
              ),
              child: sending
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
    );
  }
}
