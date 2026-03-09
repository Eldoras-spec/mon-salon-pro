import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../services/database_service.dart';
import '../services/auth_service.dart';
import '../models/notification_model.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

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
    final uid = _auth.currentUserId;
    if (uid != null) {
      _db.markAllNotificationsRead(uid);
    }
  }

  String _formatTime(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'À l\'instant';
    if (diff.inMinutes < 60) return 'Il y a ${diff.inMinutes}min';
    if (diff.inHours < 24) return 'Il y a ${diff.inHours}h';
    if (diff.inDays == 1) return 'Hier';
    if (diff.inDays < 7) return 'Il y a ${diff.inDays}j';
    return '${date.day}/${date.month}/${date.year}';
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
    final uid = _auth.currentUserId;

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        title: Text(
          'Notifications',
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
          ? const Center(child: Text('Non connecté'))
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
                          'Aucune notification',
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
                    return GestureDetector(
                      onTap: () => _db.markNotificationRead(n.id),
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
                                        _formatTime(n.createdAt),
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
