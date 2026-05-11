import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';
import '../utils/timezone_helper.dart';
import 'member_avatar.dart';

/// Show the team-member detail bottom sheet. Reuses the same caching +
/// parallel-load pattern as `client_detail_sheet.dart`.
///
/// [onEdit] / [onDelete] are invoked AFTER the sheet has been dismissed,
/// so the parent screen can open its own edit form or confirmation dialog
/// without nesting modals. Both callbacks are optional.
Future<void> showTeamMemberDetailSheet(
  BuildContext context, {
  required TeamMemberModel member,
  required SalonModel salon,
  VoidCallback? onEdit,
  VoidCallback? onDelete,
  VoidCallback? onManageUnavailability,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      child: TeamMemberDetailSheet(
        member: member,
        salon: salon,
        onEdit: onEdit,
        onDelete: onDelete,
        onManageUnavailability: onManageUnavailability,
      ),
    ),
  );
}

// ─── Cache ─────────────────────────────────────────────────────────────

class _TeamMemberDetailCache {
  static const Duration _ttl = Duration(minutes: 5);
  static final Map<String, _CacheEntry> _store = {};

  static _TeamMemberDetailData? get(String key) {
    final e = _store[key];
    if (e == null) return null;
    if (DateTime.now().difference(e.cachedAt) > _ttl) {
      _store.remove(key);
      return null;
    }
    return e.data;
  }

  static void put(String key, _TeamMemberDetailData data) {
    _store[key] = _CacheEntry(data, DateTime.now());
  }

  static void invalidate(String key) => _store.remove(key);

  static String makeKey(String salonId, String memberId) =>
      '$salonId|$memberId';
}

class _CacheEntry {
  _CacheEntry(this.data, this.cachedAt);
  final _TeamMemberDetailData data;
  final DateTime cachedAt;
}

class _TeamMemberDetailData {
  _TeamMemberDetailData({
    required this.monthBookedCount,
    required this.monthRevenue,
    required this.monthBookedHours,
    required this.monthAvailableHours,
    required this.totalAssignedLast90,
    required this.noShowCountLast90,
    required this.uniqueClientsCount,
    required this.topServiceName,
    required this.lastVisit,
    required this.upcoming,
    required this.past,
  });

  final int monthBookedCount;
  final double monthRevenue;
  final double monthBookedHours;
  final double monthAvailableHours;
  final int totalAssignedLast90;
  final int noShowCountLast90;
  final int uniqueClientsCount;
  final String? topServiceName;
  final DateTime? lastVisit;
  final List<AppointmentModel> upcoming;
  final List<AppointmentModel> past;

  double get occupancyRate {
    if (monthAvailableHours <= 0) return 0;
    return (monthBookedHours / monthAvailableHours * 100).clamp(0, 100);
  }

  double get noShowRate {
    if (totalAssignedLast90 == 0) return 0;
    return noShowCountLast90 / totalAssignedLast90 * 100;
  }
}

// ─── Perf tier (driven by month booked count) ──────────────────────────

class _PerfTier {
  const _PerfTier(this.key, this.emoji, this.bg, this.fg);
  final String key;
  final String emoji;
  final Color bg;
  final Color fg;

  static _PerfTier of(int monthBookedCount) {
    if (monthBookedCount >= 60) {
      return const _PerfTier('top', '👑', Color(0xFFFEF3C7), Color(0xFF92400E));
    }
    if (monthBookedCount >= 30) {
      return const _PerfTier('gold', '🥇', Color(0xFFFEF3C7), Color(0xFFB45309));
    }
    if (monthBookedCount >= 10) {
      return const _PerfTier('silver', '🥈', Color(0xFFE5E7EB), Color(0xFF4B5563));
    }
    return const _PerfTier('starter', '🌱', Color(0xFFD1FAE5), Color(0xFF065F46));
  }

