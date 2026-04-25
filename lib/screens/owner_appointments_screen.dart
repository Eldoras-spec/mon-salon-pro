import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../utils/currency_helper.dart';
import '../widgets/country_phone_field.dart';
import '../widgets/member_avatar.dart';
import '../widgets/whatsapp_otp_dialog.dart';

// ── Filter tabs ──────────────────────────────────────────────────────────────

enum _Filter { all, today, upcoming, completed, cancelled }

extension _FilterLabel on _Filter {
  String localizedLabel(AppLocalizations? l) => switch (this) {
        _Filter.all => l?.tr('appointments_filter_all') ?? 'Tous',
        _Filter.today => l?.tr('appointments_filter_today') ?? "Aujourd'hui",
        _Filter.upcoming => l?.tr('appointments_filter_upcoming') ?? 'À venir',
        _Filter.completed => l?.tr('appointments_filter_completed') ?? 'Terminés',
        _Filter.cancelled => l?.tr('appointments_filter_cancelled') ?? 'Annulés',
      };
}

// ── Screen ───────────────────────────────────────────────────────────────────

class OwnerAppointmentsScreen extends ConsumerStatefulWidget {
  const OwnerAppointmentsScreen({super.key});

  @override
  ConsumerState<OwnerAppointmentsScreen> createState() =>
      _OwnerAppointmentsScreenState();
}

class _OwnerAppointmentsScreenState
    extends ConsumerState<OwnerAppointmentsScreen> {
  _Filter _selected = _Filter.all;
  String _searchQuery = '';
  String? _memberFilterId; // null = tous les employés
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  static bool _isToday(DateTime dt) {
    final n = DateTime.now();
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  void _showAddAppointmentSheet(BuildContext context) {
    final salon = ref.read(ownerSalonProvider).value;
    final team = ref.read(ownerTeamProvider).value ?? [];
    if (salon == null) return;
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
        child: _AddAppointmentSheet(
          salon: salon,
          teamMembers: team,
          onCreated: () => ref.invalidate(ownerAppointmentsRangeProvider),
        ),
      ),
    );
  }

  List<AppointmentModel> _filter(List<AppointmentModel> all) {
    final now = DateTime.now();
    var result = switch (_selected) {
      _Filter.all => all,
      _Filter.today => all.where((a) => _isToday(a.dateTime)).toList(),
      _Filter.upcoming =>
        all.where((a) => a.status == 'upcoming' && a.dateTime.isAfter(now)).toList(),
      _Filter.completed => all.where((a) => a.status == 'completed').toList(),
      _Filter.cancelled => all.where((a) => a.status == 'cancelled').toList(),
    };
    if (_memberFilterId != null) {
      result = result
          .where((a) => a.assignedMemberId == _memberFilterId)
          .toList();
    }
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      final qDigits = q.replaceAll(RegExp(r'\D'), '');
      result = result
          .where((a) =>
              a.serviceName.toLowerCase().contains(q) ||
              (a.clientName ?? '').toLowerCase().contains(q) ||
              (qDigits.isNotEmpty &&
                  (a.clientPhone ?? '')
                      .replaceAll(RegExp(r'\D'), '')
                      .contains(qDigits)))
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final appointmentsAsync = ref.watch(ownerAppointmentsRangeProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: RefreshIndicator(
        color: AppColors.brand600,
        onRefresh: () async {
          ref.invalidate(ownerAppointmentsRangeProvider);
          await Future.delayed(const Duration(milliseconds: 500));
        },
        child: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            title: Text(
              l?.tr('appointments_title') ?? 'Rendez-vous',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                onPressed: () => _showAddAppointmentSheet(context),
                icon: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    border: Border.all(color: AppColors.brand200),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.add_rounded,
                      size: 18, color: AppColors.brand600),
                ),
                splashRadius: 20,
                tooltip: l?.tr('appointments_add_tooltip') ?? 'Ajouter un rendez-vous',
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(52),
              child: _FilterBar(
                selected: _selected,
                onSelect: (f) => setState(() => _selected = f),
              ),
            ),
          ),

          // ── Period + Member dropdowns (side by side) ───────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: _PeriodDropdown(
                      selected: ref.watch(appointmentsPeriodProvider),
                      onSelect: (p) =>
                          ref.read(appointmentsPeriodProvider.notifier).state = p,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _MemberDropdown(
                      selectedMemberId: _memberFilterId,
                      onSelect: (id) => setState(() => _memberFilterId = id),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Search bar ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: const TextStyle(fontSize: 13, color: AppColors.brand950),
                decoration: InputDecoration(
                  hintText: l?.tr('appointments_search_hint') ?? 'Rechercher par client, service…',
                  hintStyle: const TextStyle(
                      fontSize: 13, color: AppColors.secondary400),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 18, color: AppColors.secondary400),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                          child: const Icon(Icons.close_rounded,
                              size: 16, color: AppColors.secondary400),
                        )
                      : null,
                  filled: true,
                  fillColor: AppColors.secondary50,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.secondary200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.secondary200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: AppColors.brand400),
                  ),
                ),
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────
          appointmentsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: AppColors.brand600),
              ),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'))),
            ),
            data: (all) {
              final items = _filter(all);
              if (items.isEmpty) {
                return SliverFillRemaining(
                  child: _EmptyState(filter: _selected),
                );
              }
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => _AppointmentTile(
                    key: ValueKey(items[i].id),
                    appointment: items[i],
                    onStatusChanged: () => ref.invalidate(ownerAppointmentsRangeProvider),
                  ),
                  childCount: items.length,
                ),
              );
            },
          ),
        ],
      ),
      ),
    );
  }
}

