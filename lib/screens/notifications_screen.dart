import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/notification_model.dart';
import '../services/app_localizations.dart';

class NotificationsScreen extends StatefulWidget {
  /// Optional explicit notifications owner. When null, falls back to the
  /// signed-in Firebase uid. The member view passes the synthetic key
  /// `emp_${salonId}_${memberId}` so a member in profile-selector mode
  /// (sharing the owner's Firebase session) still sees THEIR own notifs,
  /// not the owner's.
  const NotificationsScreen({super.key, this.userId});

  final String? userId;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  final _db = DatabaseService();
  final _auth = AuthService();

  @override
  void initState() {
    super.initState();
    // Mark all as read when screen opens
    final uid = widget.userId ?? _auth.currentUserId;
    if (uid != null) {
      _db.markAllNotificationsRead(uid);
    }
  }

  String _formatTime(DateTime date, AppLocalizations? l) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return l?.tr('notifications_just_now') ?? 'À l\'instant';
    if (diff.inMinutes < 60) return (l?.tr('notifications_minutes_ago') ?? 'Il y a {min}min').replaceAll('{min}', '${diff.inMinutes}');
    if (diff.inHours < 24) return (l?.tr('notifications_hours_ago') ?? 'Il y a {hours}h').replaceAll('{hours}', '${diff.inHours}');
    if (diff.inDays == 1) return l?.tr('notifications_yesterday') ?? 'Hier';
    if (diff.inDays < 7) return (l?.tr('notifications_days_ago') ?? 'Il y a {days}j').replaceAll('{days}', '${diff.inDays}');
    return '${date.day}/${date.month}/${date.year}';
  }

  /// Open the WhatsApp chat with the client behind a handover notification.
  /// Falls back to a snackbar (showing the number to copy) when no app can
  /// open the link — e.g. an emulator without WhatsApp or a browser.
  Future<void> _openClientWhatsApp(String phone) async {
    final l = AppLocalizations.of(context);
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return;
    final uri = Uri.parse('https://wa.me/$digits');
    bool launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text((l?.tr('notif_handover_no_wa') ??
                'WhatsApp indisponible sur cet appareil. Numéro du client : {phone}')
            .replaceAll('{phone}', '+$digits')),
      ));
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'appointment':
        return Icons.calendar_today_rounded;
      case 'payment':
        return Icons.receipt_rounded;
      case 'promotion':
        return Icons.local_offer_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _colorForType(String type, bool isRead) {
    if (isRead) return AppColors.secondary400;
    switch (type) {
      case 'appointment':
        return AppColors.brand600;
      case 'payment':
        return const Color(0xFF22C55E);
      case 'promotion':
        return const Color(0xFFF59E0B);
      default:
        return AppColors.brand600;
    }
  }

  Color _bgForType(String type, bool isRead) {
    if (isRead) return AppColors.secondary100;
    switch (type) {
      case 'appointment':
        return AppColors.brand50;
      case 'payment':
        return const Color(0xFFF0FDF4);
      case 'promotion':
        return const Color(0xFFFFFBEB);
      default:
        return AppColors.brand50;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final uid = widget.userId ?? _auth.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        title: Text(
          l?.tr('notifications_title') ?? 'Notifications',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand950),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: uid == null
          ? Center(child: Text(l?.tr('notifications_not_connected') ?? 'Non connecté'))
          : StreamBuilder<List<NotificationModel>>(
              stream: _db.getNotifications(uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.brand500),
                  );
                }

                final notifications = snapshot.data ?? [];

                if (notifications.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.notifications_off_outlined,
                          size: 64,
                          color: AppColors.secondary300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l?.tr('notifications_empty') ?? 'Aucune notification',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.secondary500,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: notifications.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final n = notifications[index];
                    final isHandover = n.type == 'bot_handover' &&
                        (n.clientPhone?.trim().isNotEmpty ?? false);
                    return GestureDetector(
                      onTap: () {
                        _db.markNotificationRead(n.id);
                        // A handover means a client is waiting — tapping opens
                        // the WhatsApp chat with them directly.
                        if (isHandover) _openClientWhatsApp(n.clientPhone!);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: n.isRead
                                ? Colors.transparent
                                : AppColors.brand200,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(9),
                              decoration: BoxDecoration(
                                color: _bgForType(n.type, n.isRead),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _iconForType(n.type),
                                color: _colorForType(n.type, n.isRead),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          n.title,
                                          style: GoogleFonts.plusJakartaSans(
                                            fontWeight: n.isRead
                                                ? FontWeight.w500
                                                : FontWeight.bold,
                                            fontSize: 14,
                                            color: AppColors.secondary900,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        _formatTime(n.createdAt, l),
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 11,
                                          color: AppColors.secondary400,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    n.body,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: AppColors.secondary600,
                                    ),
                                  ),
                                  if (isHandover) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF25D366)
                                            .withValues(alpha: 0.10),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.chat_rounded,
                                              size: 14, color: Color(0xFF128C7E)),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              '${l?.tr('notif_handover_reply') ?? 'Répondre sur WhatsApp'}'
                                              '${(n.clientName?.trim().isNotEmpty ?? false) ? ' · ${n.clientName}' : ''}'
                                              ' · ${n.clientPhone}',
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                                color: const Color(0xFF128C7E),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            if (!n.isRead) ...[
                              const SizedBox(width: 8),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: AppColors.brand500,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
