import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import 'conversations_screen.dart';

class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  static bool _isOpen(Map<String, dynamic> hours) {
    const dayNames = [
      'lundi', 'mardi', 'mercredi', 'jeudi',
      'vendredi', 'samedi', 'dimanche',
    ];
    final now = DateTime.now();
    final dayData = hours[dayNames[now.weekday - 1]] as Map<String, dynamic>?;
    if (dayData == null || dayData['isOpen'] != true) return false;
    try {
      final op = (dayData['open'] as String).split(':');
      final cl = (dayData['close'] as String).split(':');
      final nowMin = now.hour * 60 + now.minute;
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      return nowMin >= openMin && nowMin < closeMin;
    } catch (_) {
      return false;
    }
  }

  static bool _isToday(DateTime dt) {
    final n = DateTime.now();
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userModelProvider);
    final salonAsync = ref.watch(ownerSalonProvider);
    final appointmentsAsync = ref.watch(ownerAppointmentsProvider);
    final activeMember = ref.watch(activeTeamMemberProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: userAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text('Erreur : $e')),
        data: (user) {
          final userName = activeMember?.name ?? user?.fullName ?? 'Propriétaire';
          final salon = salonAsync.value;
          final appointments = appointmentsAsync.value ?? [];

          final todayUpcoming = appointments
              .where((a) => _isToday(a.dateTime) && a.status == 'upcoming')
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

          final totalRevenue = appointments
              .where((a) => a.status == 'completed')
              .fold<double>(0, (s, a) => s + a.price);

          final completedCount =
              appointments.where((a) => a.status == 'completed').length;

          final recentAll = appointments.take(5).toList();

          // Weekly stats
          final now = DateTime.now();
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          final weekDayCounts = List.filled(7, 0);
          final weekDayRevenue = List.filled(7, 0.0);
          for (final a in appointments) {
            final diff = a.dateTime
                .difference(DateTime(
                    weekStart.year, weekStart.month, weekStart.day))
                .inDays;
            if (diff >= 0 && diff < 7) {
              weekDayCounts[diff]++;
              if (a.status == 'completed') weekDayRevenue[diff] += a.price;
            }
          }
          final weekRevenue =
              weekDayRevenue.fold<double>(0, (s, v) => s + v);
          final weekTotal =
              weekDayCounts.fold<int>(0, (s, v) => s + v);

          return RefreshIndicator(
            color: AppColors.brand600,
            onRefresh: () async {
              ref.invalidate(ownerSalonProvider);
              ref.invalidate(ownerAppointmentsProvider);
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: CustomScrollView(
              slivers: [
                // ── Gradient header ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF831843), // brand900
                          Color(0xFFBE185D), // brand700
                          Color(0xFFDB2777), // brand600
                        ],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top row: title + actions
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Bonjour,',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        userName,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Profile switch
                                GestureDetector(
                                  onTap: () {
                                    ref
                                        .read(activeTeamMemberProvider.notifier)
                                        .state = null;
                                    ref
                                        .read(profileSelectedProvider.notifier)
                                        .state = false;
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.swap_horiz_rounded,
                                        size: 20,
                                        color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Security & Account
                                GestureDetector(
                                  onTap: () {
                                    final email = userAsync.value?.email ?? '';
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.white,
                                      shape: const RoundedRectangleBorder(
                                        borderRadius: BorderRadius.vertical(
                                            top: Radius.circular(20)),
                                      ),
                                      builder: (_) => _OwnerSecuritySheet(
                                        userEmail: email,
                                        onAccountDeleted: () {
                                          ref.read(authServiceProvider).signOut();
                                          ref.invalidate(authStateProvider);
                                          ref.invalidate(userModelProvider);
                                        },
                                      ),
                                    );
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.settings_outlined,
                                        size: 18,
                                        color: Colors.white),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Logout
                                GestureDetector(
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        title: const Text('Déconnexion'),
                                        content: const Text(
                                            'Êtes-vous sûr de vouloir vous déconnecter ?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: const Text('Annuler'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: const Text('Déconnecter',
                                                style: TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    await ref
                                        .read(authServiceProvider)
                                        .signOut();
                                    ref.invalidate(authStateProvider);
                                    ref.invalidate(userModelProvider);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.power_settings_new_rounded,
                                        size: 18,
                                        color: Colors.white),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            Text(
                              DateFormat("EEEE d MMMM yyyy", 'fr_FR')
                                  .format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Quick stats row ────────────────────────────
                            Row(
                              children: [
                                _GlassStat(
                                  value: appointmentsAsync.isLoading
                                      ? '…'
                                      : '${todayUpcoming.length}',
                                  label: "Aujourd'hui",
                                  icon: Icons.calendar_today_rounded,
                                ),
                                const SizedBox(width: 10),
                                _GlassStat(
                                  value: appointmentsAsync.isLoading
                                      ? '…'
                                      : '$completedCount',
                                  label: 'Terminés',
                                  icon: Icons.check_circle_outline_rounded,
                                ),
                                const SizedBox(width: 10),
                                _GlassStat(
                                  value: salon?.rating != null
                                      ? salon!.rating.toStringAsFixed(1)
                                      : '—',
                                  label: 'Note',
                                  icon: Icons.star_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Body ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),

                      // Revenue + salon card
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _RevenueCard(
                          totalRevenue: totalRevenue,
                          salon: salon,
                          loading: appointmentsAsync.isLoading,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Salon web link ─────────────────────────────────
                      if (salon != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SalonLinkCard(salon: salon),
                        ),
                      if (salon != null) const SizedBox(height: 16),

                      // ── Weekly chart ─────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _WeeklyChart(
                          dayCounts: weekDayCounts,
                          weekTotal: weekTotal,
                          weekRevenue: weekRevenue,
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── AI Summary (hidden for new salons with no appointments) ──
                      if (salon != null && appointments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _AISummaryCard(salonId: salon.id),
                        ),
                      if (salon != null && appointments.isNotEmpty) const SizedBox(height: 20),

                      // ── Messages ─────────────────────────────────────────
                      if (salon != null && user != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _MessagesWidget(
                            salonId: salon.id,
                            ownerId: user.id,
                          ),
                        ),
                      if (salon != null && user != null)
                        const SizedBox(height: 20),

                      // ── Today's appointments ────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SectionHeader(
                          title: "Rendez-vous d'aujourd'hui",
                          count: todayUpcoming.length,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (appointmentsAsync.isLoading)
                        const _LoadingCard()
                      else if (todayUpcoming.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyCard(
                            icon: Icons.calendar_today_outlined,
                            message:
                                "Aucun rendez-vous prévu aujourd'hui",
                          ),
                        )
                      else
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                children: todayUpcoming
                                    .map((a) => _AppointmentCard(
                                        appointment: a,
                                        showDate: false))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // ── Recent appointments ─────────────────────────────
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child:
                            _SectionHeader(title: 'Rendez-vous récents'),
                      ),
                      const SizedBox(height: 12),
                      if (appointmentsAsync.isLoading)
                        const _LoadingCard()
                      else if (recentAll.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyCard(
                            icon: Icons.history_rounded,
                            message:
                                "Aucun rendez-vous pour l'instant",
                          ),
                        )
                      else
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                children: recentAll
                                    .map((a) => _AppointmentCard(
                                        appointment: a,
                                        showDate: true))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Salon web link card ──────────────────────────────────────────────────────

class _SalonLinkCard extends StatefulWidget {
  const _SalonLinkCard({required this.salon});
  final SalonModel salon;

  @override
  State<_SalonLinkCard> createState() => _SalonLinkCardState();
}

class _SalonLinkCardState extends State<_SalonLinkCard> {
  String? _generatedSlug;

  SalonModel get salon => widget.salon;

  String get _salonUrl {
    final slug = _generatedSlug ?? salon.slug;
    if (slug != null && slug.isNotEmpty) {
      return 'https://monsalon.web.app/s/$slug';
    }
    return 'https://monsalon.web.app/salon.html?id=${salon.id}';
  }

  @override
  void initState() {
    super.initState();
    if (salon.slug == null || salon.slug!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSlug());
    }
  }

  Future<void> _ensureSlug() async {
    try {
      final slug = await DatabaseService().ensureSalonSlug(
        salon.id,
        salon.name,
        salon.city,
      );
      if (mounted) setState(() => _generatedSlug = slug);
    } catch (e) {
      debugPrint('[SalonLink] ERROR generating slug: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.link_rounded, color: AppColors.brand600, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Lien de votre salon',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _salonUrl,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _salonUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Lien copie ! Collez-le dans votre bio Instagram.'),
                  backgroundColor: AppColors.brand600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brand600,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'Copier',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass stat (header) ──────────────────────────────────────────────────────

class _GlassStat extends StatelessWidget {
  const _GlassStat({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Revenue card ─────────────────────────────────────────────────────────────

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.totalRevenue,
    required this.salon,
    required this.loading,
  });
  final double totalRevenue;
  final SalonModel? salon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final revenueStr = totalRevenue >= 1000
        ? '${(totalRevenue / 1000).toStringAsFixed(1)}k MAD'
        : '${totalRevenue.toStringAsFixed(0)} MAD';

    final open =
        salon != null ? OwnerHomeScreen._isOpen(salon!.workingHours) : false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Revenue
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.trending_up_rounded,
                          size: 16, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Revenus totaux',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  loading ? '…' : revenueStr,
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ],
            ),
          ),

          // Salon status
          if (salon != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: salon!.logoUrl != null
                      ? Image.network(
                          salon!.logoUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: open
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: open
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        open ? 'Ouvert' : 'Fermé',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: open
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.storefront_outlined,
            color: AppColors.brand400, size: 20),
      );
}

// ── Weekly chart ─────────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({
    required this.dayCounts,
    required this.weekTotal,
    required this.weekRevenue,
  });

  final List<int> dayCounts;
  final int weekTotal;
  final double weekRevenue;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final maxCount = dayCounts.reduce((a, b) => a > b ? a : b);
    final todayIndex = DateTime.now().weekday - 1;

    final revenueStr = weekRevenue >= 1000
        ? '${(weekRevenue / 1000).toStringAsFixed(1)}k'
        : weekRevenue.toStringAsFixed(0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                'Cette semaine',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$weekTotal RDV',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$revenueStr MAD',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Bar chart
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final ratio =
                  maxCount > 0 ? dayCounts[i] / maxCount : 0.0;
              final isToday = i == todayIndex;
              final barHeight = 6.0 + (ratio * 70);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dayCounts[i] > 0)
                        Text(
                          '${dayCounts[i]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? AppColors.brand700
                                : AppColors.secondary400,
                          ),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: barHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: isToday
                              ? const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    AppColors.brand600,
                                    AppColors.brand400,
                                  ],
                                )
                              : null,
                          color: isToday
                              ? null
                              : (dayCounts[i] > 0
                                  ? AppColors.brand100
                                  : AppColors.secondary100),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppColors.brand600
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _dayLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isToday
                                  ? Colors.white
                                  : AppColors.secondary400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Appointment card ────────────────────────────────────────────────────────

class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.showDate,
  });
  final AppointmentModel appointment;
  final bool showDate;

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  String _clientName = '…';

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    if (a.clientId == 'walk-in') {
      _clientName = a.clientName ?? 'Client sans compte';
    } else {
      DatabaseService().getClientName(a.clientId).then((name) {
        if (mounted) setState(() => _clientName = name);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;

    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr = widget.showDate
        ? DateFormat('d MMM', 'fr_FR').format(a.dateTime)
        : null;

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Time badge
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: a.status == 'upcoming'
                  ? AppColors.brand50
                  : AppColors.secondary50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: a.status == 'upcoming'
                        ? AppColors.brand700
                        : AppColors.secondary500,
                  ),
                ),
                if (dateStr != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.secondary400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.serviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.brand950,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 12, color: AppColors.secondary400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _clientName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: price + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${a.price.toStringAsFixed(0)} MAD',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusFg,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brand600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Empty / Loading cards ───────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.secondary50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppColors.secondary300),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
                color: AppColors.secondary400, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
            color: AppColors.brand600, strokeWidth: 2),
      ),
    );
  }
}

// ── AI Summary card ──────────────────────────────────────────────────────────

class _AISummaryCard extends StatefulWidget {
  const _AISummaryCard({required this.salonId});
  final String salonId;

  @override
  State<_AISummaryCard> createState() => _AISummaryCardState();
}

class _AISummaryCardState extends State<_AISummaryCard> {
  String? _summary;
  bool _loading = false;
  bool _error = false;
  bool _expanded = false;
  static const int _maxChars = 120;

  @override
  void initState() {
    super.initState();
    _loadCachedOrFetch();
  }

  /// Load cached summary from Firestore. Only call Gemini if no cache for today.
  Future<void> _loadCachedOrFetch() async {
    setState(() { _loading = true; _error = false; });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .get();
      final data = doc.data();
      final cachedSummary = data?['aiSummary'] as String?;
      final cachedDate = data?['aiSummaryDate'] as String?;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      if (cachedSummary != null && cachedDate == today) {
        setState(() { _summary = cachedSummary; _loading = false; });
        return;
      }
      // No valid cache — fetch from Gemini
      await _fetchFromGemini();
    } catch (e) {
      // Fallback: try Gemini directly
      await _fetchFromGemini();
    }
  }

  Future<void> _fetchFromGemini() async {
    setState(() { _loading = true; _error = false; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateDailySummary',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      final result = await callable.call({'salonId': widget.salonId});
      final data = result.data as Map<String, dynamic>;
      final summary = data['summary'] as String?;
      setState(() { _summary = summary; _loading = false; });

      // Cache in Firestore
      if (summary != null) {
        final today = DateTime.now().toIso8601String().substring(0, 10);
        FirebaseFirestore.instance
            .collection('salons')
            .doc(widget.salonId)
            .update({'aiSummary': summary, 'aiSummaryDate': today});
      }
    } catch (e) {
      setState(() { _loading = false; _error = true; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFFDF2F8), // brand50
            Color(0xFFFFFFFF),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brand100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.auto_awesome,
                  size: 18,
                  color: AppColors.brand600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Résumé intelligent',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (!_loading)
                GestureDetector(
                  onTap: _loadCachedOrFetch,
                  child: Icon(
                    Icons.refresh_rounded,
                    size: 20,
                    color: AppColors.secondary400,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    color: AppColors.brand600,
                    strokeWidth: 2,
                  ),
                ),
              ),
            )
          else if (_error)
            GestureDetector(
              onTap: _fetchFromGemini,
              child: Text(
                'Impossible de générer le résumé. Appuie pour réessayer.',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: AppColors.secondary400,
                  height: 1.5,
                ),
              ),
            )
          else if (_summary != null) ...[
            Text(
              _expanded || _summary!.length <= _maxChars
                  ? _summary!
                  : '${_summary!.substring(0, _maxChars)}...',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13.5,
                color: AppColors.secondary600,
                height: 1.6,
              ),
            ),
            if (_summary!.length > _maxChars)
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    _expanded ? 'Voir moins' : 'Voir plus',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand600,
                    ),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// ── Messages widget ─────────────────────────────────────────────────────────

class _MessagesWidget extends StatelessWidget {
  const _MessagesWidget({required this.salonId, required this.ownerId});
  final String salonId;
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<dynamic>>(
      stream: MessageService().getOwnerConversations(salonId),
      builder: (context, snap) {
        final convs = (snap.data ?? []);
        final unread = convs.fold<int>(
          0,
          (acc, c) => acc + ((c.unreadByOwner ?? 0) as int),
        );
        final hasUnread = unread > 0;
        final preview = convs.isNotEmpty ? convs.first : null;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConversationsScreen(
                currentUserId: ownerId,
                isClient: false,
                salonId: salonId,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    hasUnread ? AppColors.brand200 : AppColors.secondary100,
                width: hasUnread ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasUnread
                        ? AppColors.brand50
                        : AppColors.secondary50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: hasUnread
                        ? AppColors.brand600
                        : AppColors.secondary400,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Messages',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview != null
                            ? (preview.lastMessage as String).isNotEmpty
                                ? '${preview.clientName} : ${preview.lastMessage}'
                                : '${convs.length} conversation${convs.length > 1 ? 's' : ''}'
                            : 'Aucun message pour l\'instant',
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
                    ],
                  ),
                ),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.secondary300, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Owner Security & Account Sheet ───────────────────────────────────────────

class _OwnerSecuritySheet extends StatefulWidget {
  const _OwnerSecuritySheet({
    required this.userEmail,
    required this.onAccountDeleted,
  });
  final String userEmail;
  final VoidCallback onAccountDeleted;

  @override
  State<_OwnerSecuritySheet> createState() => _OwnerSecuritySheetState();
}

class _OwnerSecuritySheetState extends State<_OwnerSecuritySheet> {
  bool _loading = false;
  bool _sent = false;
  bool _deleting = false;

  Future<void> _resetPassword() async {
    setState(() => _loading = true);
    try {
      await AuthService().sendPasswordResetEmail(widget.userEmail);
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer votre compte ?'),
        content: const Text(
          'Cette action est irréversible. Toutes vos données, '
          'votre salon, vos réservations et conversations seront '
          'définitivement supprimés.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Supprimer',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Êtes-vous vraiment sûr ?'),
        content: const Text(
          'Votre compte, votre salon et toutes vos données seront supprimés '
          'de façon permanente. Cette action ne peut pas être annulée.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Non, garder mon compte'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Oui, supprimer définitivement',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    setState(() => _deleting = true);
    try {
      await AuthService().deleteAccount();
      if (mounted) {
        Navigator.pop(context);
        widget.onAccountDeleted();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _deleting = false);
        String msg = 'Erreur lors de la suppression.';
        if (e.toString().contains('requires-recent-login')) {
          msg = 'Veuillez vous reconnecter puis réessayer la suppression.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text('Sécurité & Compte',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 20),

          // Reset password
          if (_sent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Un email de réinitialisation a été envoyé à ${widget.userEmail}',
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: AppColors.secondary500, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Un lien de réinitialisation sera envoyé à\n${widget.userEmail}',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.secondary600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Réinitialiser le mot de passe',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          ],

          // Delete account
          const SizedBox(height: 28),
          const Divider(height: 1),
          const SizedBox(height: 20),
          Text('Zone dangereuse',
              style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFFDC2626))),
          const SizedBox(height: 8),
          const Text(
            'La suppression de votre compte est définitive et irréversible.',
            style: TextStyle(fontSize: 12, color: AppColors.secondary500),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: _deleting ? null : _deleteAccount,
              icon: _deleting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          color: Color(0xFFDC2626), strokeWidth: 2))
                  : const Icon(Icons.delete_forever_rounded, size: 18),
              label: Text(_deleting
                  ? 'Suppression en cours...'
                  : 'Supprimer mon compte'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFFEE2E2), width: 1.5),
                backgroundColor: const Color(0xFFFFF5F5),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