// ── Filter bar ───────────────────────────────────────────────────────────────

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.selected, required this.onSelect});
  final _Filter selected;
  final ValueChanged<_Filter> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        children: _Filter.values.map((f) {
          final active = f == selected;
          return GestureDetector(
            onTap: () => onSelect(f),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: active ? AppColors.brand600 : AppColors.secondary100,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                f.localizedLabel(l),
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

// ── Dropdowns (period + member) ─────────────────────────────────────────────

const _dropdownPadding = EdgeInsets.symmetric(horizontal: 10, vertical: 8);
const _dropdownRadius = 10.0;

class _PeriodDropdown extends StatelessWidget {
  const _PeriodDropdown({required this.selected, required this.onSelect});
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

    return Container(
      padding: _dropdownPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.secondary200),
        borderRadius: BorderRadius.circular(_dropdownRadius),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<AppointmentsPeriod>(
          value: selected,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AppColors.secondary500),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.brand700,
          ),
          items: [
            for (final p in AppointmentsPeriod.values)
              DropdownMenuItem(value: p, child: Text(label(p), overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (p) { if (p != null) onSelect(p); },
        ),
      ),
    );
  }
}

class _MemberDropdown extends ConsumerWidget {
  const _MemberDropdown({required this.selectedMemberId, required this.onSelect});
  final String? selectedMemberId;
  final ValueChanged<String?> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final team = ref.watch(ownerTeamProvider).value ?? [];
    final allLabel = l?.tr('appointments_members_all') ?? 'Tous les employés';

    return Container(
      padding: _dropdownPadding,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.secondary200),
        borderRadius: BorderRadius.circular(_dropdownRadius),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String?>(
          value: selectedMemberId,
          isExpanded: true,
          isDense: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: AppColors.secondary500),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.brand700,
          ),
          items: [
            DropdownMenuItem<String?>(value: null, child: Text(allLabel, overflow: TextOverflow.ellipsis)),
            for (final m in team)
              DropdownMenuItem<String?>(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: onSelect,
        ),
      ),
    );
  }
}

// ── Appointment tile ─────────────────────────────────────────────────────────

class _AppointmentTile extends ConsumerStatefulWidget {
  const _AppointmentTile({
    super.key,
    required this.appointment,
    required this.onStatusChanged,
  });
  final AppointmentModel appointment;
  final VoidCallback onStatusChanged;

  @override
  ConsumerState<_AppointmentTile> createState() => _AppointmentTileState();
}

class _AppointmentTileState extends ConsumerState<_AppointmentTile> {
  String _clientName = '…';
  String? _clientPhone;
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;

    // Prefer the name/phone snapshot written on the appointment itself
    // (always present for walk-ins via website + mobile walk-in bookings).
    final storedName = a.clientName?.trim();
    final storedPhone = a.clientPhone?.trim();
    if (storedName != null && storedName.isNotEmpty) {
      _clientName = storedName;
    }
    if (storedPhone != null && storedPhone.isNotEmpty) {
      _clientPhone = storedPhone;
    }

    if (a.clientId == 'walk-in') {
      if (storedName == null || storedName.isEmpty) {
        _clientName = 'Client sans compte';
      }
      return;
    }