  String label(AppLocalizations? l) {
    switch (key) {
      case 'top':
        return l?.tr('team_perf_tier_top') ?? 'Top performer';
      case 'gold':
        return l?.tr('team_perf_tier_gold') ?? 'Gold';
      case 'silver':
        return l?.tr('team_perf_tier_silver') ?? 'Silver';
      default:
        return l?.tr('team_perf_tier_starter') ?? 'Démarrage';
    }
  }
}

// ─── Sheet widget ──────────────────────────────────────────────────────

class TeamMemberDetailSheet extends ConsumerStatefulWidget {
  const TeamMemberDetailSheet({
    super.key,
    required this.member,
    required this.salon,
    this.onEdit,
    this.onDelete,
    this.onManageUnavailability,
  });

  final TeamMemberModel member;
  final SalonModel salon;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final VoidCallback? onManageUnavailability;

  @override
  ConsumerState<TeamMemberDetailSheet> createState() =>
      _TeamMemberDetailSheetState();
}

class _TeamMemberDetailSheetState
    extends ConsumerState<TeamMemberDetailSheet> {
  static const _dayKeys = [
    'lundi', 'mardi', 'mercredi', 'jeudi',
    'vendredi', 'samedi', 'dimanche',
  ];

  late final String _cacheKey;
  _TeamMemberDetailData? _data;
  bool _loading = false;
  String? _error;
  bool _showAllUpcoming = false;
  bool _showAllPast = false;

  @override
  void initState() {
    super.initState();
    _cacheKey =
        _TeamMemberDetailCache.makeKey(widget.salon.id, widget.member.id);
    final cached = _TeamMemberDetailCache.get(_cacheKey);
    if (cached != null) {
      _data = cached;
    } else {
      _refresh();
    }
  }

  Future<void> _refresh({bool bypassCache = false}) async {
    if (bypassCache) _TeamMemberDetailCache.invalidate(_cacheKey);
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final fs = FirebaseFirestore.instance;
      final salonId = widget.salon.id;
      final m = widget.member;
      // Compare against salon wall-clock — `appointment.dateTime` is
      // stored as wall-clock-UTC of the salon TZ (see
      // reference_wall_clock_utc_convention.md). Using DateTime.now()
      // would drift by the salon's offset on a non-salon-TZ device.
      final now = TimezoneHelper.salonWallClockNow(widget.salon.timezone);
      final monthStart = DateTime.utc(now.year, now.month, 1);
      final nextMonthStart = DateTime.utc(now.year, now.month + 1, 1);
      final past90Start = now.subtract(const Duration(days: 90));

      // ── Past 90 days query ─────────────────────────────────────
      // Uses existing index #19: appointments(salonId, assignedMemberId,
      // dateTime ASC). Pulls last-90j window so we can derive:
      //   - no-show rate (status == 'no_show')
      //   - past list (most-recent slice, reversed in-memory)
      //   - month revenue + booked hours for the past portion
      //   - top service (status == 'completed')
      //   - unique clients (over the 90-day window)
      final pastFuture = fs
          .collection('appointments')
          .where('salonId', isEqualTo: salonId)
          .where('assignedMemberId', isEqualTo: m.id)
          .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(past90Start))
          .where('dateTime', isLessThan: Timestamp.fromDate(now))
          .orderBy('dateTime')
          .limit(500)
          .get()
          .then((s) => s.docs
              .map((d) => AppointmentModel.fromFirestore(d))
              .toList()
            ..sort((a, b) => b.dateTime.compareTo(a.dateTime)));

      // ── Upcoming query (everything from now into the future) ────
      // Same index #19. We pull the full window so we cover both the
      // remainder of this month (for booked-hours stat) and the
      // upcoming-list section. status filtering is done client-side.
      final upcomingFuture = fs
          .collection('appointments')
          .where('salonId', isEqualTo: salonId)
          .where('assignedMemberId', isEqualTo: m.id)
          .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(now))
          .orderBy('dateTime')
          .limit(100)
          .get()
          .then((s) => s.docs
              .map((d) => AppointmentModel.fromFirestore(d))
              .toList());

      final results = await Future.wait([
        pastFuture.catchError((e) {
          debugPrint('[TeamDetail] past query failed: $e');
          return <AppointmentModel>[];
        }),
        upcomingFuture.catchError((e) {
          debugPrint('[TeamDetail] upcoming query failed: $e');
          return <AppointmentModel>[];
        }),
      ]);
      final past = results[0];
      final futureRdv = results[1];

      // ── Month aggregates ───────────────────────────────────────
      bool inCurrentMonth(DateTime t) =>
          !t.isBefore(monthStart) && t.isBefore(nextMonthStart);

      final monthPast = past.where((a) => inCurrentMonth(a.dateTime)).toList();
      final monthFuture =
          futureRdv.where((a) => inCurrentMonth(a.dateTime)).toList();

      int monthBookedCount = 0;
      double monthRevenue = 0;
      int monthBookedMinutes = 0;
      for (final a in monthPast) {
        // Revenue counts only 'completed' (cancelled/no_show don't earn).
        if (a.status == 'completed') {
          monthRevenue += a.price;
        }
        // Booked count + booked hours follow the same "slot was used"
        // semantic as the agenda: completed OR upcoming. cancelled
        // and no_show free up the slot, so they do NOT count.
        if (a.status == 'completed' || a.status == 'upcoming') {
          monthBookedCount += 1;
          monthBookedMinutes += a.durationMinutes;
        }
      }
      for (final a in monthFuture) {
        if (a.status == 'upcoming') {
          monthBookedCount += 1;
          monthBookedMinutes += a.durationMinutes;
        }
      }

      // ── Month available hours (salon hours minus member off) ────
      final monthAvailableHours = _computeMonthAvailableHours(
        now: now,
        monthStart: monthStart,
        nextMonthStart: nextMonthStart,
      );

      // ── No-show rate (last 90 days, assigned to this member) ────
      final noShowCount = past.where((a) => a.status == 'no_show').length;
      final totalAssigned = past.length;

      // ── Top service (completed only, over the 90-day window) ────
      final serviceCounts = <String, int>{};
      for (final a in past) {
        if (a.status != 'completed') continue;
        if (a.serviceName.isEmpty) continue;
        serviceCounts[a.serviceName] = (serviceCounts[a.serviceName] ?? 0) + 1;
      }
      String? topService;
      int topCount = -1;
      serviceCounts.forEach((k, v) {
        if (v > topCount) {
          topCount = v;
          topService = k;
        }
      });

      // ── Unique clients (90j + future window combined) ──────────
      final clientKeys = <String>{};
      for (final a in [...past, ...futureRdv]) {
        final key = a.clientId.isNotEmpty && a.clientId != 'walk-in'
            ? 'uid:${a.clientId}'
            : (a.clientPhone != null && a.clientPhone!.isNotEmpty
                ? 'phone:${a.clientPhone}'
                : null);
        if (key != null) clientKeys.add(key);
      }

      // ── Last visit (most-recent completed in window) ───────────
      DateTime? lastVisit;
      for (final a in past) {
        if (a.status == 'completed') {
          lastVisit = a.dateTime;
          break; // already sorted DESC
        }
      }

      // ── Upcoming list (status==upcoming, future only) ──────────
      final upcoming = futureRdv
          .where((a) => a.status == 'upcoming')
          .take(20)
          .toList();

      final data = _TeamMemberDetailData(
        monthBookedCount: monthBookedCount,
        monthRevenue: monthRevenue,
        monthBookedHours: monthBookedMinutes / 60.0,
        monthAvailableHours: monthAvailableHours,
        totalAssignedLast90: totalAssigned,
        noShowCountLast90: noShowCount,
        uniqueClientsCount: clientKeys.length,
        topServiceName: topService,
        lastVisit: lastVisit,
        upcoming: upcoming,
        past: past.take(10).toList(),
      );
      _TeamMemberDetailCache.put(_cacheKey, data);
      if (mounted) {
        setState(() {
          _data = data;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Computes salon-open hours for the current month, minus the member's
  /// full-day unavailabilities (specific dates + recurring weekdays) and
  /// any slot-level blocks. Returns a `double` (hours, fractional).
  double _computeMonthAvailableHours({
    required DateTime now,
    required DateTime monthStart,
    required DateTime nextMonthStart,
  }) {
    final wh = widget.salon.workingHours;
    final m = widget.member;
    double total = 0;
    var cursor = monthStart;
    while (cursor.isBefore(nextMonthStart)) {
      final weekday = cursor.weekday; // 1=Mon … 7=Sun
      final dayKey = _dayKeys[weekday - 1];
      final dayData = wh[dayKey];
      final isOpen = dayData is Map && dayData['isOpen'] == true;
      if (isOpen) {
        final openStr = dayData['open'] as String?;
        final closeStr = dayData['close'] as String?;
        if (openStr != null && closeStr != null) {
          final openMin = _parseHHmmToMin(openStr);
          final closeMin = _parseHHmmToMin(closeStr);
          if (closeMin > openMin) {
            double dayHours = (closeMin - openMin) / 60.0;
            final iso = _iso(cursor);
            final isRecurringOff = m.recurringDaysOff.contains(weekday);
            final isDateOff = m.unavailableDates.contains(iso);
            if (isRecurringOff || isDateOff) {
              dayHours = 0;
            } else {
              final slots = m.unavailableSlots[iso] ?? const <String>[];
              for (final s in slots) {
                final parts = s.split('-');
                if (parts.length != 2) continue;
                final sStart = _parseHHmmToMin(parts[0].trim());
                final sEnd = _parseHHmmToMin(parts[1].trim());
                if (sEnd > sStart) {
                  dayHours -= (sEnd - sStart) / 60.0;
                }
              }
              if (dayHours < 0) dayHours = 0;
            }
            total += dayHours;
          }
        }
      }
      cursor = cursor.add(const Duration(days: 1));
    }
    return total;
  }

  static int _parseHHmmToMin(String s) {
    final parts = s.split(':');
    if (parts.length != 2) return 0;
    final h = int.tryParse(parts[0]) ?? 0;
    final mm = int.tryParse(parts[1]) ?? 0;
    return h * 60 + mm;
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Actions ──────────────────────────────────────────────────────────

  void _openWhatsApp() {
    final phone = widget.member.phone;
    if (phone == null || phone.isEmpty) {
      _toast(AppLocalizations.of(context)?.tr('team_detail_no_phone') ??
          'Numéro WhatsApp manquant.');
      return;
    }
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    launchUrl(Uri.parse('https://wa.me/$digits'),
        mode: LaunchMode.externalApplication);
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final m = widget.member;
    final currency = widget.salon.currency;
    final tier = _PerfTier.of(_data?.monthBookedCount ?? 0);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 44, height: 4,
            decoration: BoxDecoration(
              color: AppColors.secondary200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(l, m, tier),
                  const SizedBox(height: 20),
                  _buildActionButtons(l),
                  const SizedBox(height: 24),
                  if (_data == null && _loading) ...[
                    const Center(child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(color: AppColors.brand600),
                    )),
                  ] else if (_error != null) ...[
                    _buildErrorBlock(l),
                  ] else if (_data != null) ...[
                    _buildKeyStats(l, currency),
                    const SizedBox(height: 14),
                    _buildHistoryStats(l),
                    const SizedBox(height: 14),
                    _buildDetailsRows(l, m),
                    const SizedBox(height: 14),
                    _buildUnavailabilitySection(l, m),
                    const SizedBox(height: 14),
                    _buildAppointmentSection(
                      l,
                      title: l?.tr('team_detail_upcoming_rdv') ?? 'Prochains RDV',
                      items: _data!.upcoming,
                      showAll: _showAllUpcoming,
                      onToggleShowAll: () =>
                          setState(() => _showAllUpcoming = !_showAllUpcoming),
                      currency: currency,
                      emptyLabel: l?.tr('team_detail_no_upcoming') ??
                          'Aucun RDV à venir.',
                    ),
                    const SizedBox(height: 14),
                    _buildAppointmentSection(
                      l,
                      title: l?.tr('team_detail_past_rdv') ?? 'Historique',
                      items: _data!.past,
                      showAll: _showAllPast,
                      onToggleShowAll: () =>
                          setState(() => _showAllPast = !_showAllPast),
                      currency: currency,
                      emptyLabel: l?.tr('team_detail_no_past') ??
                          'Aucun RDV passé.',
                    ),
                    const SizedBox(height: 18),
                    _buildOwnerActions(l),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations? l, TeamMemberModel m, _PerfTier tier) {
    final roleLabel = m.role == 'gerant'
        ? (l?.tr('team_role_manager') ?? 'Gérant(e)')
        : (l?.tr('team_role_member') ?? 'Employé(e)');
    final availabilityBadge = _availabilityBadge(l, m);

    return Column(
      children: [
        MemberAvatar(
          name: m.name,
          photoUrl: m.photoUrl,
          radius: 42,
          backgroundColor: AppColors.brand50,
        ),
        const SizedBox(height: 14),
        Text(
          m.name,
          style: GoogleFonts.dmSans(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.brand950,
          ),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          roleLabel,
          style: const TextStyle(
            color: AppColors.secondary500,
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: tier.bg,
                borderRadius: BorderRadius.circular(99),
                border: Border.all(color: tier.fg.withValues(alpha: 0.15)),
              ),
              child: Text(
                '${tier.emoji} ${tier.label(l)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tier.fg,
                  letterSpacing: 0.3,
                ),
              ),
            ),
            ?availabilityBadge,
          ],
        ),
      ],
    );
  }

  Widget? _availabilityBadge(AppLocalizations? l, TeamMemberModel m) {
    final now = TimezoneHelper.salonWallClockNow(widget.salon.timezone);
    final today = DateTime.utc(now.year, now.month, now.day);
    if (m.isUnavailableOnDate(today)) {
      return _pillBadge(
        l?.tr('team_detail_off_today') ?? 'Indispo aujourd\'hui',
        bg: const Color(0xFFFEE2E2),
        fg: const Color(0xFFB91C1C),
      );
    }
    return _pillBadge(
      l?.tr('team_detail_available_today') ?? 'Dispo aujourd\'hui',
      bg: const Color(0xFFD1FAE5),
      fg: const Color(0xFF065F46),
    );
  }

  Widget _pillBadge(String label, {required Color bg, required Color fg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildActionButtons(AppLocalizations? l) {
    final hasPhone =
        widget.member.phone != null && widget.member.phone!.isNotEmpty;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: hasPhone ? _openWhatsApp : null,
            icon: const Icon(FontAwesomeIcons.whatsapp,
                size: 16, color: Color(0xFF25D366)),
            label: Text(
              l?.tr('team_detail_message') ?? 'Message',
              style: const TextStyle(
                color: AppColors.brand950,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: const BorderSide(color: AppColors.secondary200),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(99)),
            ),
          ),
        ),
        if (widget.onManageUnavailability != null) ...[
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onManageUnavailability!();
              },
              icon: const Icon(Icons.event_busy_rounded, size: 18),
              label: Text(l?.tr('team_detail_manage_unavail') ??
                  'Indisponibilités'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand950,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(99)),
                elevation: 0,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKeyStats(AppLocalizations? l, String currency) {
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.event_available_rounded,
            label: l?.tr('team_detail_rdv_month') ?? 'RDV ce mois',
            value: '${_data!.monthBookedCount}',
            iconColor: const Color(0xFF0EA5E9),
            iconBg: const Color(0xFFE0F2FE),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.payments_outlined,
            label: l?.tr('team_detail_revenue_month') ?? 'Revenu ce mois',
            value: CurrencyHelper.format(_data!.monthRevenue, currency),
            iconColor: const Color(0xFF059669),
            iconBg: const Color(0xFFD1FAE5),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryStats(AppLocalizations? l) {
    final occupancy = _data!.occupancyRate.round();
    final noShowRate = _data!.noShowRate.round();
    final noShowEnough = _data!.totalAssignedLast90 >= 3;
    return Row(
      children: [
        Expanded(
          child: _StatCard(
            icon: Icons.speed_rounded,
            label: l?.tr('team_detail_occupancy') ?? 'Taux d\'occupation',
            value: '$occupancy%',
            iconColor: const Color(0xFF7C3AED),
            iconBg: const Color(0xFFEDE9FE),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _StatCard(
            icon: Icons.event_busy_rounded,
            label: l?.tr('team_detail_no_show_rate') ?? 'No-show 90j',
            value: noShowEnough ? '$noShowRate%' : '—',
            iconColor: const Color(0xFFDB2777),
            iconBg: const Color(0xFFFCE7F3),
          ),
        ),
      ],
    );
  }

  Widget _buildDetailsRows(AppLocalizations? l, TeamMemberModel m) {
    final services = m.assignedServiceNames;
    final memberSince = DateFormat('MMM yyyy').format(m.createdAt);
    final lastVisit = _data!.lastVisit;
    String lastVisitLabel;
    if (lastVisit == null) {
      lastVisitLabel = l?.tr('team_detail_last_visit_never') ?? '—';
    } else {
      final days = DateTime.now().toUtc().difference(lastVisit).inDays;
      if (days <= 0) {
        lastVisitLabel = l?.tr('clients_today') ?? "Aujourd'hui";
      } else if (days == 1) {
        lastVisitLabel = l?.tr('clients_yesterday') ?? 'Hier';
      } else {
        lastVisitLabel = (l?.tr('clients_days_ago') ?? 'Il y a {days} jours')
            .replaceAll('{days}', '$days');
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _detailRow(
            Icons.content_cut,
            l?.tr('team_detail_services') ?? 'Services',
            services.isEmpty
                ? (l?.tr('team_detail_no_services') ?? 'Aucun')
                : services.join(', '),
          ),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(
            Icons.people_outline,
            l?.tr('team_detail_unique_clients') ?? 'Clients servis (90j)',
            '${_data!.uniqueClientsCount}',
          ),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(
            Icons.star_outline_rounded,
            l?.tr('team_detail_top_service') ?? 'Service le + booké',
            _data!.topServiceName ?? '—',
          ),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(
            Icons.cake_outlined,
            l?.tr('team_detail_member_since') ?? 'Membre depuis',
            memberSince,
          ),
          const Divider(height: 1, color: AppColors.secondary200),
          _detailRow(
            Icons.history_rounded,
            l?.tr('team_detail_last_visit') ?? 'Dernière visite',
            lastVisitLabel,
          ),
          if (m.phone != null && m.phone!.isNotEmpty) ...[
            const Divider(height: 1, color: AppColors.secondary200),
            InkWell(
              onTap: _openWhatsApp,
              child: _detailRow(
                FontAwesomeIcons.whatsapp,
                l?.tr('team_detail_whatsapp') ?? 'WhatsApp',
                m.phone!,
                trailingColor: const Color(0xFF25D366),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value,
      {Color? trailingColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.secondary500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.secondary600)),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: trailingColor ?? AppColors.brand950,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnavailabilitySection(AppLocalizations? l, TeamMemberModel m) {
    final now = TimezoneHelper.salonWallClockNow(widget.salon.timezone);
    // Week window: today + next 6 days.
    final weekDays = List.generate(
      7,
      (i) => DateTime.utc(now.year, now.month, now.day)
          .add(Duration(days: i)),
    );
    final offThisWeek = weekDays
        .where((d) => m.isUnavailableOnDate(d))
        .map((d) => DateFormat('EEE dd').format(d))
        .toList();

    final todayIso = _iso(weekDays.first);
    final todaySlots = m.unavailableSlots[todayIso] ?? const <String>[];

    if (offThisWeek.isEmpty && todaySlots.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.event_busy_rounded,
                  size: 16, color: Color(0xFFB45309)),
              const SizedBox(width: 8),
              Text(
                l?.tr('team_detail_unavail_title') ?? 'Indisponibilités',
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF78350F),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (offThisWeek.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                (l?.tr('team_detail_off_this_week') ??
                        'Jours OFF cette semaine : {days}')
                    .replaceAll('{days}', offThisWeek.join(', ')),
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF78350F),
                ),
              ),
            ),
          if (todaySlots.isNotEmpty)
            Text(
              (l?.tr('team_detail_slots_today') ??
                      'Créneaux bloqués aujourd\'hui : {slots}')
                  .replaceAll('{slots}', todaySlots.join(', ')),
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF78350F),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAppointmentSection(
    AppLocalizations? l, {
    required String title,
    required List<AppointmentModel> items,
    required bool showAll,
    required VoidCallback onToggleShowAll,
    required String currency,
    required String emptyLabel,
  }) {
    final visible = showAll ? items : items.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (items.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    '${items.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand700,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                emptyLabel,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondary500,
                ),
              ),
            ),
          ...visible.map((a) => _appointmentRow(a, currency)),
          if (items.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: onToggleShowAll,
                child: Text(showAll
                    ? (l?.tr('common_show_less') ?? 'Voir moins')
                    : (l?.tr('common_show_more') ?? 'Voir tout ({count})')
                        .replaceAll('{count}', '${items.length}')),
              ),
            ),
        ],
      ),
    );
  }

  Widget _appointmentRow(AppointmentModel a, String currency) {
    final date = DateFormat('dd MMM yyyy · HH:mm').format(a.dateTime);
    final statusColor = switch (a.status) {
      'completed' => const Color(0xFF15803D),
      'cancelled' => const Color(0xFFB91C1C),
      'no_show' => const Color(0xFFB91C1C),
      _ => AppColors.brand700,
    };
    final clientLabel = (a.clientName?.isNotEmpty ?? false)
        ? a.clientName!
        : (a.clientPhone ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 6, height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.serviceName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand950,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$date${clientLabel.isNotEmpty ? '  ·  $clientLabel' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Text(
            CurrencyHelper.format(a.price, currency),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.brand950,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOwnerActions(AppLocalizations? l) {
    return Row(
      children: [
        if (widget.onEdit != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onEdit!();
              },
              icon: const Icon(Icons.edit_outlined,
                  size: 16, color: AppColors.brand950),
              label: Text(
                l?.tr('common_edit') ?? 'Modifier',
                style: const TextStyle(
                  color: AppColors.brand950,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: AppColors.secondary200),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        if (widget.onEdit != null && widget.onDelete != null)
          const SizedBox(width: 10),
        if (widget.onDelete != null)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete!();
              },
              icon: const Icon(Icons.delete_outline_rounded,
                  size: 16, color: Color(0xFFB91C1C)),
              label: Text(
                l?.tr('common_delete') ?? 'Supprimer',
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildErrorBlock(AppLocalizations? l) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFB91C1C)),
          const SizedBox(height: 8),
          Text(
            (l?.tr('team_detail_load_error') ??
                    'Erreur de chargement : {error}')
                .replaceAll('{error}', _error ?? ''),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _refresh(bypassCache: true),
            child: Text(l?.tr('common_retry') ?? 'Réessayer'),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    required this.iconBg,
  });
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.secondary500,
            ),
          ),
        ],
      ),
    );
  }
}
