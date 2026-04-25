import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../widgets/member_avatar.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';

class MemberHomeScreen extends ConsumerStatefulWidget {
  const MemberHomeScreen({super.key});

  @override
  ConsumerState<MemberHomeScreen> createState() => _MemberHomeScreenState();
}

class _MemberHomeScreenState extends ConsumerState<MemberHomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _switchProfile() {
    // Reset providers — main.dart reacts and shows TeamProfileSelectorScreen
    ref.read(activeTeamMemberProvider.notifier).state = null;
    ref.read(profileSelectedProvider.notifier).state = false;
  }

  Future<void> _signOut() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('home_logout_title') ?? 'Déconnexion'),
        content: Text(l?.tr('home_logout_message') ?? 'Êtes-vous sûr de vouloir vous déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l?.tr('common_disconnect') ?? 'Déconnecter',
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await ref.read(authServiceProvider).signOut();
    ref.invalidate(authStateProvider);
    ref.invalidate(userModelProvider);
  }

  @override
  Widget build(BuildContext context) {
    final member = ref.watch(activeTeamMemberProvider);
    // If member is null, main.dart will have already swapped the screen.
    if (member == null) return const SizedBox.shrink();

    final salonAsync = ref.watch(ownerSalonProvider);

    final l = AppLocalizations.of(context);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: NestedScrollView(
        headerSliverBuilder: (context, _) => [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            automaticallyImplyLeading: false,
            title: _MemberHeader(member: member),
            actions: [
              // Hide the profile switcher when the user is logged in via an
              // employee code — they have no other profile to switch to.
              if (ref.watch(employeeSessionProvider).value == null) ...[
                GestureDetector(
                  onTap: _switchProfile,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.brand200),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.people_alt_outlined,
                            size: 15, color: AppColors.brand600),
                        const SizedBox(width: 5),
                        Text(
                          l?.tr('member_profiles') ?? 'Profils',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              GestureDetector(
                onTap: _signOut,
                child: Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.secondary200),
                  ),
                  child: const Icon(Icons.power_settings_new_rounded,
                      size: 16, color: AppColors.secondary400),
                ),
              ),
              const SizedBox(width: 12),
            ],
            bottom: TabBar(
              controller: _tabController,
              labelColor: AppColors.brand600,
              unselectedLabelColor: AppColors.secondary400,
              indicatorColor: AppColors.brand600,
              labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              tabs: [
                Tab(text: l?.tr('member_my_appointments_tab') ?? 'Mes RDV'),
                Tab(text: l?.tr('member_all_appointments_tab') ?? 'Tous les RDV'),
                Tab(text: l?.tr('member_unavailability_tab') ?? 'Indispo'),
              ],
            ),
          ),
        ],
        body: salonAsync.when(
          loading: () => TabBarView(
            controller: _tabController,
            children: List.generate(
              3,
              (_) => const Center(
                child:
                    CircularProgressIndicator(color: AppColors.brand500),
              ),
            ),
          ),
          error: (e, _) => TabBarView(
            controller: _tabController,
            children: List.generate(
              3,
              (_) => Center(child: Text((l?.tr('gerant_conges_error') ?? 'Erreur: {error}').replaceAll('{error}', '$e'))),
            ),
          ),
          data: (salon) {
            if (salon == null) {
              return TabBarView(
                controller: _tabController,
                children: List.generate(
                  3,
                  (_) => Center(
                    child: Text(l?.tr('member_salon_not_found') ?? 'Salon introuvable',
                        style:
                            const TextStyle(color: AppColors.secondary400)),
                  ),
                ),
              );
            }
            return TabBarView(
              controller: _tabController,
              children: [
                _MyAppointmentsTab(
                    salon: salon, member: member),
                _AllAppointmentsTab(
                    salonId: salon.id, member: member),
                UnavailabilityTab(
                    salonId: salon.id, member: member),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ─── Member Header ────────────────────────────────────────────────────────────

class _MemberHeader extends StatelessWidget {
  const _MemberHeader({required this.member});
  final TeamMemberModel member;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Row(
      children: [
        MemberAvatar(
          name: member.name,
          photoUrl: member.photoUrl,
          radius: 18,
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.name,
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: member.role == 'gerant'
                    ? const Color(0xFFFFF7ED)
                    : AppColors.brand50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                member.role == 'gerant'
                    ? (l?.tr('selector_manager') ?? 'Gérant(e)')
                    : (l?.tr('selector_employee') ?? 'Employé(e)'),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: member.role == 'gerant'
                      ? const Color(0xFFEA580C)
                      : AppColors.brand600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─── My Appointments Tab ──────────────────────────────────────────────────────

class _MyAppointmentsTab extends ConsumerWidget {
  const _MyAppointmentsTab(
      {required this.salon, required this.member});
  final SalonModel salon;
  final TeamMemberModel member;

  void _showAddSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: _MemberAddAppointmentSheet(
          salon: salon,
          member: member,
          onCreated: () => ref.invalidate(ownerAppointmentsRangeProvider),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentsAsync = ref.watch(ownerAppointmentsRangeProvider);
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        // Period chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _MemberPeriodChips(
            selected: ref.watch(appointmentsPeriodProvider),
            onSelect: (p) =>
                ref.read(appointmentsPeriodProvider.notifier).state = p,
          ),
        ),
        // Add button row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Align(
            alignment: Alignment.center,
            child: GestureDetector(
              onTap: () => _showAddSheet(context, ref),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  border: Border.all(color: AppColors.brand200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.add_rounded,
                    size: 20, color: AppColors.brand600),
              ),
            ),
          ),
        ),
        // Appointments list (filtered to this member)
        Expanded(
          child: appointmentsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.brand500),
            ),
            error: (e, _) => Center(
                child: Text((l?.tr('gerant_conges_error') ?? 'Erreur: {error}')
                    .replaceAll('{error}', '$e'))),
            data: (all) {
              final appointments = all
                  .where((a) => a.assignedMemberId == member.id)
                  .toList();
              if (appointments.isEmpty) {
                return _EmptyAppointments(
                  message: l?.tr('member_no_appointments_assigned') ??
                      'Aucun rendez-vous vous est assigné',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: appointments.length,
                itemBuilder: (ctx, i) =>
                    _MemberAppointmentCard(appointment: appointments[i]),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── All Appointments Tab ─────────────────────────────────────────────────────

class _AllAppointmentsTab extends ConsumerWidget {
  const _AllAppointmentsTab(
      {required this.salonId, required this.member});
  final String salonId;
  final TeamMemberModel member;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appointmentsAsync = ref.watch(ownerAppointmentsRangeProvider);
    final l = AppLocalizations.of(context);

    return Column(
      children: [
        // Period chips
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: _MemberPeriodChips(
            selected: ref.watch(appointmentsPeriodProvider),
            onSelect: (p) =>
                ref.read(appointmentsPeriodProvider.notifier).state = p,
          ),
        ),
        Expanded(
          child: appointmentsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: AppColors.brand500),
            ),
            error: (e, _) => Center(
                child: Text((l?.tr('gerant_conges_error') ?? 'Erreur: {error}')
                    .replaceAll('{error}', '$e'))),
            data: (appointments) {
              if (appointments.isEmpty) {
                return _EmptyAppointments(
                  message: l?.tr('member_no_appointments_salon') ??
                      'Aucun rendez-vous dans le salon',
                );
              }
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: appointments.length,
                itemBuilder: (ctx, i) => _MemberAppointmentCard(
                  appointment: appointments[i],
                  member: member,
                  onSelfAssign: () =>
                      ref.invalidate(ownerAppointmentsRangeProvider),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ─── Appointment Card ─────────────────────────────────────────────────────────

class _MemberAppointmentCard extends StatefulWidget {
  const _MemberAppointmentCard({
    required this.appointment,
    this.member,
    this.onSelfAssign,
  });
  final AppointmentModel appointment;
  final TeamMemberModel? member;
  final VoidCallback? onSelfAssign;

  @override
  State<_MemberAppointmentCard> createState() =>
      _MemberAppointmentCardState();
}

class _MemberAppointmentCardState extends State<_MemberAppointmentCard> {
  String _clientName = '…';
  bool _assigning = false;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    final storedName = a.clientName?.trim();
    if (storedName != null && storedName.isNotEmpty) {
      _clientName = storedName;
      return;
    }
    if (a.clientId == 'walk-in') {
      _clientName = 'Client sans compte'; // fallback, localized in build
      return;
    }
    DatabaseService().getClientName(a.clientId).then((name) {
      if (mounted) setState(() => _clientName = name);
    });
  }

  Future<void> _selfAssign() async {
    final m = widget.member;
    if (m == null) return;
    setState(() => _assigning = true);
    try {
      await DatabaseService()
          .assignAppointment(widget.appointment.id, m.id, m.name);
      widget.onSelfAssign?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erreur: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = widget.appointment;
    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr = DateFormat('EEE d MMM', 'fr_FR').format(a.dateTime);

    final (statusLabel, statusBg, statusFg) = switch (a.status) {
      'completed' => (
          l?.tr('appointments_status_completed') ?? 'Terminé',
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A)
        ),
      'cancelled' => (
          l?.tr('appointments_status_cancelled') ?? 'Annulé',
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626)
        ),
      _ => (l?.tr('appointments_status_upcoming') ?? 'À venir', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
    };

    final canAssign = widget.member != null &&
        a.status == 'upcoming' &&
        a.assignedMemberId == null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Time column
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                timeStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.brand700,
                ),
              ),
              Text(
                dateStr,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.secondary400,
                ),
              ),
            ],
          ),
          Container(
              width: 1,
              height: 40,
              color: AppColors.secondary100,
              margin: const EdgeInsets.symmetric(horizontal: 14)),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.serviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.brand950,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (a.selectedOptions != null && a.selectedOptions!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(a.selectedOptions!.join(' · '),
                      style: const TextStyle(fontSize: 10, color: Colors.purple), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                if (a.selectedDesignUrl != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(a.selectedDesignThumbnail ?? a.selectedDesignUrl!, height: 40, width: 60, fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  _clientName,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary500,
                  ),
                ),
                if (a.assignedMemberName != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.person_pin_outlined,
                          size: 12, color: AppColors.brand600),
                      const SizedBox(width: 3),
                      Text(
                        a.assignedMemberName!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.brand600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Right
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
              if (canAssign) ...[
                const SizedBox(height: 6),
                _assigning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: AppColors.brand600, strokeWidth: 2),
                      )
                    : GestureDetector(
                        onTap: _selfAssign,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brand50,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: AppColors.brand200),
                          ),
                          child: Text(
                            l?.tr('member_self_assign') ?? 'S\'assigner',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand600,
                            ),
                          ),
                        ),
                      ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyAppointments extends StatelessWidget {
  const _EmptyAppointments({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.calendar_month_outlined,
              size: 48, color: AppColors.secondary200),
          const SizedBox(height: 16),
          Text(
            message,
            style: const TextStyle(
              color: AppColors.secondary400,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Unavailability / Indisponibilités Tab ───────────────────────────────────

class UnavailabilityTab extends ConsumerStatefulWidget {
  const UnavailabilityTab(
      {super.key, required this.salonId, required this.member});
  final String salonId;
  final TeamMemberModel member;

  @override
  ConsumerState<UnavailabilityTab> createState() => _UnavailabilityTabState();
}

class _UnavailabilityTabState extends ConsumerState<UnavailabilityTab>
    with AutomaticKeepAliveClientMixin {
  late DateTime _focusedMonth;
  late Set<String> _unavailable; // ISO date strings "yyyy-MM-dd"
  late Map<String, List<String>> _unavailableSlots; // {"2026-03-10": ["09:00-10:00"]}
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month);
    _unavailable = Set<String>.from(widget.member.unavailableDates);
    _unavailableSlots = Map<String, List<String>>.from(
      widget.member.unavailableSlots.map((k, v) => MapEntry(k, List<String>.from(v))),
    );
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _todayKey() => _isoDate(DateTime.now());

  bool get _isTodayFullyUnavailable => _unavailable.contains(_todayKey());

  late List<int> _recurringDaysOff = List<int>.from(widget.member.recurringDaysOff);

  Widget _buildRecurringDaysOff() {
    final l = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).languageCode;
    final dayLabels = locale == 'fr'
        ? ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.event_repeat_rounded, size: 18, color: AppColors.brand600),
              const SizedBox(width: 8),
              Text(
                l?.tr('unavailability_recurring_days') ?? 'Jours de repos hebdomadaires',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.brand950),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('unavailability_recurring_subtitle') ?? 'Sélectionnez vos jours de repos fixes chaque semaine',
            style: TextStyle(fontSize: 11, color: AppColors.secondary400),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(7, (i) {
              final weekday = i + 1; // 1=Mon ... 7=Sun
              final isOff = _recurringDaysOff.contains(weekday);
              return GestureDetector(
                onTap: _saving ? null : () async {
                  setState(() {
                    if (isOff) {
                      _recurringDaysOff.remove(weekday);
                    } else {
                      _recurringDaysOff.add(weekday);
                    }
                  });
                  // Save to Firestore
                  try {
                    await FirebaseFirestore.instance
                        .collection('salons')
                        .doc(widget.salonId)
                        .collection('teamMembers')
                        .doc(widget.member.id)
                        .update({'recurringDaysOff': _recurringDaysOff});
                    _syncProvider(null, null, recurringDaysOff: List<int>.from(_recurringDaysOff));
                  } catch (e) {
                    debugPrint('Error saving recurring days off: $e');
                  }
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isOff ? const Color(0xFFFEE2E2) : AppColors.secondary50,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isOff ? const Color(0xFFFCA5A5) : AppColors.secondary200,
                      width: isOff ? 1.5 : 1,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    dayLabels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isOff ? const Color(0xFFDC2626) : AppColors.secondary500,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  /// Generate hour labels from 8h to 22h
  List<int> get _morningHours => [8, 9, 10, 11, 12];
  List<int> get _afternoonHours => [13, 14, 15, 16, 17, 18, 19, 20, 21];

  bool _isHourUnavailable(int hour) {
    final key = _todayKey();
    final slots = _unavailableSlots[key] ?? [];
    final hStr = '${hour.toString().padLeft(2, '0')}:00-${(hour + 1).toString().padLeft(2, '0')}:00';
    return slots.contains(hStr);
  }

  Future<void> _toggleHour(int hour) async {
    final key = _todayKey();
    final hStr = '${hour.toString().padLeft(2, '0')}:00-${(hour + 1).toString().padLeft(2, '0')}:00';
    final updatedSlots = Map<String, List<String>>.from(_unavailableSlots);
    final list = List<String>.from(updatedSlots[key] ?? []);

    if (list.contains(hStr)) {
      list.remove(hStr);
    } else {
      // Check for appointments in this hour
      final now = DateTime.now();
      final slotStart = DateTime(now.year, now.month, now.day, hour, 0);
      final slotEnd = DateTime(now.year, now.month, now.day, hour + 1, 0);
      final appointments = await DatabaseService()
          .getAppointmentsForMemberOnDate(
              widget.salonId, widget.member.id, slotStart, slotEnd);
      if (appointments.isNotEmpty && mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (l?.tr('appointments_error_appointment_at_hour') ?? 'Impossible : vous avez un rendez-vous à {hour}h').replaceAll('{hour}', '$hour'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }
      list.add(hStr);
      list.sort();
    }

    if (list.isEmpty) {
      updatedSlots.remove(key);
    } else {
      updatedSlots[key] = list;
    }

    setState(() {
      _unavailableSlots = updatedSlots;
      _saving = true;
    });
    try {
      await DatabaseService()
          .setUnavailableSlots(widget.salonId, widget.member.id, updatedSlots);
      _syncProvider(null, updatedSlots);
    } catch (_) {
      _revertState();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleDay(DateTime day) async {
    final key = _isoDate(day);
    final updated = Set<String>.from(_unavailable);
    if (updated.contains(key)) {
      updated.remove(key);
    } else {
      // Check if member has appointments on this day before marking unavailable
      final dayStart = DateTime(day.year, day.month, day.day);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final appointments = await DatabaseService()
          .getAppointmentsForMemberOnDate(
              widget.salonId, widget.member.id, dayStart, dayEnd);
      if (appointments.isNotEmpty && mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (l?.tr('appointments_error_appointments_on_day') ?? 'Impossible : vous avez {count} rendez-vous ce jour').replaceAll('{count}', '${appointments.length}'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            backgroundColor: const Color(0xFFDC2626),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        return;
      }
      updated.add(key);
    }
    // Clear hourly slots for this day when toggling full day
    final updatedSlots = Map<String, List<String>>.from(_unavailableSlots);
    updatedSlots.remove(key);
    setState(() {
      _unavailable = updated;
      _unavailableSlots = updatedSlots;
      _saving = true;
    });
    try {
      await Future.wait([
        DatabaseService().setUnavailableDates(
            widget.salonId, widget.member.id, updated.toList()),
        DatabaseService().setUnavailableSlots(
            widget.salonId, widget.member.id, updatedSlots),
      ]);
      _syncProvider(updated, updatedSlots);
    } catch (_) {
      _revertState();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _syncProvider(Set<String>? dates, Map<String, List<String>>? slots, {List<int>? recurringDaysOff}) {
    if (!mounted) return;
    final current = ref.read(activeTeamMemberProvider);
    if (current != null) {
      ref.read(activeTeamMemberProvider.notifier).state = current.copyWith(
        unavailableDates: dates?.toList() ?? current.unavailableDates,
        unavailableSlots: slots ?? current.unavailableSlots,
        recurringDaysOff: recurringDaysOff ?? current.recurringDaysOff,
      );
    }
  }

  void _revertState() {
    if (mounted) {
      setState(() {
        _unavailable = Set<String>.from(widget.member.unavailableDates);
        _unavailableSlots = Map<String, List<String>>.from(
          widget.member.unavailableSlots.map((k, v) => MapEntry(k, List<String>.from(v))),
        );
      });
    }
  }

  void _prevMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month - 1);
      });

  void _nextMonth() => setState(() {
        _focusedMonth =
            DateTime(_focusedMonth.year, _focusedMonth.month + 1);
      });

  Widget _buildHourChip(int hour) {
    final isUnavail = _isHourUnavailable(hour);
    final now = DateTime.now();
    final isPast = hour <= now.hour;
    return GestureDetector(
      onTap: (isPast || _isTodayFullyUnavailable) ? null : () => _toggleHour(hour),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isUnavail
              ? const Color(0xFFDC2626)
              : isPast
                  ? AppColors.secondary100
                  : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isUnavail
                ? const Color(0xFFDC2626)
                : isPast
                    ? AppColors.secondary200
                    : AppColors.secondary200,
          ),
        ),
        child: Text(
          '${hour.toString().padLeft(2, '0')}h',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: isUnavail
                ? Colors.white
                : isPast
                    ? AppColors.secondary300
                    : AppColors.brand950,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final loc = Localizations.localeOf(context).languageCode == 'fr' ? 'fr_FR' : 'en_US';
    final monthLabel =
        DateFormat('MMMM yyyy', loc).format(_focusedMonth);
    final unavailableThisMonth = _unavailable
        .where((d) {
          final dt = DateTime.parse(d);
          return dt.year == _focusedMonth.year &&
              dt.month == _focusedMonth.month;
        })
        .length;

    // Build grid of days
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final startOffset = (firstDay.weekday - 1) % 7;
    final daysInMonth =
        DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Info banner
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 18, color: Color(0xFFEA580C)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    AppLocalizations.of(context)?.tr('unavailability_info') ?? 'Marquez vos indisponibilités par heure (aujourd\'hui) ou par jour entier (calendrier).',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Recurring days off ──
          _buildRecurringDaysOff(),
          const SizedBox(height: 16),

          // ── Today's hourly unavailability ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.schedule_rounded,
                        size: 18, color: AppColors.brand600),
                    const SizedBox(width: 8),
                    Text(
                      (AppLocalizations.of(context)?.tr('unavailability_today') ?? "Aujourd'hui — {date}").replaceAll('{date}', DateFormat('d MMMM', Localizations.localeOf(context).languageCode == 'fr' ? 'fr_FR' : 'en_US').format(DateTime.now())),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.brand950,
                      ),
                    ),
                    if (_saving) ...[
                      const SizedBox(width: 8),
                      const SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.brand500),
                      ),
                    ],
                  ],
                ),
                if (_isTodayFullyUnavailable) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.block_rounded, size: 16, color: Color(0xFFDC2626)),
                        const SizedBox(width: 8),
                        Text(
                          AppLocalizations.of(context)?.tr('unavailability_full_day') ?? 'Journée entière indisponible',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 14),
                  Text(
                    AppLocalizations.of(context)?.tr('unavailability_morning') ?? 'Matin',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: _morningHours.map(_buildHourChip).toList(),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    AppLocalizations.of(context)?.tr('unavailability_afternoon') ?? 'Après-midi',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _afternoonHours.map((h) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildHourChip(h),
                      )).toList(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Calendar for full-day unavailability ──
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.secondary100),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Month navigation
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      onPressed: _prevMonth,
                      icon: const Icon(Icons.chevron_left_rounded),
                      color: AppColors.secondary500,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    Text(
                      monthLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.brand950,
                      ),
                    ),
                    IconButton(
                      onPressed: _nextMonth,
                      icon: const Icon(Icons.chevron_right_rounded),
                      color: AppColors.secondary500,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Weekday headers
                Row(
                  children: (Localizations.localeOf(context).languageCode == 'fr'
                    ? ['L', 'M', 'M', 'J', 'V', 'S', 'D']
                    : ['M', 'T', 'W', 'T', 'F', 'S', 'S'])
                      .map((d) => Expanded(
                            child: Center(
                              child: Text(
                                d,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.secondary400,
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 8),

                // Days grid
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7,
                    mainAxisSpacing: 6,
                    crossAxisSpacing: 4,
                    childAspectRatio: 1,
                  ),
                  itemCount: startOffset + daysInMonth,
                  itemBuilder: (ctx, index) {
                    if (index < startOffset) return const SizedBox();
                    final day = index - startOffset + 1;
                    final date = DateTime(
                        _focusedMonth.year, _focusedMonth.month, day);
                    final key = _isoDate(date);
                    final isUnavailable = _unavailable.contains(key);
                    final isToday = _todayKey() == key;
                    final isPast = date.isBefore(DateTime(
                        DateTime.now().year,
                        DateTime.now().month,
                        DateTime.now().day));

                    return GestureDetector(
                      onTap: isPast ? null : () => _toggleDay(date),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: isUnavailable
                              ? const Color(0xFFDC2626)
                              : isPast
                                  ? AppColors.secondary50
                                  : isToday
                                      ? AppColors.brand50
                                      : Colors.transparent,
                          shape: BoxShape.circle,
                          border: isToday && !isUnavailable
                              ? Border.all(
                                  color: AppColors.brand400, width: 1.5)
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            '$day',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isUnavailable
                                  ? Colors.white
                                  : isPast
                                      ? AppColors.secondary300
                                      : AppColors.brand950,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Summary
          if (unavailableThisMonth > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.event_busy_outlined,
                      size: 18, color: Color(0xFFDC2626)),
                  const SizedBox(width: 10),
                  Text(
                    (AppLocalizations.of(context)?.tr('unavailability_days_count') ?? '{count} jour{plural} indisponible{plural} ce mois-ci')
                        .replaceAll('{count}', '$unavailableThisMonth')
                        .replaceAll('{plural}', unavailableThisMonth > 1 ? 's' : ''),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF991B1B),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 16),

          // Legend
          Builder(builder: (context) {
            final l = AppLocalizations.of(context);
            return Row(
              children: [
                _LegendDot(color: const Color(0xFFDC2626), label: l?.tr('unavailability_legend_unavailable') ?? 'Indisponible'),
                const SizedBox(width: 16),
                _LegendDot(color: AppColors.brand50, label: l?.tr('unavailability_legend_today') ?? "Aujourd'hui", border: AppColors.brand400),
                const SizedBox(width: 16),
                _LegendDot(color: AppColors.secondary50, label: l?.tr('unavailability_legend_past') ?? 'Passé'),
              ],
            );
          }),
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label, this.border});
  final Color color;
  final String label;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 14,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: border != null
                ? Border.all(color: border!, width: 1.5)
                : null,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.secondary500,
          ),
        ),
      ],
    );
  }
}

// ─── Member Add Appointment Sheet ────────────────────────────────────────────

class _MemberAddAppointmentSheet extends StatefulWidget {
  const _MemberAddAppointmentSheet({
    required this.salon,
    required this.member,
    required this.onCreated,
  });
  final SalonModel salon;
  final TeamMemberModel member;
  final VoidCallback onCreated;

  @override
  State<_MemberAddAppointmentSheet> createState() =>
      _MemberAddAppointmentSheetState();
}

class _MemberAddAppointmentSheetState
    extends State<_MemberAddAppointmentSheet> {
  static const _dayKeys = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];

  final _clientNameCtrl = TextEditingController();
  final List<Map<String, dynamic>> _selectedServices = [];
  Map<String, dynamic>? _selectedService;
  Map<String, dynamic>? _selectedPack;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;
  List<AppointmentModel> _existingAppointments = [];
  String? _activeServiceCategory;
  bool _showAllServices = false;

  bool get _isMultiService => _selectedServices.length > 1;

  /// Services assigned to this member only.
  List<Map<String, dynamic>> get _memberServices {
    final assigned = widget.member.assignedServiceNames;
    return widget.salon.services
        .where((s) => s['visibleTo'] == null && assigned.contains(s['name'] as String? ?? ''))
        .cast<Map<String, dynamic>>()
        .toList();
  }

  List<String> get _serviceCategories {
    final seen = <String>{};
    final cats = <String>[];
    for (final s in _memberServices) {
      final cat = s['category'] as String?;
      if (cat != null && cat.isNotEmpty && seen.add(cat)) cats.add(cat);
    }
    return cats;
  }

  List<Map<String, dynamic>> get _filteredServices {
    final all = _activeServiceCategory == null
        ? _memberServices
        : _memberServices.where((s) => s['category'] == _activeServiceCategory).toList();
    if (_selectedServices.isNotEmpty) {
      all.sort((a, b) {
        final aName = a['name'] ?? a['title'] ?? '';
        final bName = b['name'] ?? b['title'] ?? '';
        final aSelected = _selectedServices.any((s) => (s['name'] ?? s['title'] ?? '') == aName) ? 0 : 1;
        final bSelected = _selectedServices.any((s) => (s['name'] ?? s['title'] ?? '') == bName) ? 0 : 1;
        return aSelected.compareTo(bSelected);
      });
    }
    return all;
  }

  int get _totalDuration => _selectedServices.fold<int>(
    0, (acc, s) => acc + ((s['duration'] as int?) ?? 30),
  );

  double get _totalPrice => _selectedServices.fold<double>(
    0.0, (acc, s) => acc + ((s['price'] as num?)?.toDouble() ?? 0.0),
  );

  void _toggleService(Map<String, dynamic> service) {
    final svcName = service['name'] ?? service['title'] ?? '';
    final isSelected = _selectedServices.any(
      (s) => (s['name'] ?? s['title'] ?? '') == svcName,
    );
    if (!isSelected && _selectedServices.length >= 5) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('booking_max_services') ??
              'Maximum 5 prestations par réservation. Merci de créer une seconde réservation pour plus.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }
    setState(() {
      if (isSelected) {
        _selectedServices.removeWhere((s) => (s['name'] ?? s['title'] ?? '') == svcName);
      } else {
        _selectedServices.add(service);
        _selectedPack = null;
      }
      _selectedService = _selectedServices.isNotEmpty ? _selectedServices.first : null;
    });
  }

  /// Packs where ALL services are assigned to this member.
  List<Map<String, dynamic>> get _memberPacks {
    final assigned = widget.member.assignedServiceNames;
    return widget.salon.servicePacks.where((pack) {
      final packServices = List<String>.from(pack['services'] ?? []);
      return packServices.isNotEmpty && packServices.every((s) => assigned.contains(s));
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _snapTimeToOpenHours();
    _loadAppointments();
  }

  Future<void> _loadAppointments() async {
    try {
      final appts = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);
      if (mounted) setState(() => _existingAppointments = appts);
    } catch (_) {}
  }

  int get _effectiveDuration {
    if (_selectedPack != null) {
      final packSvcNames = List<String>.from(_selectedPack!['services'] ?? []);
      int total = 0;
      for (final sName in packSvcNames) {
        final svc = widget.salon.services.cast<Map<String, dynamic>>().firstWhere(
          (s) => (s['name'] ?? s['title']) == sName,
          orElse: () => <String, dynamic>{},
        );
        total += ((svc['duration'] ?? 30) as int);
      }
      return total;
    }
    if (_selectedServices.length >= 2) return _totalDuration;
    return (_selectedService?['duration'] as int?) ?? 30;
  }

  bool _isSlotBlocked(String timeStr) {
    if (_selectedService == null && _selectedServices.isEmpty) return false;
    final parts = timeStr.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final duration = _effectiveDuration;
    final slotStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, h, m);
    final slotEnd = slotStart.add(Duration(minutes: duration));

    // Member unavailable (full day)
    if (_isMemberUnavailable(_selectedDate)) return true;

    // Member unavailable (time slot)
    if (_isMemberUnavailableAtTime(_selectedDate, TimeOfDay(hour: h, minute: m), duration)) return true;

    // Existing appointments
    for (final appt in _existingAppointments) {
      if (appt.assignedMemberId != widget.member.id) continue;
      final apptStart = appt.dateTime.toUtc();
      final apptEnd = apptStart.add(Duration(minutes: appt.durationMinutes));
      if (slotStart.toUtc().isBefore(apptEnd) && slotEnd.toUtc().isAfter(apptStart)) return true;
    }
    return false;
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _getHoursForDate(DateTime date) {
    final dayKey = _dayKeys[date.weekday - 1];
    return widget.salon.workingHours[dayKey] as Map<String, dynamic>?;
  }

  bool _isDayOpen(DateTime date) {
    final data = _getHoursForDate(date);
    return data?['isOpen'] == true;
  }

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool _isMemberUnavailable(DateTime date) {
    return widget.member.unavailableDates.contains(_isoDate(date));
  }

  bool _isMemberUnavailableAtTime(DateTime date, TimeOfDay time, int durationMin) {
    final iso = _isoDate(date);
    final slots = widget.member.unavailableSlots[iso] ?? [];
    if (slots.isEmpty) return false;
    final startMin = time.hour * 60 + time.minute;
    final endMin = startMin + durationMin;
    for (final slot in slots) {
      final parts = slot.split('-');
      if (parts.length != 2) continue;
      final sMin = _timeStrToMin(parts[0]);
      final eMin = _timeStrToMin(parts[1]);
      if (startMin < eMin && endMin > sMin) return true;
    }
    return false;
  }

  int _timeStrToMin(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  void _snapTimeToOpenHours() {
    final data = _getHoursForDate(_selectedDate);
    if (data == null || data['isOpen'] != true) return;
    final open = _parseTime(data['open'] as String);
    final close = _parseTime(data['close'] as String);
    final t = _selectedTime;
    final tMin = t.hour * 60 + t.minute;
    final openMin = open.hour * 60 + open.minute;
    final closeMin = close.hour * 60 + close.minute;
    if (tMin < openMin || tMin >= closeMin) {
      _selectedTime = open;
    }
  }

  List<String> _generateTimeSlots() {
    final data = _getHoursForDate(_selectedDate);
    if (data == null || data['isOpen'] != true) return [];
    final open = _parseTime(data['open'] as String);
    final close = _parseTime(data['close'] as String);
    final openMin = open.hour * 60 + open.minute;
    final closeMin = close.hour * 60 + close.minute;
    final slots = <String>[];
    final now = DateTime.now();
    final isToday = _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final nowMin = now.hour * 60 + now.minute;
    for (int m = openMin; m < closeMin; m += 30) {
      if (isToday && m <= nowMin) continue;
      final h = m ~/ 60;
      final mm = m % 60;
      slots.add(
          '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
    }
    return slots;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        if (!_isDayOpen(date)) return false;
        if (_isMemberUnavailable(date)) return false;
        return true;
      },
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: AppColors.brand600,
            onPrimary: Colors.white,
            surface: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _snapTimeToOpenHours();
      });
      _loadAppointments();
    }
  }

  Future<void> _submit() async {
    final clientName = _clientNameCtrl.text.trim();
    final l = AppLocalizations.of(context);
    if (clientName.isEmpty) {
      _showError(l?.tr('appointments_error_client_name') ?? 'Veuillez entrer le nom du client');
      return;
    }
    if (_selectedService == null && _selectedServices.isEmpty) {
      _showError(l?.tr('appointments_error_service') ?? 'Veuillez sélectionner un service');
      return;
    }
    if (_isMemberUnavailable(_selectedDate)) {
      _showError(l?.tr('member_add_unavailable_day') ?? 'Vous êtes indisponible ce jour-là');
      return;
    }
    if (!_isDayOpen(_selectedDate)) {
      _showError(l?.tr('appointments_error_closed') ?? 'Le salon est fermé ce jour-là');
      return;
    }

    // Check if the selected time falls within an unavailable slot
    final duration = _effectiveDuration;
    if (_isMemberUnavailableAtTime(_selectedDate, _selectedTime, duration)) {
      _showError(l?.tr('member_add_unavailable_slot') ?? 'Vous êtes indisponible sur ce créneau horaire');
      return;
    }

    setState(() => _loading = true);
    try {
      final dateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );
      // Double-booking check
      final existing = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);
      final newStart = dateTime;
      final newEnd = dateTime.add(Duration(minutes: duration));
      final conflict = existing.where((a) {
        if (a.assignedMemberId != widget.member.id) return false;
        final aEnd = a.dateTime.add(Duration(minutes: a.durationMinutes));
        return newStart.isBefore(aEnd) && newEnd.isAfter(a.dateTime);
      }).firstOrNull;
      if (conflict != null) {
        final conflictTime =
            '${conflict.dateTime.hour.toString().padLeft(2, '0')}:${conflict.dateTime.minute.toString().padLeft(2, '0')}';
        if (mounted) {
          _showError((l?.tr('member_add_conflict') ?? 'Vous avez déjà un RDV à {time}').replaceAll('{time}', conflictTime));
          setState(() => _loading = false);
        }
        return;
      }

      // Pack mode OR multi-service mode: create one appointment per service, chained.
      // All chained appointments assigned to the logged-in member.
      if (_selectedPack != null || _isMultiService) {
        final List<Map<String, dynamic>> chain;
        if (_selectedPack != null) {
          final packSvcNames = List<String>.from(_selectedPack!['services'] ?? []);
          chain = packSvcNames.map((sName) {
            return widget.salon.services.cast<Map<String, dynamic>>().firstWhere(
              (s) => (s['name'] ?? s['title']) == sName,
              orElse: () => <String, dynamic>{'name': sName, 'duration': 30, 'price': 0},
            );
          }).toList();
        } else {
          chain = _selectedServices;
        }
        var cursor = dateTime;
        for (final svc in chain) {
          final sName = svc['name'] as String? ?? 'Service';
          final svcDur = (svc['duration'] as int?) ?? 30;
          await DatabaseService().createAppointment(AppointmentModel(
            id: const Uuid().v4(),
            clientId: 'walk-in',
            salonId: widget.salon.id,
            salonName: widget.salon.name,
            serviceName: sName,
            price: (svc['price'] as num?)?.toDouble() ?? 0.0,
            dateTime: cursor,
            status: 'upcoming',
            createdAt: DateTime.now(),
            durationMinutes: svcDur,
            clientName: clientName,
            assignedMemberId: widget.member.id,
            assignedMemberName: widget.member.name,
          ));
          cursor = cursor.add(Duration(minutes: svcDur));
        }
      } else {
        final serviceName = _selectedService!['name'] as String? ?? 'Service';
        final price = (_selectedService!['price'] as num?)?.toDouble() ?? 0.0;
        await DatabaseService().createAppointment(AppointmentModel(
          id: const Uuid().v4(),
          clientId: 'walk-in',
          salonId: widget.salon.id,
          salonName: widget.salon.name,
          serviceName: serviceName,
          price: price,
          dateTime: dateTime,
          status: 'upcoming',
          createdAt: DateTime.now(),
          durationMinutes: duration,
          clientName: clientName,
          assignedMemberId: widget.member.id,
          assignedMemberName: widget.member.name,
        ));
      }
      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l?.tr('appointments_created_success') ?? 'RDV créé avec succès'),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) _showError((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.redAccent),
    );
  }

  Widget _buildServicePicker(AppLocalizations? l) {
    final categories = _serviceCategories;
    final filtered = _filteredServices;
    final visibleServices = _showAllServices ? filtered : filtered.take(4).toList();
    final packs = _memberPacks;
    final showPacks = packs.isNotEmpty &&
        _activeServiceCategory == null &&
        _selectedServices.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (categories.isNotEmpty) ...[
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final isAll = i == 0;
                final cat = isAll ? null : categories[i - 1];
                final active = _activeServiceCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() {
                    _activeServiceCategory = cat;
                    _showAllServices = false;
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: active ? AppColors.brand600 : Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: active ? AppColors.brand600 : AppColors.secondary200,
                      ),
                    ),
                    child: Text(
                      isAll ? (l?.tr('booking_all') ?? 'Tous') : cat!,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: active ? Colors.white : AppColors.brand800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (showPacks) ...[
          ...packs.map((pack) => _buildPackTile(pack, l)),
          const SizedBox(height: 8),
        ],
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              l?.tr('appointments_no_services') ?? 'Aucun service dans cette catégorie',
              style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
            ),
          )
        else
          ...visibleServices.map((svc) => _buildServiceTile(svc, l)),
        if (filtered.length > 4)
          Center(
            child: TextButton(
              onPressed: () => setState(() => _showAllServices = !_showAllServices),
              child: Text(
                _showAllServices
                    ? (l?.tr('booking_see_less') ?? 'Voir moins')
                    : (l?.tr('booking_see_all_services') ?? 'Voir tous les services ({count})')
                        .replaceAll('{count}', filtered.length.toString()),
                style: const TextStyle(
                  color: AppColors.brand700,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
        if (_selectedServices.length >= 2)
          Container(
            margin: const EdgeInsets.only(top: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, size: 16, color: AppColors.brand600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedServices.length} services · ${_totalDuration}min · ${CurrencyHelper.format(_totalPrice, widget.salon.currency)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand800,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildServiceTile(Map<String, dynamic> svc, AppLocalizations? l) {
    final name = svc['name'] as String? ?? svc['title'] as String? ?? '';
    final price = (svc['price'] as num?)?.toDouble() ?? 0.0;
    final duration = (svc['duration'] as int?) ?? 30;
    final selected = _selectedServices.any(
      (s) => (s['name'] ?? s['title'] ?? '') == name,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => _toggleService(svc),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand50 : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand400 : AppColors.secondary200,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: selected ? AppColors.brand600 : Colors.white,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: selected ? AppColors.brand600 : AppColors.secondary300,
                    width: 2,
                  ),
                ),
                child: selected
                    ? const Icon(Icons.check, color: Colors.white, size: 14)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950,
                        )),
                    const SizedBox(height: 2),
                    Text('${duration}min · ${CurrencyHelper.format(price, widget.salon.currency)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                        )),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPackTile(Map<String, dynamic> pack, AppLocalizations? l) {
    final name = pack['name'] as String? ?? 'Pack';
    final price = (pack['price'] as num?)?.toDouble() ?? 0.0;
    final packServices = List<String>.from(pack['services'] ?? []);
    final services = widget.salon.services.cast<Map<String, dynamic>>();
    int totalDur = 0;
    for (final sName in packServices) {
      final svc = services.firstWhere(
        (s) => (s['name'] ?? s['title']) == sName,
        orElse: () => <String, dynamic>{},
      );
      totalDur += ((svc['duration'] ?? 30) as int);
    }
    final selected = _selectedPack == pack;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () {
          setState(() {
            if (selected) {
              _selectedPack = null;
              _selectedService = null;
            } else {
              _selectedPack = pack;
              _selectedServices.clear();
              if (packServices.isNotEmpty) {
                _selectedService = services.firstWhere(
                  (s) => (s['name'] ?? s['title']) == packServices.first,
                  orElse: () => services.first,
                );
              }
            }
          });
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand100 : AppColors.brand50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.brand200,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              const Text('📦', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand950,
                        )),
                    const SizedBox(height: 2),
                    Text('${packServices.length} services · ${totalDur}min · ${CurrencyHelper.format(price, widget.salon.currency)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.brand700,
                        )),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: AppColors.brand600, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final services = _memberServices;
    final dateStr =
        DateFormat('EEE d MMM yyyy', 'fr_FR').format(_selectedDate);
    final timeStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

    final l = AppLocalizations.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l?.tr('appointments_new_title') ?? 'Nouveau rendez-vous',
              style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              (l?.tr('member_add_subtitle') ?? 'Rendez-vous assigné à {name}').replaceAll('{name}', widget.member.name),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.secondary400),
            ),
            const SizedBox(height: 20),

            // Client name
            _label(l?.tr('appointments_client_name') ?? 'Nom du client *'),
            const SizedBox(height: 6),
            TextField(
              controller: _clientNameCtrl,
              style:
                  const TextStyle(fontSize: 14, color: AppColors.brand950),
              decoration: _inputDecoration(l?.tr('appointments_client_name_hint') ?? 'ex. Mohamed Alami'),
            ),
            const SizedBox(height: 16),

            // Service selection (only member's assigned services)
            _label(l?.tr('appointments_service_label') ?? 'Service *'),
            const SizedBox(height: 6),
            if (services.isEmpty)
              Text(
                l?.tr('member_add_no_services') ?? 'Aucun service assigné',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.secondary400),
              )
            else
              _buildServicePicker(l),
            const SizedBox(height: 16),

            // Date
            _label(l?.tr('appointments_date_label') ?? 'Date *'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  border: Border.all(color: AppColors.secondary200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.secondary400),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateStr,
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.brand950),
                      ),
                    ),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 18, color: AppColors.secondary400),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Time slots
            _label(l?.tr('appointments_time_label') ?? 'Heure *'),
            const SizedBox(height: 6),
            Builder(builder: (_) {
              if (_isMemberUnavailable(_selectedDate)) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.event_busy_outlined,
                          size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l?.tr('member_add_unavailable_day') ?? 'Vous êtes indisponible ce jour-là',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }
              if (!_isDayOpen(_selectedDate)) {
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded,
                          size: 16, color: Color(0xFFDC2626)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l?.tr('appointments_salon_closed') ?? 'Le salon est fermé ce jour-là',
                          style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final slots = _generateTimeSlots();
              final morning = slots
                  .where((t) => int.parse(t.split(':')[0]) < 12)
                  .toList();
              final afternoon = slots
                  .where((t) => int.parse(t.split(':')[0]) >= 12)
                  .toList();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (morning.isNotEmpty) ...[
                    _timeSlotSection(
                      label: l?.tr('appointments_morning') ?? 'Matin',
                      icon: Icons.wb_sunny_outlined,
                      slots: morning,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (afternoon.isNotEmpty)
                    _timeSlotSection(
                      label: l?.tr('appointments_afternoon') ?? 'Après-midi',
                      icon: Icons.wb_twilight_outlined,
                      slots: afternoon,
                    ),
                ],
              );
            }),

            // Summary
            if (_selectedService != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brand100),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l?.tr('appointments_summary') ?? 'Résumé',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand700)),
                    const SizedBox(height: 6),
                    Text(
                      '${_selectedService!['name']} · ${CurrencyHelper.format((_selectedService!['price'] as num?)?.toDouble() ?? 0, widget.salon.currency)} · ${_selectedService!['duration'] ?? 30} min',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.brand950),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        (l?.tr('appointments_with') ?? 'Avec {name}').replaceAll('{name}', widget.member.name),
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.secondary500),
                      ),
                    ),
                    Text(
                      '$dateStr à $timeStr',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.secondary500),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Submit button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _loading ? null : _submit,
                icon: _loading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(
                  _loading
                      ? (l?.tr('appointments_creating') ?? 'Création...')
                      : (l?.tr('appointments_create') ?? 'Créer le rendez-vous'),
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeSlotSection({
    required String label,
    required IconData icon,
    required List<String> slots,
  }) {
    final selectedStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: AppColors.secondary500),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary600,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              (AppLocalizations.of(context)?.tr('appointments_slots_count') ?? '{count} créneaux').replaceAll('{count}', '${slots.length}'),
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: slots.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final time = slots[index];
              final isSelected = selectedStr == time;
              final isBlocked = _isSlotBlocked(time);
              return GestureDetector(
                onTap: isBlocked ? null : () {
                  final parts = time.split(':');
                  setState(() => _selectedTime = TimeOfDay(
                        hour: int.parse(parts[0]),
                        minute: int.parse(parts[1]),
                      ));
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                  decoration: BoxDecoration(
                    color: isBlocked
                        ? AppColors.secondary100
                        : isSelected ? AppColors.brand600 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isBlocked
                          ? AppColors.secondary200
                          : isSelected
                              ? AppColors.brand600
                              : AppColors.secondary200,
                      width: isSelected && !isBlocked ? 1.5 : 1,
                    ),
                    boxShadow: isSelected && !isBlocked
                        ? [
                            BoxShadow(
                              color: AppColors.brand600
                                  .withValues(alpha: 0.25),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    time,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: isBlocked
                          ? AppColors.secondary300
                          : isSelected
                              ? Colors.white
                              : AppColors.secondary700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondary700,
        ),
      );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(fontSize: 13, color: AppColors.secondary400),
        filled: true,
        fillColor: AppColors.secondary50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: AppColors.brand400, width: 1.5),
        ),
      );
}

// ── Period chips shared between Mes RDV and Tous les RDV tabs ──────────────

class _MemberPeriodChips extends StatelessWidget {
  const _MemberPeriodChips({required this.selected, required this.onSelect});
  final AppointmentsPeriod selected;
  final ValueChanged<AppointmentsPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String label(AppointmentsPeriod p) => switch (p) {
          AppointmentsPeriod.last3Months =>
            l?.tr('appointments_period_3m') ?? '3 derniers mois',
          AppointmentsPeriod.last6Months =>
            l?.tr('appointments_period_6m') ?? '6 derniers mois',
          AppointmentsPeriod.lastYear =>
            l?.tr('appointments_period_1y') ?? 'Dernière année',
        };

    return Row(
      children: AppointmentsPeriod.values.map((p) {
        final active = p == selected;
        return Expanded(
          child: GestureDetector(
            onTap: () => onSelect(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: EdgeInsets.only(
                  right: p == AppointmentsPeriod.values.last ? 0 : 6),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: active ? AppColors.brand50 : Colors.white,
                border: Border.all(
                    color:
                        active ? AppColors.brand600 : AppColors.secondary200),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Text(
                label(p),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      active ? AppColors.brand700 : AppColors.secondary500,
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