    // Registered clients: fill any missing fields from the user doc.
    if (storedName == null || storedName.isEmpty) {
      DatabaseService().getClientName(a.clientId).then((name) {
        if (mounted) setState(() => _clientName = name);
      });
    }
    if (storedPhone == null || storedPhone.isEmpty) {
      DatabaseService().getClientPhone(a.clientId).then((phone) {
        if (mounted) setState(() => _clientPhone = phone);
      });
    }
  }

  Future<void> _updateStatus(String newStatus) async {
    setState(() => _updating = true);
    try {
      await DatabaseService()
          .updateAppointmentStatus(widget.appointment.id, newStatus);
      // Loyalty points are awarded server-side by the
      // `onAppointmentStatusChanged` Cloud Function whenever the status
      // transitions to "completed" (manual here + auto-complete CF).
      widget.onStatusChanged();
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e')), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showAssignSheet(List<TeamMemberModel> members) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                l?.tr('appointments_assign_member') ?? 'Assigner à un membre',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
            ),
            const Divider(height: 1),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l?.tr('appointments_no_team_members') ?? 'Aucun membre dans l\'équipe',
                  style: const TextStyle(color: AppColors.secondary400),
                ),
              )
            else
              ...members.map((m) => ListTile(
                    leading: MemberAvatar(
                      name: m.name,
                      photoUrl: m.photoUrl,
                      radius: 20,
                    ),
                    title: Text(m.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      m.role == 'gerant' ? (l?.tr('team_role_manager') ?? 'Gérant(e)') : (l?.tr('team_role_member') ?? 'Employé(e)'),
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: widget.appointment.assignedMemberId == m.id
                        ? const Icon(Icons.check_circle_rounded,
                            color: AppColors.brand600)
                        : null,
                    onTap: () async {
                      Navigator.pop(context);
                      await DatabaseService().assignAppointment(
                        widget.appointment.id,
                        m.id,
                        m.name,
                      );
                      widget.onStatusChanged();
                    },
                  )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showActions() {
    final l = AppLocalizations.of(context);
    final a = widget.appointment;
    if (a.status != 'upcoming') return;
    final members = ref.read(ownerTeamProvider).value ?? [];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Text(
                    a.serviceName,
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                  if (a.selectedOptions != null && a.selectedOptions!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6, runSpacing: 4,
                      alignment: WrapAlignment.center,
                      children: a.selectedOptions!.map((opt) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brand50,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.brand200),
                        ),
                        child: Text(opt, style: const TextStyle(fontSize: 11, color: AppColors.brand700, fontWeight: FontWeight.w500)),
                      )).toList(),
                    ),
                  ],
                  // Selected design image
                  if (a.selectedDesignUrl != null) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        children: [
                          Image.network(
                            a.selectedDesignThumbnail ?? a.selectedDesignUrl!,
                            height: 100, width: double.infinity, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const SizedBox.shrink()),
                          if (a.selectedDesignIsVideo == true)
                            const Positioned.fill(
                              child: Center(child: Icon(Icons.play_circle_filled, size: 36, color: Colors.white70)),
                            ),
                        ],
                      ),
                    ),
                    if (a.selectedDesignLabel != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text('${a.selectedDesignIsVideo == true ? '🎬' : '🎨'} ${a.selectedDesignLabel!}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.purple)),
                      ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            if (a.dateTime.isBefore(DateTime.now()))
              ListTile(
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: const Color(0xFFDCFCE7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.check_rounded,
                      color: Color(0xFF16A34A), size: 20),
                ),
                title: Text(l?.tr('appointments_mark_completed') ?? 'Marquer comme terminé',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  _updateStatus('completed');
                },
              ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.person_pin_outlined,
                    color: AppColors.brand600, size: 20),
              ),
              title: Text(l?.tr('appointments_assign_member') ?? 'Assigner à un membre',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _showAssignSheet(members);
              },
            ),
            ListTile(
              leading: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.close_rounded,
                    color: Color(0xFFDC2626), size: 20),
              ),
              title: Text(l?.tr('appointments_cancel') ?? 'Annuler le rendez-vous',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _updateStatus('cancelled');
              },
            ),
            _BlacklistTile(appointment: a),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = widget.appointment;
    if (a.clientId == 'walk-in' && a.clientName == null) {
      _clientName = l?.tr('appointments_walk_in_client') ?? 'Client sans compte';
    }

    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr =
        DateFormat('EEE d MMM', 'fr_FR').format(a.dateTime);

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

    final canAct = a.status == 'upcoming';

    return InkWell(
      onTap: canAct ? _showActions : null,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(
            bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
          ),
        ),
        child: Row(
          children: [
            // Date/Time column
            SizedBox(
              width: 48,
              child: Column(
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
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.secondary400,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),

            Container(
                width: 1, height: 40, color: AppColors.secondary100,
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
                  const SizedBox(height: 2),
                  Text(
                    _clientPhone != null
                        ? '$_clientName  •  $_clientPhone'
                        : _clientName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                    ),
                  ),
                  if (a.assignedMemberName != null) ...[
                    const SizedBox(height: 4),
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

            const SizedBox(width: 12),

            // Right: price + status + action
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  CurrencyHelper.format(a.price, ref.read(ownerSalonProvider).value?.currency ?? 'MAD'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 4),
                _updating
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            color: AppColors.brand600, strokeWidth: 2),
                      )
                    : Container(
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
                            color: statusFg,
                          ),
                        ),
                      ),
              ],
            ),

            if (canAct) ...[
              const SizedBox(width: 8),
              const Icon(Icons.more_vert_rounded,
                  color: AppColors.secondary300, size: 18),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ──────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filter});
  final _Filter filter;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final (icon, msg) = switch (filter) {
      _Filter.today => (
          Icons.calendar_today_outlined,
          l?.tr('appointments_empty_today') ?? "Aucun rendez-vous aujourd'hui"
        ),
      _Filter.upcoming => (
          Icons.event_available_outlined,
          l?.tr('appointments_empty_upcoming') ?? 'Aucun rendez-vous à venir'
        ),
      _Filter.completed => (
          Icons.check_circle_outline_rounded,
          l?.tr('appointments_empty_completed') ?? 'Aucun rendez-vous terminé'
        ),
      _Filter.cancelled => (
          Icons.cancel_outlined,
          l?.tr('appointments_empty_cancelled') ?? 'Aucun rendez-vous annulé'
        ),
      _ => (Icons.calendar_month_outlined, l?.tr('appointments_empty_all') ?? 'Aucun rendez-vous pour l\'instant'),
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
            Text(
              msg,
              style: const TextStyle(
                color: AppColors.brand950,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add appointment sheet ───────────────────────────────────────────────────

class _AddAppointmentSheet extends StatefulWidget {
  const _AddAppointmentSheet({
    required this.salon,
    required this.teamMembers,
    required this.onCreated,
  });
  final SalonModel salon;
  final List<TeamMemberModel> teamMembers;
  final VoidCallback onCreated;

  @override
  State<_AddAppointmentSheet> createState() => _AddAppointmentSheetState();
}

class _AddAppointmentSheetState extends State<_AddAppointmentSheet> {
  static const _dayKeys = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];

  final _clientNameCtrl = TextEditingController();
  String? _clientWhatsappE164;
  String? _verifiedWalkInWhatsapp;
  // Multi-service selection (cap 5). _selectedService is kept in sync with
  // _selectedServices.first for compatibility with existing single-service
  // logic paths (slot checks, employee picker).
  final List<Map<String, dynamic>> _selectedServices = [];
  Map<String, dynamic>? _selectedService;
  Map<String, dynamic>? _selectedPack;
  TeamMemberModel? _selectedMember;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;
  List<AppointmentModel> _existingAppointments = [];
  // Service picker UX (matches client app pattern)
  String? _activeServiceCategory;
  bool _showAllServices = false;

  bool get _isMultiService => _selectedServices.length > 1;

  List<String> get _serviceCategories {
    final seen = <String>{};
    final cats = <String>[];
    for (final s in widget.salon.services) {
      if (s['visibleTo'] != null) continue;
      final cat = s['category'] as String?;
      if (cat != null && cat.isNotEmpty && seen.add(cat)) cats.add(cat);
    }
    return cats;
  }

  List<Map<String, dynamic>> get _filteredServices {
    var services = widget.salon.services
        .where((s) => s['visibleTo'] == null)
        .cast<Map<String, dynamic>>()
        .toList();
    final all = _activeServiceCategory == null
        ? services
        : services.where((s) => s['category'] == _activeServiceCategory).toList();
    // Put selected services first so the user can see what they picked.
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
    0, (sum, s) => sum + ((s['duration'] as int?) ?? 30),
  );

  double get _totalPrice => _selectedServices.fold<double>(
    0.0, (sum, s) => sum + ((s['price'] as num?)?.toDouble() ?? 0.0),
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
        _selectedPack = null; // packs and multi-service are exclusive
      }
      _selectedService = _selectedServices.isNotEmpty ? _selectedServices.first : null;
      _selectedMember = null;
    });
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
    } catch (e) {
      debugPrint('Error loading appointments: $e');
    }
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    super.dispose();
  }

  /// Get the working hours data for a given date.
  Map<String, dynamic>? _getHoursForDate(DateTime date) {
    final dayKey = _dayKeys[date.weekday - 1]; // weekday: 1=Mon
    return widget.salon.workingHours[dayKey] as Map<String, dynamic>?;
  }

  bool _isDayOpen(DateTime date) {
    final data = _getHoursForDate(date);
    return data?['isOpen'] == true;
  }

  TimeOfDay _parseTime(String time) {
    final parts = time.split(':');
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }

  /// Snap selected time to opening hour if current time is outside range.
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        // Check if salon is open
        final wh = _getHoursForDate(date);
        if (wh == null || wh['isOpen'] != true) return false;
        // Check if selected member is unavailable the whole day
        if (_selectedMember != null) {
          if (_selectedMember!.isUnavailableOnDate(date)) return false;
        }
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

  /// Generate 30-min time slots from salon working hours for selected date.
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
      slots.add('${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
    }
    return slots;
  }

  /// Total duration of selected pack (null if no pack selected)
  int? get _packDuration {
    if (_selectedPack == null) return null;
    final packServices = List<String>.from(_selectedPack!['services'] ?? []);
    final services = widget.salon.services;
    int total = 0;
    for (final sName in packServices) {
      final svc = services.cast<Map<String, dynamic>>().firstWhere(
        (s) => (s['name'] ?? s['title']) == sName,
        orElse: () => <String, dynamic>{},
      );
      total += ((svc['duration'] ?? 30) as int);
    }
    return total;
  }

  /// Check if the pack can be chained starting at [timeStr].
  bool _canChainPackAt(String timeStr) {
    if (_selectedPack == null) return true;
    final parts = timeStr.split(':');
    var cursor = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day,
        int.parse(parts[0]), int.parse(parts[1]));
    final iso = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final packServices = List<String>.from(_selectedPack!['services'] ?? []);
    final services = widget.salon.services.cast<Map<String, dynamic>>();
    final simulatedBusy = <String, List<List<DateTime>>>{};

    for (final sName in packServices) {
      final svc = services.firstWhere(
        (s) => (s['name'] ?? s['title']) == sName,
        orElse: () => <String, dynamic>{'duration': 30},
      );
      final dur = (svc['duration'] as int?) ?? 30;
      final svcEnd = cursor.add(Duration(minutes: dur));

      final candidates = widget.teamMembers
          .where((m) => m.isActive && m.assignedServiceNames.contains(sName) && !m.isUnavailableOnDate(_selectedDate))
          .toList();

      if (candidates.isEmpty) {
        cursor = svcEnd;
        continue;
      }

      bool found = false;
      for (final m in candidates) {
        final busy = _existingAppointments.any((a) {
          if (a.assignedMemberId != m.id) return false;
          final aStart = a.dateTime.toUtc();
          final aEnd = aStart.add(Duration(minutes: a.durationMinutes));
          return cursor.toUtc().isBefore(aEnd) && svcEnd.toUtc().isAfter(aStart);
        });
        final simBusy = (simulatedBusy[m.id] ?? []).any((r) =>
            cursor.isBefore(r[1]) && svcEnd.isAfter(r[0]));
        if (!busy && !simBusy) {
          simulatedBusy.putIfAbsent(m.id, () => []).add([cursor, svcEnd]);
          found = true;
          break;
        }
      }
      if (!found) return false;
      cursor = svcEnd;
    }
    return true;
  }

  /// Check if a time slot is blocked for the selected member (or pack chain).
  bool _isSlotBlocked(String timeStr) {
    if (_selectedService == null) return false;

    // Pack mode: check if the entire chain can be auto-assigned
    if (_selectedPack != null) {
      return !_canChainPackAt(timeStr);
    }

    if (_selectedMember == null) return false;
    final parts = timeStr.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    final duration = _packDuration ?? ((_selectedService!['duration'] as int?) ?? 30);
    final slotStart = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, h, m);
    final slotEnd = slotStart.add(Duration(minutes: duration));

    // Check member full-day unavailability (includes recurring days off)
    if (_selectedMember!.isUnavailableOnDate(_selectedDate)) return true;

    // Check member hourly unavailability
    final iso = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final unavailSlots = _selectedMember!.unavailableSlots[iso] ?? [];
    for (final slot in unavailSlots) {
      final sp = slot.split('-');
      if (sp.length != 2) continue;
      final sParts = sp[0].split(':');
      final eParts = sp[1].split(':');
      final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
      final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
      final startMin = h * 60 + m;
      final endMin = startMin + duration;
      if (startMin < eMin && endMin > sMin) return true;
    }

    // Check existing appointments for this member
    for (final appt in _existingAppointments) {
      if (appt.assignedMemberId != _selectedMember!.id) continue;
      final apptStart = appt.dateTime.toUtc();
      final apptEnd = apptStart.add(Duration(minutes: appt.durationMinutes));
      final sUtc = slotStart.toUtc();
      final eUtc = slotEnd.toUtc();
      if (sUtc.isBefore(apptEnd) && eUtc.isAfter(apptStart)) return true;
    }

    return false;
  }

  /// Multi-service mode: auto-assign an available employee per service and
  /// create one appointment per service chained back-to-back. Mirrors
  /// _submitPack but iterates over the full service map (with price/duration
  /// already present) rather than looking up names in salon.services.
  Future<void> _submitMulti(String clientName, AppLocalizations? l) async {
    setState(() => _loading = true);
    try {
      final existing = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);

      var cursor = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );

      final bookings = <Map<String, dynamic>>[];

      for (final svc in _selectedServices) {
        final sName = svc['name'] as String? ?? svc['title'] as String? ?? 'Service';
        final dur = (svc['duration'] as int?) ?? 30;
        final svcEnd = cursor.add(Duration(minutes: dur));

        final priority = List<String>.from(svc['memberPriority'] ?? []);
        final candidates = widget.teamMembers
            .where((m) =>
                m.isActive &&
                m.assignedServiceNames.contains(sName) &&
                !m.isUnavailableOnDate(_selectedDate))
            .toList();
        if (priority.isNotEmpty) {
          candidates.sort((a, b) {
            final aIdx = priority.indexOf(a.name);
            final bIdx = priority.indexOf(b.name);
            return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
          });
        }

        TeamMemberModel? assigned;
        for (final m in candidates) {
          final busy = existing.any((a) {
            if (a.assignedMemberId != m.id) return false;
            final aStart = a.dateTime.toUtc();
            final aEnd = aStart.add(Duration(minutes: a.durationMinutes));
            return cursor.toUtc().isBefore(aEnd) && svcEnd.toUtc().isAfter(aStart);
          });
          final chainBusy = bookings.any((b) {
            if (b['memberId'] != m.id) return false;
            final bStart = b['start'] as DateTime;
            final bEnd = b['end'] as DateTime;
            return cursor.isBefore(bEnd) && svcEnd.isAfter(bStart);
          });
          if (!busy && !chainBusy) {
            assigned = m;
            break;
          }
        }

        if (assigned == null && candidates.isNotEmpty) {
          if (mounted) {
            _showError('Aucun employé disponible pour "$sName" à ${cursor.hour.toString().padLeft(2, '0')}:${cursor.minute.toString().padLeft(2, '0')}');
            setState(() => _loading = false);
          }
          return;
        }

        bookings.add({
          'service': svc,
          'member': assigned,
          'memberId': assigned?.id,
          'start': cursor,
          'end': svcEnd,
          'duration': dur,
        });
        cursor = svcEnd;
      }

      final clientWhatsapp = _clientWhatsappE164;
      for (final b in bookings) {
        final svc = b['service'] as Map<String, dynamic>;
        final member = b['member'] as TeamMemberModel?;
        final appointment = AppointmentModel(
          id: const Uuid().v4(),
          clientId: 'walk-in',
          salonId: widget.salon.id,
          salonName: widget.salon.name,
          serviceName: svc['name'] as String? ?? 'Service',
          price: (svc['price'] as num?)?.toDouble() ?? 0.0,
          dateTime: DateTime.utc(
            (b['start'] as DateTime).year,
            (b['start'] as DateTime).month,
            (b['start'] as DateTime).day,
            (b['start'] as DateTime).hour,
            (b['start'] as DateTime).minute,
          ),
          status: 'upcoming',
          createdAt: DateTime.now(),
          durationMinutes: b['duration'] as int,
          clientName: clientName,
          clientPhone: (clientWhatsapp != null && clientWhatsapp.isNotEmpty)
              ? clientWhatsapp
              : null,
          assignedMemberId: member?.id,
          assignedMemberName: member?.name,
        );
        await DatabaseService().createAppointment(appointment);
      }

      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError('Erreur: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _submitPack(String clientName, AppLocalizations? l) async {
    final packServices = List<String>.from(_selectedPack!['services'] ?? []);
    final services = widget.salon.services.cast<Map<String, dynamic>>();
    final iso = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    setState(() => _loading = true);
    try {
      final existing = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);

      var cursor = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day,
        _selectedTime.hour, _selectedTime.minute,
      );

      final bookings = <Map<String, dynamic>>[];

      for (final sName in packServices) {
        final svc = services.firstWhere(
          (s) => (s['name'] ?? s['title']) == sName,
          orElse: () => <String, dynamic>{'name': sName, 'duration': 30, 'price': 0},
        );
        final dur = (svc['duration'] as int?) ?? 30;
        final svcEnd = cursor.add(Duration(minutes: dur));

        // Find available member for this service, sorted by priority
        final priority = List<String>.from(svc['memberPriority'] ?? []);
        final candidates = widget.teamMembers
            .where((m) =>
                m.isActive &&
                m.assignedServiceNames.contains(sName) &&
                !m.isUnavailableOnDate(_selectedDate))
            .toList();
        // Sort by priority ranking
        if (priority.isNotEmpty) {
          candidates.sort((a, b) {
            final aIdx = priority.indexOf(a.name);
            final bIdx = priority.indexOf(b.name);
            return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
          });
        }

        TeamMemberModel? assigned;
        for (final m in candidates) {
          // Check existing appointments
          final busy = existing.any((a) {
            if (a.assignedMemberId != m.id) return false;
            final aStart = a.dateTime.toUtc();
            final aEnd = aStart.add(Duration(minutes: a.durationMinutes));
            return cursor.toUtc().isBefore(aEnd) && svcEnd.toUtc().isAfter(aStart);
          });
          // Check already planned bookings in this chain
          final chainBusy = bookings.any((b) {
            if (b['memberId'] != m.id) return false;
            final bStart = b['start'] as DateTime;
            final bEnd = b['end'] as DateTime;
            return cursor.isBefore(bEnd) && svcEnd.isAfter(bStart);
          });
          if (!busy && !chainBusy) {
            assigned = m;
            break;
          }
        }

        if (assigned == null && candidates.isNotEmpty) {
          if (mounted) {
            _showError('Aucun employé disponible pour "$sName" à ${cursor.hour.toString().padLeft(2, '0')}:${cursor.minute.toString().padLeft(2, '0')}');
            setState(() => _loading = false);
          }
          return;
        }

        bookings.add({
          'service': svc,
          'member': assigned,
          'memberId': assigned?.id,
          'start': cursor,
          'end': svcEnd,
          'duration': dur,
        });
        cursor = svcEnd;
      }

      // Create all appointments
      final clientWhatsapp = _clientWhatsappE164;
      for (final b in bookings) {
        final svc = b['service'] as Map<String, dynamic>;
        final member = b['member'] as TeamMemberModel?;
        final appointment = AppointmentModel(
          id: const Uuid().v4(),
          clientId: 'walk-in',
          salonId: widget.salon.id,
          salonName: widget.salon.name,
          serviceName: svc['name'] as String? ?? 'Service',
          price: (svc['price'] as num?)?.toDouble() ?? 0.0,
          dateTime: b['start'] as DateTime,
          status: 'upcoming',
          createdAt: DateTime.now(),
          durationMinutes: b['duration'] as int,
          clientName: clientName,
          clientPhone: (clientWhatsapp != null && clientWhatsapp.isNotEmpty)
              ? clientWhatsapp
              : null,
          assignedMemberId: member?.id,
          assignedMemberName: member?.name,
        );
        await DatabaseService().createAppointment(appointment);
      }

      widget.onCreated();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _showError('Erreur: $e');
    }
    if (mounted) setState(() => _loading = false);
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
    if (_selectedPack == null && !_isMultiService && _selectedMember == null) {
      _showError(l?.tr('appointments_error_employee') ?? 'Veuillez sélectionner un employé');
      return;
    }

    // WhatsApp OTP verification (Business plan only — CF gates server-side).
    // Free/Essentiel salons short-circuit and proceed without OTP. Optional
    // field: skip entirely if no WA number was entered.
    final whatsapp = _clientWhatsappE164;
    if (whatsapp != null && whatsapp.isNotEmpty &&
        _verifiedWalkInWhatsapp != whatsapp) {
      final result = await WhatsappOtpDialog.show(
        context, whatsapp,
        salonId: widget.salon.id,
      );
      if (!mounted) return;
      if (result == null) {
        _showError(l?.tr('appointments_walkin_otp_required') ??
            'Vérification WhatsApp annulée. Réessayez ou laissez le champ vide.');
        return;
      }
      _verifiedWalkInWhatsapp = whatsapp;
    }

    // Pack mode → auto-assign and create chained appointments
    if (_selectedPack != null) {
      await _submitPack(clientName, l);
      return;
    }
    // Multi-service mode → auto-assign like pack
    if (_isMultiService) {
      await _submitMulti(clientName, l);
      return;
    }
    if (!_isDayOpen(_selectedDate)) {
      _showError(l?.tr('appointments_error_closed') ?? 'Le salon est fermé ce jour-là');
      return;
    }
    // Check member unavailability
    if (_selectedMember!.isUnavailableOnDate(_selectedDate)) {
      _showError((l?.tr('appointments_error_unavailable_day') ?? '{name} est indisponible ce jour-là').replaceAll('{name}', _selectedMember!.name));
      return;
    }

    // Check if the selected time falls within an unavailable slot
    final isoDate =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final duration = _packDuration ?? (_selectedService!['duration'] as int? ?? 30);
    final slots = _selectedMember!.unavailableSlots[isoDate] ?? [];
    if (slots.isNotEmpty) {
      final startMin = _selectedTime.hour * 60 + _selectedTime.minute;
      final endMin = startMin + duration;
      for (final slot in slots) {
        final parts = slot.split('-');
        if (parts.length != 2) continue;
        final sp = parts[0].split(':');
        final ep = parts[1].split(':');
        final sMin = int.parse(sp[0]) * 60 + int.parse(sp[1]);
        final eMin = int.parse(ep[0]) * 60 + int.parse(ep[1]);
        if (startMin < eMin && endMin > sMin) {
          _showError((l?.tr('appointments_error_unavailable_slot') ?? '{name} est indisponible sur ce créneau ({slot})').replaceAll('{name}', _selectedMember!.name).replaceAll('{slot}', '${parts[0]} - ${parts[1]}'));
          return;
        }
      }
    }

    setState(() => _loading = true);
    try {
      final dateTime = DateTime.utc(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        _selectedTime.hour,
        _selectedTime.minute,
      );

      final serviceName = _selectedPack != null
          ? 'Pack: ${_selectedPack!['name'] ?? 'Pack'}'
          : (_selectedService!['name'] as String? ?? 'Service');
      final price = _selectedPack != null
          ? (_selectedPack!['price'] as num?)?.toDouble() ?? 0.0
          : (_selectedService!['price'] as num?)?.toDouble() ?? 0.0;

      // Double-booking check
      final existing = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);
      final newStart = dateTime;
      final newEnd = dateTime.add(Duration(minutes: duration));
      final conflict = existing.where((a) {
        if (a.assignedMemberId != _selectedMember!.id) return false;
        final aEnd = a.dateTime.add(Duration(minutes: a.durationMinutes));
        return newStart.isBefore(aEnd) && newEnd.isAfter(a.dateTime);
      }).firstOrNull;
      if (conflict != null) {
        final conflictTime =
            '${conflict.dateTime.hour.toString().padLeft(2, '0')}:${conflict.dateTime.minute.toString().padLeft(2, '0')}';
        if (mounted) {
          _showError(
              (l?.tr('appointments_error_conflict') ?? '{name} a déjà un RDV à {time}').replaceAll('{name}', _selectedMember!.name).replaceAll('{time}', conflictTime));
          setState(() => _loading = false);
        }
        return;
      }

      final appointment = AppointmentModel(
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
        clientPhone: (_clientWhatsappE164 != null &&
                _clientWhatsappE164!.isNotEmpty)
            ? _clientWhatsappE164
            : null,
        assignedMemberId: _selectedMember!.id,
        assignedMemberName: _selectedMember!.name,
      );

      await DatabaseService().createAppointment(appointment);

      // Notify the assigned member
      final timeLabel =
          '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      await DatabaseService().saveNotification(
        userId: 'team_${widget.salon.id}_${_selectedMember!.id}',
        title: l?.tr('appointments_new_assignment_title') ?? 'Nouveau RDV assigné',
        body: (l?.tr('appointments_new_assignment_body') ?? '{service} avec {client} le {date} à {time}').replaceAll('{service}', serviceName).replaceAll('{client}', clientName).replaceAll('{date}', DateFormat('d MMM', 'fr_FR').format(dateTime)).replaceAll('{time}', timeLabel),
        type: 'assignment',
      );

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
      if (mounted) {
        _showError((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'));
      }
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
    final packs = widget.salon.servicePacks;
    final showPacks = packs.isNotEmpty &&
        _activeServiceCategory == null &&
        _selectedServices.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Category chips
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

        // Packs (only when no category filter and no services selected)
        if (showPacks) ...[
          ...packs.map((pack) => _buildPackTile(pack, l)),
          const SizedBox(height: 8),
        ],

        // Service tiles
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

        // "Voir plus" toggle
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

        // Summary bar when multi-service
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
            _selectedMember = null;
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
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final dateStr = DateFormat('EEE d MMM yyyy', 'fr_FR').format(_selectedDate);
    final timeStr =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';

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
              l?.tr('appointments_new_subtitle') ?? 'Ajoutez un rendez-vous reçu par téléphone ou WhatsApp',
              style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
            ),
            const SizedBox(height: 20),

            // Client name
            _label(l?.tr('appointments_client_name') ?? 'Nom du client *'),
            const SizedBox(height: 6),
            TextField(
              controller: _clientNameCtrl,
              style: const TextStyle(fontSize: 14, color: AppColors.brand950),
              decoration: _inputDecoration(l?.tr('appointments_client_name_hint') ?? 'ex. Mohamed Alami'),
            ),
            const SizedBox(height: 16),

            // Client WhatsApp (used for OTP verification on Business plan)
            _label(l?.tr('appointments_client_whatsapp') ?? 'WhatsApp'),
            const SizedBox(height: 6),
            CountryPhoneField(
              initialE164: _clientWhatsappE164,
              onChanged: (e164) {
                setState(() {
                  _clientWhatsappE164 = e164;
                  if (_verifiedWalkInWhatsapp != e164) {
                    _verifiedWalkInWhatsapp = null;
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Service / Pack selection
            _label(l?.tr('appointments_service_label') ?? 'Service *'),
            const SizedBox(height: 6),
            _buildServicePicker(l),
            const SizedBox(height: 16),

            // Employee selection (filtered by selected service)
            _label(l?.tr('appointments_employee_label') ?? 'Employé *'),
            const SizedBox(height: 6),
            Builder(builder: (_) {
              if (_selectedService == null) {
                return Text(
                  l?.tr('appointments_select_service_first') ?? 'Sélectionnez d\'abord un service',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary400),
                );
              }
              // Pack mode OR multi-service mode → auto-assign
              if (_selectedPack != null || _isMultiService) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.brand100),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.auto_awesome, size: 16, color: AppColors.brand600),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          l?.tr('appointments_auto_assign') ?? 'Attribution automatique des employés pour chaque service du pack',
                          style: const TextStyle(fontSize: 12, color: AppColors.brand700),
                        ),
                      ),
                    ],
                  ),
                );
              }
              final serviceName =
                  _selectedService?['name'] as String? ?? '';
              final filteredMembers = serviceName.isEmpty
                  ? widget.teamMembers
                  : widget.teamMembers
                      .where((m) =>
                          m.isActive &&
                          m.assignedServiceNames.contains(serviceName))
                      .toList();
              if (filteredMembers.isEmpty) {
                return Text(
                  l?.tr('appointments_no_employee_for_service') ?? 'Aucun employé assigné à ce service',
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary400),
                );
              }
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filteredMembers.map((m) {
                  final selected = _selectedMember?.id == m.id;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedMember = m),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color:
                            selected ? AppColors.brand100 : Colors.white,
                        border: Border.all(
                          color: selected
                              ? AppColors.brand400
                              : AppColors.secondary200,
                        ),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          selected
                              ? const CircleAvatar(
                                  radius: 12,
                                  backgroundColor: AppColors.brand500,
                                  child: Icon(Icons.check,
                                      size: 12, color: Colors.white),
                                )
                              : MemberAvatar(
                                  name: m.name,
                                  photoUrl: m.photoUrl,
                                  radius: 12,
                                ),
                          const SizedBox(width: 6),
                          Text(
                            m.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: selected
                                  ? AppColors.brand700
                                  : AppColors.secondary600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              );
            }),
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
              final morning =
                  slots.where((t) => int.parse(t.split(':')[0]) < 12).toList();
              final afternoon =
                  slots.where((t) => int.parse(t.split(':')[0]) >= 12).toList();
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
                      _selectedPack != null
                          ? 'Pack: ${_selectedPack!['name']} · ${CurrencyHelper.format((_selectedPack!['price'] as num?)?.toDouble() ?? 0, widget.salon.currency)} · ${_packDuration ?? 0} min'
                          : '${_selectedService!['name']} · ${CurrencyHelper.format((_selectedService!['price'] as num?)?.toDouble() ?? 0, widget.salon.currency)} · ${_selectedService!['duration'] ?? 30} min',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.brand950),
                    ),
                    if (_selectedMember != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          (l?.tr('appointments_with') ?? 'Avec {name}').replaceAll('{name}', _selectedMember!.name),
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
                  _loading ? (l?.tr('appointments_creating') ?? 'Création...') : (l?.tr('appointments_create') ?? 'Créer le rendez-vous'),
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
            separatorBuilder: (_, __) => const SizedBox(width: 8),
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
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.secondary400),
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
          borderSide: const BorderSide(color: AppColors.brand400, width: 1.5),
        ),
      );
}

