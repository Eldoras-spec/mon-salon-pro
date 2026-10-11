import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/plan_config.dart';
import '../services/database_service.dart';
import '../services/app_localizations.dart';
import '../utils/currency_helper.dart';
import '../utils/timezone_helper.dart';
import 'owner_appointments_screen.dart';
import 'owner_subscription_screen.dart';
import 'conversations_screen.dart';
import 'notifications_screen.dart';
import '../widgets/member_avatar.dart';
import '../widgets/owner_tasks_card.dart';
import '../widgets/owner_setup_card.dart';
import '../providers/owner_tasks_provider.dart';
import '../providers/setup_tasks_provider.dart';

class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  // Open/closed badge in the salon's own time zone, honouring holiday
  // closures (closedDates) — the device clock was used before.
  static bool _isOpen(SalonModel salon) {
    const dayNames = [
      'lundi', 'mardi', 'mercredi', 'jeudi',
      'vendredi', 'samedi', 'dimanche',
    ];
    final hours = salon.workingHours;
    final now = TimezoneHelper.salonNow(salon.timezone);
    if (salon.isClosedOnDate(now)) return false;
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

  // [dt] is wall-clock-UTC; compare with the salon's wall-clock "now".
  static bool _isToday(DateTime dt, String? tz) {
    final n = TimezoneHelper.salonWallClockNow(tz);
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userModelProvider);
    final salonAsync = ref.watch(ownerSalonProvider);
    // Bounded last-7d + next-7d window — covers today's RDV, current
    // week stats and the recent-5 widget without scanning lifetime
    // appointments (saves N reads per dashboard open).
    final appointmentsAsync = ref.watch(ownerHomeAppointmentsProvider);
    final activeMember = ref.watch(activeTeamMemberProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: userAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text((AppLocalizations.of(context)?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'))),
        data: (user) {
          final l = AppLocalizations.of(context);
          final userName = activeMember?.name ?? user?.fullName ?? (l?.tr('home_owner') ?? 'Propriétaire');
          final salon = salonAsync.value;
          final appointments = appointmentsAsync.value ?? [];

          final todayUpcoming = appointments
              .where((a) => _isToday(a.dateTime, salon?.timezone) && a.status == 'upcoming')
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

          // Current-month revenue + completed count come from dedicated
          // server-side providers (see ownerCurrentMonth* providers).

          // Weekly stats — wall-clock-UTC day buckets (Mon..Sun) in the salon
          // TZ. Day index from calendar dates, not `difference().inDays`,
          // which truncated toward zero and folded last Sunday into Monday.
          // Cancelled / no-show RDV are not activity.
          final now = TimezoneHelper.salonWallClockNow(salon?.timezone);
          final weekStart = DateTime.utc(now.year, now.month, now.day)
              .subtract(Duration(days: now.weekday - 1));
          final weekDayCounts = List.filled(7, 0);
          final weekDayRevenue = List.filled(7, 0.0);
          for (final a in appointments) {
            if (a.status == 'cancelled' || a.status == 'no_show') continue;
            final day = DateTime.utc(
                a.dateTime.year, a.dateTime.month, a.dateTime.day);
            final diff = day.difference(weekStart).inHours ~/ 24;
            if (!day.isBefore(weekStart) && diff < 7) {
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
              ref.invalidate(ownerHomeAppointmentsProvider);
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
                          AppColors.brand900,
                          AppColors.brand700,
                          AppColors.brand600,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(0),
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
                                // Avatar = profile switcher (shared device).
                                // A code-logged employee has no other
                                // profile: the avatar is just an avatar.
                                GestureDetector(
                                  onTap: ref.watch(employeeSessionProvider).value != null
                                      ? null
                                      : () {
                                          ref
                                              .read(activeTeamMemberProvider.notifier)
                                              .state = null;
                                          ref
                                              .read(profileSelectedProvider.notifier)
                                              .state = false;
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: Colors.white.withValues(alpha: 0.5),
                                          width: 1.5),
                                    ),
                                    child: MemberAvatar(
                                      name: userName,
                                      photoUrl: activeMember?.photoUrl ??
                                          user?.profileImageUrl,
                                      radius: 20,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l?.tr('home_hello') ?? 'Bonjour,',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        userName.length > 13
                                            ? '${userName.substring(0, 13)}…'
                                            : userName,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Security & Account
                                // Notifications bell with unread badge
                                GestureDetector(
                                  onTap: () {
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => const NotificationsScreen(),
                                    ));
                                  },
                                  child: Builder(
                                    builder: (context) {
                                      final unreadCount = ref
                                              .watch(unreadNotificationsCountProvider)
                                              .value ??
                                          0;
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                Icons.notifications_rounded,
                                                size: 18,
                                                color: Colors.white),
                                          ),
                                          if (unreadCount > 0)
                                            Positioned(
                                              top: -4, right: -4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                                child: Text(
                                                  '$unreadCount',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Messages shortcut with unread badge
                                if (ref.watch(employeeSessionProvider).value == null)
                                GestureDetector(
                                  onTap: () {
                                    // ConversationsScreen needs the salon id
                                    // (it force-unwraps it): ignore taps until
                                    // the salon is loaded instead of crashing.
                                    if (salon == null) return;
                                    final uid = ref.read(authStateProvider).value?.uid ?? '';
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => ConversationsScreen(
                                        currentUserId: uid,
                                        isClient: false,
                                        salonId: salon.id,
                                      ),
                                    ));
                                  },
                                  child: Builder(
                                    builder: (context) {
                                      final unreadCount = ref
                                              .watch(unreadMessagesCountProvider)
                                              .value ??
                                          0;
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                CupertinoIcons.chat_bubble_text_fill,
                                                size: 18,
                                                color: Colors.white),
                                          ),
                                          if (unreadCount > 0)
                                            Positioned(
                                              top: -4, right: -4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                                child: Text(
                                                  '$unreadCount',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            Text(
                              DateFormat("EEEE d MMMM yyyy", Localizations.localeOf(context).languageCode)
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
                                  label: l?.tr('home_today') ?? "Aujourd'hui",
                                  icon: Icons.calendar_today_rounded,
                                ),
                                const SizedBox(width: 10),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final countAsync = ref.watch(
                                        ownerCurrentMonthCompletedCountProvider);
                                    return _GlassStat(
                                      value: countAsync.isLoading
                                          ? '…'
                                          : '${countAsync.value ?? 0}',
                                      label: l?.tr('home_completed_month') ??
                                          'Terminés ce mois',
                                      icon: Icons.check_circle_outline_rounded,
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                _GlassStat(
                                  value: salon?.rating != null
                                      ? salon!.rating.toStringAsFixed(1)
                                      : '—',
                                  label: l?.tr('home_rating') ?? 'Note',
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

                      // ── Free team cap banners ─────────────────────────
                      // Either a countdown banner during the 30-day grace
                      // period, or a post-grace banner showing how many
                      // members were deactivated. Both send to the upgrade
                      // screen. Owner only — gerants/members don't see them.
                      if (salon != null && activeMember?.role != 'gerant')
                        Consumer(
                          builder: (context, ref, _) {
                            final team = ref.watch(ownerTeamProvider).value
                                ?? const <TeamMemberModel>[];
                            final now = DateTime.now();
                            final graceEnd = salon.freeCapGraceEndsAt;
                            final inGrace = salon.isFree &&
                                graceEnd != null &&
                                now.isBefore(graceEnd) &&
                                team.length > PlanConfig.freeTeamMemberCap;
                            final deactivatedCount = team
                                .where((m) => m.isDeactivatedByCap)
                                .length;
                            if (inGrace) {
                              return Column(children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: _TeamCapGraceBanner(
                                    graceEnd: graceEnd,
                                    teamCount: team.length,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ]);
                            }
                            if (salon.isFree && deactivatedCount > 0) {
                              return Column(children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: _TeamCapDeactivatedBanner(
                                    deactivatedCount: deactivatedCount,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ]);
                            }
                            return const SizedBox.shrink();
                          },
                        ),

                      // ── Today's appointments ────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SectionHeader(
                          title: l?.tr('home_today_appointments') ?? "Rendez-vous d'aujourd'hui",
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
                                l?.tr('home_no_appointments_today') ?? "Aucun rendez-vous prévu aujourd'hui",
                          ),
                        )
                      else
                        // Same tile (and action sheet) as the RDV tab: tap
                        // → mark done / no-show / WhatsApp / reschedule…
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Column(
                            children: todayUpcoming
                                .map((a) => OwnerAppointmentTile(
                                      key: ValueKey(a.id),
                                      appointment: a,
                                      onStatusChanged: () => ref.invalidate(
                                          ownerHomeAppointmentsProvider),
                                    ))
                                .toList(),
                          ),
                        ),

                      const SizedBox(height: 20),

                      // Tasks to do (hidden when empty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: OwnerTasksCard(),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final hasTasks =
                              ref.watch(ownerTasksProvider).isNotEmpty;
                          return SizedBox(height: hasTasks ? 16 : 0);
                        },
                      ),

                      // Revenue card (current month)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final revenueAsync =
                                ref.watch(ownerCurrentMonthRevenueProvider);
                            return _RevenueCard(
                              monthlyRevenue: revenueAsync.value ?? 0,
                              salon: salon,
                              loading: revenueAsync.isLoading,
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),
                      // ── Revenue by employee (Today / Week / Month) ──────
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 20),
                        child: _RevenueByEmployeeCard(
                          salon: salon,
                          homeAppointments: appointmentsAsync.value ?? const [],
                          currency: salon?.currency ?? 'MAD',
                        ),
                      ),

                      const SizedBox(height: 28),
                      // ── Weekly chart ─────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _WeeklyChart(
                          dayCounts: weekDayCounts,
                          weekTotal: weekTotal,
                          weekRevenue: weekRevenue,
                          currency: salon?.currency ?? 'MAD',
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

                      // Setup card — owner only. Gerants don't need the
                      // onboarding tasks (salon setup is owner's responsibility).
                      if (activeMember?.role != 'gerant') ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: OwnerSetupCard(),
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final hasSetup =
                                ref.watch(setupTasksProvider).isNotEmpty;
                            return SizedBox(height: hasSetup ? 16 : 0);
                          },
                        ),
                      ],

                      // ── Salon web link ─────────────────────────────────
                      if (salon != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SalonLinkCard(salon: salon),
                        ),
                      if (salon != null) const SizedBox(height: 16),

                      // ── Add-on services (premium Mon Salon offerings) ───
                      const _AddOnServicesSection(),

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

// ─── Revenue by employee card ────────────────────────────────────────────────
//
// Live revenue breakdown by team member, with Today/Week/Month segmented
// control. Only counts `status == 'completed'` appointments. Today + Week
// derive from `ownerHomeAppointmentsProvider` (already streaming ±7d);
// Month watches `ownerCurrentMonthAppointmentsProvider` (calendar month).
// Both are Riverpod streams → cache + listener built in, no manual cache.

enum _RevenuePeriod { today, week, month }

class _RevenueByEmployeeCard extends ConsumerStatefulWidget {
  const _RevenueByEmployeeCard({
    required this.salon,
    required this.homeAppointments,
    required this.currency,
  });

  final SalonModel? salon;
  final List<AppointmentModel> homeAppointments;
  final String currency;

  @override
  ConsumerState<_RevenueByEmployeeCard> createState() =>
      _RevenueByEmployeeCardState();
}

class _RevenueByEmployeeCardState
    extends ConsumerState<_RevenueByEmployeeCard> {
  _RevenuePeriod _period = _RevenuePeriod.today;

  ({DateTime start, DateTime end}) _range(_RevenuePeriod p, DateTime now) {
    switch (p) {
      case _RevenuePeriod.today:
        final start = DateTime(now.year, now.month, now.day);
        return (start: start, end: start.add(const Duration(days: 1)));
      case _RevenuePeriod.week:
        // ISO week: Monday → next Monday
        final weekday = now.weekday; // 1 = Monday
        final monday = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: weekday - 1));
        return (start: monday, end: monday.add(const Duration(days: 7)));
      case _RevenuePeriod.month:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 1);
        return (start: start, end: end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final team = ref.watch(ownerTeamProvider).value ?? const [];

    // Pick the right source stream based on selected period. Today + Week
    // fit in the existing ±7d home stream (no extra reads). Month needs
    // the dedicated calendar-month stream.
    final List<AppointmentModel> source = _period == _RevenuePeriod.month
        ? (ref.watch(ownerCurrentMonthAppointmentsProvider).value ?? const [])
        : widget.homeAppointments;

    // Salon-TZ wall-clock "now" so period bounds match the
    // wall-clock-UTC convention used to store `appointment.dateTime`.
    final now = TimezoneHelper.salonWallClockNow(widget.salon?.timezone);
    final r = _range(_period, now);

    // Filter: completed AND in range.
    final filtered = source.where((a) {
      if (a.status != 'completed') return false;
      final dt = a.dateTime;
      return !dt.isBefore(r.start) && dt.isBefore(r.end);
    }).toList();

    // Aggregate per assigned member. Legacy RDV without assignedMemberId
    // fall into a silent "_unassigned" bucket so total == sum(members).
    final byMember = <String, ({String name, double revenue, int count})>{};
    double total = 0;
    for (final a in filtered) {
      final mid = a.assignedMemberId ?? '_unassigned';
      final mname = a.assignedMemberName ??
          (l?.tr('home_revenue_unassigned') ?? 'Non assigné');
      final cur = byMember[mid];
      final newRev = (cur?.revenue ?? 0) + a.price;
      final newCount = (cur?.count ?? 0) + 1;
      byMember[mid] = (name: mname, revenue: newRev, count: newCount);
      total += a.price;
    }

    // Sort: members with revenue first (desc), then 0-revenue members
    // alphabetically. Pull all active members from the team so the
    // owner sees who's at 0 in the period (useful signal).
    final activeMembers = team.where((m) => m.isActive).toList();
    final lines = <({String name, double revenue, int count, String? photoUrl})>[];
    for (final m in activeMembers) {
      final agg = byMember.remove(m.id);
      lines.add((
        name: m.name,
        revenue: agg?.revenue ?? 0,
        count: agg?.count ?? 0,
        photoUrl: m.photoUrl,
      ));
    }
    // Any remaining buckets = RDV with assignedMemberId not in active team
    // (deactivated member or legacy data). Surface them so total matches.
    for (final entry in byMember.entries) {
      lines.add((
        name: entry.value.name,
        revenue: entry.value.revenue,
        count: entry.value.count,
        photoUrl: null,
      ));
    }
    lines.sort((a, b) {
      if (a.revenue != b.revenue) return b.revenue.compareTo(a.revenue);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    final totalLabel = total >= 1000
        ? '${(total / 1000).toStringAsFixed(1)}k ${CurrencyHelper.symbol(widget.currency)}'
        : CurrencyHelper.format(total, widget.currency);

    return Container(
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.payments_outlined,
                    color: AppColors.brand600, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l?.tr('home_revenue_title') ?? 'Revenus',
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Segmented control
          Container(
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(4),
            child: Row(
              children: [
                for (final p in _RevenuePeriod.values)
                  Expanded(
                    child: _PeriodPill(
                      label: switch (p) {
                        _RevenuePeriod.today =>
                          l?.tr('home_revenue_today') ?? "Aujourd'hui",
                        _RevenuePeriod.week =>
                          l?.tr('home_revenue_week') ?? 'Semaine',
                        _RevenuePeriod.month =>
                          l?.tr('home_revenue_month') ?? 'Mois',
                      },
                      selected: _period == p,
                      onTap: () => setState(() => _period = p),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Total
          Text(
            totalLabel,
            style: GoogleFonts.playfairDisplay(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            (l?.tr('home_revenue_completed_count') ??
                    '{n} RDV terminés')
                .replaceAll('{n}', '${filtered.length}'),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondary400,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // Per-member breakdown
          if (lines.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                l?.tr('home_revenue_no_members') ??
                    'Ajoutez des membres pour voir le détail',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.secondary400),
              ),
            )
          else
            ...lines.map((line) {
              final pct = total > 0 ? (line.revenue / total).clamp(0.0, 1.0) : 0.0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 14,
                      backgroundColor: AppColors.brand100,
                      backgroundImage: line.photoUrl != null
                          ? NetworkImage(line.photoUrl!)
                          : null,
                      child: line.photoUrl == null
                          ? Text(
                              line.name.isNotEmpty
                                  ? line.name[0].toUpperCase()
                                  : '?',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: AppColors.brand700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            line.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand950,
                            ),
                          ),
                          const SizedBox(height: 3),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(3),
                            child: LinearProgressIndicator(
                              value: pct,
                              minHeight: 4,
                              backgroundColor: AppColors.brand50,
                              valueColor: const AlwaysStoppedAnimation(
                                  AppColors.brand500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          CurrencyHelper.format(
                              line.revenue, widget.currency),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                          ),
                        ),
                        Text(
                          '${line.count} RDV',
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.secondary400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _PeriodPill extends StatelessWidget {
  const _PeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected
                  ? AppColors.brand700
                  : AppColors.secondary400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Add-on services section ─────────────────────────────────────────────────
//
// Horizontal carousel of premium services offered by Mon Salon to salon owners.
// Each tap opens WhatsApp on +212 663 32 24 29 with a pre-filled message
// identifying which service the owner is interested in.

class _AddOnServicesSection extends StatelessWidget {
  const _AddOnServicesSection();

  static const String _phone = '212663322429';

  Future<void> _open(String message) async {
    final url = Uri.parse(
      'https://wa.me/$_phone?text=${Uri.encodeComponent(message)}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final services = <_AddOnService>[
      _AddOnService(
        icon: Icons.campaign_rounded,
        gradient: const [Color(0xFF7C3AED), Color(0xFFEC4899)],
        title: l?.tr('addon_social_campaign_title') ?? 'Campagne social media',
        subtitle: l?.tr('addon_social_campaign_sub') ??
            'Instagram & TikTok clé en main',
        message: l?.tr('addon_social_campaign_msg') ??
            "Bonjour, je souhaite être accompagné pour créer une campagne publicitaire Instagram/TikTok pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.language_rounded,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
        title: l?.tr('addon_custom_website_title') ?? 'Site web sur mesure',
        subtitle: l?.tr('addon_custom_website_sub') ??
            'Vitrine pro & booking intégré',
        message: l?.tr('addon_custom_website_msg') ??
            "Bonjour, je suis intéressé par la création d'un site web personnalisé pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.tune_rounded,
        gradient: const [Color(0xFF10B981), Color(0xFF84CC16)],
        title: l?.tr('addon_custom_option_title') ?? 'Option sur mesure',
        subtitle: l?.tr('addon_custom_option_sub') ??
            'Feature dédiée pour votre salon',
        message: l?.tr('addon_custom_option_msg') ??
            "Bonjour, j'aimerais discuter d'une option sur mesure pour mon salon (intégration, feature spécifique…).",
      ),
      _AddOnService(
        icon: Icons.photo_camera_rounded,
        gradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
        title: l?.tr('addon_photo_title') ?? 'Shooting photo pro',
        subtitle: l?.tr('addon_photo_sub') ?? 'Salon, équipe & prestations',
        message: l?.tr('addon_photo_msg') ??
            "Bonjour, je souhaite faire un shooting photo professionnel de mon salon et de mes prestations.",
      ),
      _AddOnService(
        icon: Icons.movie_creation_rounded,
        gradient: const [Color(0xFFEF4444), Color(0xFFEC4899)],
        title: l?.tr('addon_video_title') ?? 'Vidéos TikTok / Reels',
        subtitle: l?.tr('addon_video_sub') ?? 'Contenu régulier viral',
        message: l?.tr('addon_video_msg') ??
            "Bonjour, je cherche un accompagnement pour créer du contenu vidéo (TikTok/Reels) pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.location_on_rounded,
        gradient: const [Color(0xFF2563EB), Color(0xFF8B5CF6)],
        title: l?.tr('addon_google_seo_title') ?? 'Google & SEO local',
        subtitle: l?.tr('addon_google_seo_sub') ??
            'Fiche Google + gestion des avis',
        message: l?.tr('addon_google_seo_msg') ??
            "Bonjour, j'aimerais optimiser ma fiche Google + gérer les avis pour attirer plus de clients locaux.",
      ),
      _AddOnService(
        icon: Icons.school_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFFA855F7)],
        title: l?.tr('addon_training_title') ?? 'Formation équipe',
        subtitle: l?.tr('addon_training_sub') ??
            'Service client & techniques de vente',
        message: l?.tr('addon_training_msg') ??
            "Bonjour, je suis intéressé par une formation pour mon équipe (service client, techniques de vente).",
      ),
      _AddOnService(
        icon: Icons.palette_rounded,
        gradient: const [Color(0xFFEC4899), Color(0xFFF97316)],
        title: l?.tr('addon_branding_title') ?? 'Logo & identité visuelle',
        subtitle: l?.tr('addon_branding_sub') ??
            'Création ou rebranding complet',
        message: l?.tr('addon_branding_msg') ??
            "Bonjour, je souhaite créer/refaire le logo et l'identité visuelle de mon salon.",
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with title + subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF558148), Color(0xFF84CC16)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('addon_section_title') ??
                          'Propulsez votre salon',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand950,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l?.tr('addon_section_subtitle') ??
                          'Services premium Mon Salon',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Horizontal carousel
        SizedBox(
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: services.length,
            itemBuilder: (_, i) => _AddOnCard(
              service: services[i],
              onTap: () => _open(services[i].message),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddOnService {
  const _AddOnService({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.message,
  });
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final String message;
}

class _AddOnCard extends StatefulWidget {
  const _AddOnCard({required this.service, required this.onTap});
  final _AddOnService service;
  final VoidCallback onTap;

  @override
  State<_AddOnCard> createState() => _AddOnCardState();
}

class _AddOnCardState extends State<_AddOnCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = widget.service;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 196,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: s.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: s.gradient.first.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative background bubble (subtle depth)
              Positioned(
                top: -24,
                right: -24,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(s.icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    s.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l?.tr('addon_cta') ?? 'Discuter',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: s.gradient.last,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 12, color: s.gradient.last),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
  bool _showBookingLink = false;

  SalonModel get salon => widget.salon;

  String get _salonUrl {
    final slug = _generatedSlug ?? salon.slug;
    if (slug != null && slug.isNotEmpty) {
      return 'https://monsalon.web.app/s/$slug';
    }
    return 'https://monsalon.web.app/salon.html?id=${salon.id}';
  }

  String get _bookingUrl {
    final slug = _generatedSlug ?? salon.slug;
    if (slug != null && slug.isNotEmpty) {
      return 'https://monsalon.web.app/booking.html?slug=$slug';
    }
    return 'https://monsalon.web.app/booking.html?id=${salon.id}';
  }

  String get _currentUrl => _showBookingLink ? _bookingUrl : _salonUrl;

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
    final l = AppLocalizations.of(context);
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
                  _showBookingLink
                      ? (l?.tr('home_booking_link') ?? 'Lien de réservation')
                      : (l?.tr('home_salon_link') ?? 'Lien de votre salon'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentUrl,
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
          // Swap button
          GestureDetector(
            onTap: () => setState(() => _showBookingLink = !_showBookingLink),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.brand600,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Copy button
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _currentUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l?.tr('home_link_copied') ?? 'Lien copié !'),
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
              child: Text(
                l?.tr('home_copy') ?? 'Copier',
                style: const TextStyle(
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
    required this.monthlyRevenue,
    required this.salon,
    required this.loading,
  });
  final double monthlyRevenue;
  final SalonModel? salon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currency = salon?.currency ?? 'MAD';
    final revenueStr = monthlyRevenue >= 1000
        ? '${(monthlyRevenue / 1000).toStringAsFixed(1)}k ${CurrencyHelper.symbol(currency)}'
        : CurrencyHelper.format(monthlyRevenue, currency);

    final open =
        salon != null ? OwnerHomeScreen._isOpen(salon!) : false;

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
                    Text(
                      l?.tr('home_monthly_revenue') ?? 'Revenus du mois',
                      style: const TextStyle(
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
                        open ? (l?.tr('home_open') ?? 'Ouvert') : (l?.tr('home_closed') ?? 'Fermé'),
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
    this.currency = 'MAD',
  });

  final List<int> dayCounts;
  final int weekTotal;
  final double weekRevenue;
  final String currency;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final maxCount = dayCounts.reduce((a, b) => a > b ? a : b);
    final todayIndex = DateTime.now().weekday - 1;

    final revenueStr = weekRevenue >= 1000
        ? '${(weekRevenue / 1000).toStringAsFixed(1)}k ${CurrencyHelper.symbol(currency)}'
        : CurrencyHelper.format(weekRevenue, currency);

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
                l?.tr('home_this_week') ?? 'Cette semaine',
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
                  revenueStr,
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
  List<String> _noShowAlerts = [];
  List<String> _priceSuggestions = [];
  List<String> _actionSuggestions = [];
  String? _monthlyComparison;
  String? _financialInsights;
  bool _loading = false;
  bool _error = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadCachedOrFetch();
  }

  Future<void> _loadCachedOrFetch() async {
    setState(() { _loading = true; _error = false; });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .get();
      final data = doc.data();
      final cachedDate = data?['aiSummaryDate'] as String?;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      if (!mounted) return;
      final cachedLang = data?['aiSummaryLang'] as String?;
      final currentLang = Localizations.localeOf(context).languageCode;
      if (cachedDate == today && data?['aiSummary'] != null && cachedLang == currentLang) {
        _applyCache(data!);
        return;
      }
      await _fetchFromGemini();
    } catch (e) {
      await _fetchFromGemini();
    }
  }

  void _applyCache(Map<String, dynamic> data) {
    setState(() {
      _summary = data['aiSummary'] as String?;
      _noShowAlerts = List<String>.from(data['aiNoShowAlerts'] ?? []);
      _priceSuggestions = List<String>.from(data['aiPriceSuggestions'] ?? []);
      _actionSuggestions = List<String>.from(data['aiActionSuggestions'] ?? []);
      _monthlyComparison = data['aiMonthlyComparison'] as String?;
      _financialInsights = data['aiFinancialInsights'] as String?;
      _loading = false;
    });
  }

  Future<void> _fetchFromGemini() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateDailySummary',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final lang = Localizations.localeOf(context).languageCode;
      final result = await callable.call({'salonId': widget.salonId, 'lang': lang});
      if (!mounted) return;
      final data = result.data as Map<String, dynamic>;

      setState(() {
        _summary = data['summary'] as String?;
        _noShowAlerts = List<String>.from(data['noShowAlerts'] ?? []);
        _priceSuggestions = List<String>.from(data['priceSuggestions'] ?? []);
        _actionSuggestions = List<String>.from(data['actionSuggestions'] ?? []);
        _monthlyComparison = data['monthlyComparison'] as String?;
        _financialInsights = data['financialInsights'] as String?;
        _loading = false;
      });

      // Cache all sections in Firestore
      final today = DateTime.now().toIso8601String().substring(0, 10);
      FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .update({
        'aiSummary': _summary,
        'aiSummaryDate': today,
        'aiSummaryLang': lang,
        'aiNoShowAlerts': _noShowAlerts,
        'aiPriceSuggestions': _priceSuggestions,
        'aiActionSuggestions': _actionSuggestions,
        'aiMonthlyComparison': _monthlyComparison,
        'aiFinancialInsights': _financialInsights,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  bool get _hasSections =>
      _noShowAlerts.isNotEmpty ||
      _priceSuggestions.isNotEmpty ||
      _actionSuggestions.isNotEmpty ||
      (_monthlyComparison ?? '').isNotEmpty ||
      (_financialInsights ?? '').isNotEmpty;

  String _t(String key, String fallback) =>
      AppLocalizations.of(context)?.tr(key) ?? fallback;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand50, const Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brand100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _t('home_ai_title', 'Assistant IA'),
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (!_loading)
                GestureDetector(
                  onTap: _fetchFromGemini,
                  child: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.secondary400),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(color: AppColors.brand600, strokeWidth: 2),
                ),
              ),
            )
          else if (_error)
            GestureDetector(
              onTap: _fetchFromGemini,
              child: Text(
                _t('home_ai_error', 'Impossible de générer le résumé. Touchez pour réessayer.'),
                style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: AppColors.secondary400, height: 1.5),
              ),
            )
          else if (_summary != null) ...[
            // ── Summary section ──
            _AISectionRow(
              icon: Icons.summarize_rounded,
              color: AppColors.brand600,
              text: _summary!,
            ),

            // ── No-show alerts ──
            if (_noShowAlerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _AISectionHeader(icon: Icons.warning_amber_rounded, color: const Color(0xFFEA580C), label: _t('home_ai_noshow', 'Risque no-show')),
              for (final alert in _noShowAlerts)
                _AISectionRow(icon: Icons.person_off_rounded, color: const Color(0xFFEA580C), text: alert),
            ],

            // ── Expandable sections ──
            if (_hasSections && !_expanded) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_t('home_ai_see_more', 'Voir plus'), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.brand600),
                  ],
                ),
              ),
            ],

            if (_expanded) ...[
              // ── Action suggestions ──
              if (_actionSuggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionHeader(icon: Icons.lightbulb_outline_rounded, color: const Color(0xFF0891B2), label: _t('home_ai_suggestions', 'Suggestions')),
                for (final s in _actionSuggestions)
                  _AISectionRow(icon: Icons.arrow_right_rounded, color: const Color(0xFF0891B2), text: s),
              ],

              // ── Price suggestions ──
              if (_priceSuggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionHeader(icon: Icons.monetization_on_outlined, color: const Color(0xFF059669), label: _t('home_ai_price', 'Suggestions de prix')),
                for (final s in _priceSuggestions)
                  _AISectionRow(icon: Icons.arrow_right_rounded, color: const Color(0xFF059669), text: s),
              ],

              // ── Monthly comparison ──
              if ((_monthlyComparison ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionRow(
                  icon: Icons.compare_arrows_rounded,
                  color: AppColors.brand600,
                  text: _monthlyComparison!,
                  label: _t('home_ai_monthly', 'Comparaison mensuelle'),
                ),
              ],

              // ── Financial insights ──
              if ((_financialInsights ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionRow(
                  icon: Icons.insights_rounded,
                  color: const Color(0xFF0369A1),
                  text: _financialInsights!,
                  label: _t('home_ai_finance', 'Insights financiers'),
                ),
              ],

              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_t('home_ai_see_less', 'Voir moins'), style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: AppColors.brand600),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AISectionHeader extends StatelessWidget {
  const _AISectionHeader({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _AISectionRow extends StatelessWidget {
  const _AISectionRow({required this.icon, required this.color, required this.text, this.label});
  final IconData icon;
  final Color color;
  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 6),
                  Text(label!, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label == null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: color.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: AppColors.secondary600, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}


// Orange warning banner shown on the owner home during the 30-day grace
// period following a downgrade to Free while the team still has >2 members.
// Displays a countdown and a CTA to the subscription screen.
class _TeamCapGraceBanner extends StatelessWidget {
  final DateTime graceEnd;
  final int teamCount;
  const _TeamCapGraceBanner({
    required this.graceEnd,
    required this.teamCount,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daysLeft = graceEnd.difference(DateTime.now()).inDays;
    final excess = teamCount - 2;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFCD34D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_outlined,
                color: Color(0xFF92400E), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l?.tr('team_cap_grace_title') ??
                          'Plan Free : {days} jour(s) avant désactivation')
                      .replaceAll('{days}', daysLeft.toString()),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF78350F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (l?.tr('team_cap_grace_body') ??
                          'Équipe limitée à 2 membres sur Free. {excess} membre(s) seront désactivés à la fin du délai. Passez en Essentiel pour tout conserver.')
                      .replaceAll('{excess}', excess.toString()),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF92400E),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerSubscriptionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_upward, size: 14),
                  label: Text(
                    l?.tr('team_cap_grace_cta') ?? 'Passer en Essentiel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF92400E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Red banner shown on the owner home after the Free plan grace period
// expired and CF `enforceFreeTeamCap` deactivated the excess members.
// Indicates the count and pitches the upgrade to reactivate them.
class _TeamCapDeactivatedBanner extends StatelessWidget {
  final int deactivatedCount;
  const _TeamCapDeactivatedBanner({required this.deactivatedCount});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFCA5A5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_off_outlined,
                color: Color(0xFF7F1D1D), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l?.tr('team_cap_deactivated_title') ??
                          '{count} membre(s) désactivé(s)')
                      .replaceAll('{count}', deactivatedCount.toString()),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l?.tr('team_cap_deactivated_body') ??
                      'Limite Free atteinte. Leurs données sont conservées. Passez en Essentiel pour les réactiver instantanément.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF991B1B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerSubscriptionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14),
                  label: Text(
                    l?.tr('team_cap_deactivated_cta') ??
                        'Réactiver via Essentiel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F1D1D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
