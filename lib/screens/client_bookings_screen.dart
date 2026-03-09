import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../providers/auth_providers.dart';
import '../services/database_service.dart';

// ── Filter ───────────────────────────────────────────────────────────────────

enum _Tab { upcoming, completed, cancelled }

extension _TabLabel on _Tab {
  String get label => switch (this) {
        _Tab.upcoming => 'À venir',
        _Tab.completed => 'Terminés',
        _Tab.cancelled => 'Annulés',
      };
  String get status => switch (this) {
        _Tab.upcoming => 'upcoming',
        _Tab.completed => 'completed',
        _Tab.cancelled => 'cancelled',
      };
}

// ── Screen ───────────────────────────────────────────────────────────────────

class ClientBookingsScreen extends ConsumerStatefulWidget {
  const ClientBookingsScreen({super.key});

  @override
  ConsumerState<ClientBookingsScreen> createState() =>
      _ClientBookingsScreenState();
}

class _ClientBookingsScreenState
    extends ConsumerState<ClientBookingsScreen> {
  _Tab _selected = _Tab.upcoming;

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(userModelProvider);
    final uid = userAsync.value?.id;

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        slivers: [
          // ── App bar ──────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            title: Text(
              'Mes réservations',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: _TabBar(
                selected: _selected,
                onSelect: (t) => setState(() => _selected = t),
              ),
            ),
          ),

          // ── Content ──────────────────────────────────────────────────────
          if (uid == null)
            const SliverFillRemaining(
              child: Center(
                  child: Text('Connectez-vous pour voir vos réservations.')),
            )
          else
            _BookingsList(uid: uid, tab: _selected),
        ],
      ),
    );
  }
}

// ── Tab bar ──────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({required this.selected, required this.onSelect});
  final _Tab selected;
  final ValueChanged<_Tab> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: _Tab.values.map((t) {
          final active = t == selected;
          return GestureDetector(
            onTap: () => onSelect(t),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: active ? AppColors.brand600 : AppColors.secondary100,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                t.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active ? Colors.white : AppColors.secondary500,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Bookings list ────────────────────────────────────────────────────────────

class _BookingsList extends StatelessWidget {
  const _BookingsList({required this.uid, required this.tab});
  final String uid;
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AppointmentModel>>(
      stream:
          DatabaseService().getClientAppointments(uid, status: tab.status),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(
                child:
                    CircularProgressIndicator(color: AppColors.brand600)),
          );
        }
        final items = snap.data ?? [];
        if (items.isEmpty) {
          return SliverFillRemaining(
            child: _EmptyState(tab: tab),
          );
        }
        return SliverPadding(
          padding: const EdgeInsets.only(bottom: 24),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => _BookingCard(appointment: items[i]),
              childCount: items.length,
            ),
          ),
        );
      },
    );
  }
}

// ── Booking card ─────────────────────────────────────────────────────────────

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.appointment});
  final AppointmentModel appointment;

  static bool _isToday(DateTime dt) {
    final n = DateTime.now();
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  Future<void> _cancel(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text(
          'Annuler ce rendez-vous ?',
          style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              fontSize: 16),
        ),
        content: Text(
          '${appointment.serviceName} chez ${appointment.salonName}',
          style: const TextStyle(
              color: AppColors.secondary500, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non',
                style: TextStyle(color: AppColors.secondary400)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Annuler',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await DatabaseService()
          .updateAppointmentStatus(appointment.id, 'cancelled');
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = appointment;
    final today = _isToday(a.dateTime);
    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr =
        DateFormat('EEE d MMM yyyy', 'fr_FR').format(a.dateTime);

    final (statusLabel, statusBg, statusFg) = switch (a.status) {
      'completed' => (
          'Terminé',
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A)
        ),
      'cancelled' => (
          'Annulé',
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626)
        ),
      _ => ('À venir', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: today
            ? Border.all(color: AppColors.brand200, width: 1.5)
            : Border.all(color: AppColors.secondary100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar (brand for today, grey for others)
              Container(
                width: 4,
                color: today ? AppColors.brand500 : AppColors.secondary100,
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header: date + status
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              today ? "Aujourd'hui · $timeStr" : '$dateStr · $timeStr',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: today
                                    ? AppColors.brand700
                                    : AppColors.secondary500,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: statusBg,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              statusLabel,
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: statusFg),
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 10),

                      // Service name
                      Text(
                        a.serviceName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),

                      const SizedBox(height: 4),

                      // Salon name + price
                      Row(
                        children: [
                          const Icon(Icons.storefront_outlined,
                              size: 13, color: AppColors.brand400),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              a.salonName,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary500),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${a.price.toStringAsFixed(0)} MAD',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brand700,
                            ),
                          ),
                        ],
                      ),

                      // Cancel button (upcoming only)
                      if (a.status == 'upcoming') ...[
                        const SizedBox(height: 12),
                        const Divider(height: 1),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: OutlinedButton(
                            onPressed: () => _cancel(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFDC2626),
                              side: const BorderSide(
                                  color: Color(0xFFFECACA)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text(
                              'Annuler ce rendez-vous',
                              style: TextStyle(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.tab});
  final _Tab tab;

  @override
  Widget build(BuildContext context) {
    final (icon, msg) = switch (tab) {
      _Tab.upcoming => (
          Icons.event_available_outlined,
          'Aucun rendez-vous à venir'
        ),
      _Tab.completed => (
          Icons.check_circle_outline_rounded,
          'Aucun rendez-vous terminé'
        ),
      _Tab.cancelled => (Icons.cancel_outlined, 'Aucun rendez-vous annulé'),
    };

    final sub = switch (tab) {
      _Tab.upcoming => 'Réservez un salon depuis la page d\'accueil.',
      _Tab.completed => 'Vos rendez-vous terminés apparaîtront ici.',
      _Tab.cancelled => 'Vos annulations seront listées ici.',
    };

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: const BoxDecoration(
                color: AppColors.brand50,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: AppColors.brand200),
            ),
            const SizedBox(height: 20),
            Text(msg,
                style: const TextStyle(
                    color: AppColors.brand950,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              sub,
              style: const TextStyle(color: AppColors.secondary400, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