// ─── Blacklist Tile (used in appointment bottom sheet) ────────────────────────

class _BlacklistTile extends StatefulWidget {
  const _BlacklistTile({required this.appointment});
  final AppointmentModel appointment;

  @override
  State<_BlacklistTile> createState() => _BlacklistTileState();
}

class _BlacklistTileState extends State<_BlacklistTile> {
  bool? _isBlocked;

  @override
  void initState() {
    super.initState();
    _checkBlacklist();
  }

  Future<void> _checkBlacklist() async {
    final a = widget.appointment;
    final blocked = await DatabaseService().isBlacklisted(
      a.salonId,
      phone: a.clientPhone,
      userId: a.clientId != 'walk-in' ? a.clientId : null,
    );
    if (mounted) setState(() => _isBlocked = blocked);
  }

  Future<void> _toggleBlacklist() async {
    final l = AppLocalizations.of(context);
    final a = widget.appointment;

    if (_isBlocked == true) {
      // Remove from blacklist
      final blacklist = await DatabaseService().getBlacklist(a.salonId);
      final entry = blacklist.firstWhere(
        (e) =>
            (a.clientPhone != null && e['phone'] == a.clientPhone) ||
            (a.clientId != 'walk-in' && e['userId'] == a.clientId),
        orElse: () => {},
      );
      if (entry.isNotEmpty) {
        await DatabaseService().removeFromBlacklist(a.salonId, entry);
        if (mounted) {
          setState(() => _isBlocked = false);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(l?.tr('clients_bl_unblock') ?? 'Client débloqué'),
              backgroundColor: AppColors.brand600,
            ),
          );
        }
      }
    } else {
      // Add to blacklist
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l?.tr('clients_block_title') ?? 'Bloquer ce client ?'),
          content: Text(
            (l?.tr('clients_block_msg') ?? '{name} ne pourra plus réserver dans votre salon.')
                .replaceAll('{name}', a.clientName ?? a.clientPhone ?? ''),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l?.tr('common_cancel') ?? 'Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(
                l?.tr('clients_block') ?? 'Bloquer',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      );

      if (confirm == true) {
        final entry = <String, dynamic>{
          'name': a.clientName ?? a.clientPhone ?? '—',
          'blockedAt': Timestamp.now(),
        };
        if (a.clientPhone != null && a.clientPhone!.isNotEmpty) {
          entry['phone'] = a.clientPhone!;
        }
        if (a.clientId != 'walk-in') {
          entry['userId'] = a.clientId;
        }
        await DatabaseService().addToBlacklist(a.salonId, entry);
        if (mounted) {
          setState(() => _isBlocked = true);
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                (l?.tr('clients_blocked_success') ?? '{name} a été bloqué')
                    .replaceAll('{name}', a.clientName ?? ''),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    if (_isBlocked == null) {
      return const SizedBox(height: 48, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.secondary300))));
    }

    final isBlocked = _isBlocked!;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isBlocked ? const Color(0xFFDCFCE7) : const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          isBlocked ? Icons.lock_open_rounded : Icons.block,
          color: isBlocked ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
          size: 20,
        ),
      ),
      title: Text(
        isBlocked
            ? (l?.tr('clients_bl_unblock') ?? 'Débloquer')
            : (l?.tr('clients_block') ?? 'Bloquer'),
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isBlocked ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
        ),
      ),
      onTap: _toggleBlacklist,
    );
  }
}
