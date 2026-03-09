import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/owner_providers.dart';
import '../services/database_service.dart';

// ── Filter tabs ──────────────────────────────────────────────────────────────

enum _Filter { all, today, upcoming, completed, cancelled }

extension _FilterLabel on _Filter {
  String get label => switch (this) {
        _Filter.all => 'Tous',
        _Filter.today => "Aujourd'hui",
        _Filter.upcoming => 'À venir',
        _Filter.completed => 'Terminés',
        _Filter.cancelled => 'Annulés',
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
          onCreated: () => ref.invalidate(ownerAppointmentsProvider),
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
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      result = result
          .where((a) =>
              a.serviceName.toLowerCase().contains(q) ||
              (a.clientName ?? '').toLowerCase().contains(q) ||
              (a.assignedMemberName ?? '').toLowerCase().contains(q))
          .toList();
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final appointmentsAsync = ref.watch(ownerAppointmentsProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: RefreshIndicator(
        color: AppColors.brand600,
        onRefresh: () async {
          ref.invalidate(ownerAppointmentsProvider);
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
              'Rendez-vous',
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
                tooltip: 'Ajouter un rendez-vous',
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

          // ── Search bar ──────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v.trim()),
                style: const TextStyle(fontSize: 13, color: AppColors.brand950),
                decoration: InputDecoration(
                  hintText: 'Rechercher par client, service…',
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
              child: Center(child: Text('Erreur : $e')),
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
                    appointment: items[i],
                    onStatusChanged: () => ref.invalidate(ownerAppointmentsProvider),
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
                f.label,
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

// ── Appointment tile ─────────────────────────────────────────────────────────

class _AppointmentTile extends ConsumerStatefulWidget {
  const _AppointmentTile({
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
    if (a.clientId == 'walk-in') {
      _clientName = a.clientName ?? 'Client sans compte';
      _clientPhone = a.clientPhone;
    } else {
      DatabaseService().getClientName(a.clientId).then((name) {
        if (mounted) setState(() => _clientName = name);
      });
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
      if (newStatus == 'completed') {
        await DatabaseService().awardPoints(
          userId: widget.appointment.clientId,
          salonId: widget.appointment.salonId,
          bookingAmount: widget.appointment.price,
          bookingId: widget.appointment.id,
        );
      }
      widget.onStatusChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  void _showAssignSheet(List<TeamMemberModel> members) {
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
                'Assigner à un membre',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
            ),
            const Divider(height: 1),
            if (members.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Aucun membre dans l\'équipe',
                  style: TextStyle(color: AppColors.secondary400),
                ),
              )
            else
              ...members.map((m) => ListTile(
                    leading: CircleAvatar(
                      backgroundColor: AppColors.brand50,
                      child: Text(
                        m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                        style: const TextStyle(
                          color: AppColors.brand600,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    title: Text(m.name,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      m.role == 'gerant' ? 'Gérant(e)' : 'Employé(e)',
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
              child: Text(
                a.serviceName,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
            ),
            const Divider(height: 1),
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
              title: const Text('Marquer comme terminé',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
              title: const Text('Assigner à un membre',
                  style: TextStyle(fontWeight: FontWeight.w600)),
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
              title: const Text('Annuler le rendez-vous',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                _updateStatus('cancelled');
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.appointment;

    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr =
        DateFormat('EEE d MMM', 'fr_FR').format(a.dateTime);

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
                  '${a.price.toStringAsFixed(0)} MAD',
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
    final (icon, msg) = switch (filter) {
      _Filter.today => (
          Icons.calendar_today_outlined,
          "Aucun rendez-vous aujourd'hui"
        ),
      _Filter.upcoming => (
          Icons.event_available_outlined,
          'Aucun rendez-vous à venir'
        ),
      _Filter.completed => (
          Icons.check_circle_outline_rounded,
          'Aucun rendez-vous terminé'
        ),
      _Filter.cancelled => (
          Icons.cancel_outlined,
          'Aucun rendez-vous annulé'
        ),
      _ => (Icons.calendar_month_outlined, 'Aucun rendez-vous pour l\'instant'),
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
  final _clientPhoneCtrl = TextEditingController();
  Map<String, dynamic>? _selectedService;
  TeamMemberModel? _selectedMember;
  DateTime _selectedDate = DateTime.now();
  TimeOfDay _selectedTime = TimeOfDay.now();
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _snapTimeToOpenHours();
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _clientPhoneCtrl.dispose();
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

  Future<void> _submit() async {
    final clientName = _clientNameCtrl.text.trim();
    if (clientName.isEmpty) {
      _showError('Veuillez entrer le nom du client');
      return;
    }
    if (_selectedService == null) {
      _showError('Veuillez sélectionner un service');
      return;
    }
    if (_selectedMember == null) {
      _showError('Veuillez sélectionner un employé');
      return;
    }
    if (!_isDayOpen(_selectedDate)) {
      _showError('Le salon est fermé ce jour-là');
      return;
    }
    // Check member unavailability
    final isoDate =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    if (_selectedMember!.unavailableDates.contains(isoDate)) {
      _showError('${_selectedMember!.name} est indisponible ce jour-là');
      return;
    }

    // Check if the selected time falls within an unavailable slot
    final duration = _selectedService!['duration'] as int? ?? 30;
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
          _showError('${_selectedMember!.name} est indisponible sur ce créneau (${parts[0]} - ${parts[1]})');
          return;
        }
      }
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

      final serviceName = _selectedService!['name'] as String? ?? 'Service';
      final price = (_selectedService!['price'] as num?)?.toDouble() ?? 0.0;

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
              '${_selectedMember!.name} a déjà un RDV à $conflictTime');
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
        clientPhone: _clientPhoneCtrl.text.trim().isNotEmpty ? _clientPhoneCtrl.text.trim() : null,
        assignedMemberId: _selectedMember!.id,
        assignedMemberName: _selectedMember!.name,
      );

      await DatabaseService().createAppointment(appointment);

      // Notify the assigned member
      final timeLabel =
          '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
      await DatabaseService().saveNotification(
        userId: 'team_${widget.salon.id}_${_selectedMember!.id}',
        title: 'Nouveau RDV assigné',
        body: '$serviceName avec $clientName le ${DateFormat('d MMM', 'fr_FR').format(dateTime)} à $timeLabel',
        type: 'assignment',
      );

      widget.onCreated();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('RDV créé avec succès'),
            backgroundColor: Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Erreur : $e');
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final services = widget.salon.services;
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
              'Nouveau rendez-vous',
              style: GoogleFonts.dmSans(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Ajoutez un rendez-vous reçu par téléphone ou WhatsApp',
              style: TextStyle(fontSize: 12, color: AppColors.secondary400),
            ),
            const SizedBox(height: 20),

            // Client name
            _label('Nom du client *'),
            const SizedBox(height: 6),
            TextField(
              controller: _clientNameCtrl,
              style: const TextStyle(fontSize: 14, color: AppColors.brand950),
              decoration: _inputDecoration('ex. Mohamed Alami'),
            ),
            const SizedBox(height: 16),

            // Client phone
            _label('Téléphone'),
            const SizedBox(height: 6),
            TextField(
              controller: _clientPhoneCtrl,
              keyboardType: TextInputType.phone,
              style: const TextStyle(fontSize: 14, color: AppColors.brand950),
              decoration: _inputDecoration('ex. 0612345678'),
            ),
            const SizedBox(height: 16),

            // Service selection
            _label('Service *'),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.secondary200),
                borderRadius: BorderRadius.circular(10),
                color: AppColors.secondary50,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  value: _selectedService != null
                      ? services.indexOf(_selectedService!)
                      : null,
                  hint: const Text('Sélectionner un service',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.secondary400)),
                  items: List.generate(services.length, (i) {
                    final s = services[i];
                    final name = s['name'] as String? ?? '';
                    final price =
                        (s['price'] as num?)?.toStringAsFixed(0) ?? '0';
                    final dur = s['duration'] as int? ?? 30;
                    return DropdownMenuItem(
                      value: i,
                      child: Text(
                        '$name · $price MAD · ${dur}min',
                        style: const TextStyle(
                            fontSize: 13, color: AppColors.brand950),
                      ),
                    );
                  }),
                  onChanged: (i) {
                    if (i != null) {
                      setState(() {
                        _selectedService = services[i];
                        _selectedMember = null;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Employee selection (filtered by selected service)
            _label('Employé *'),
            const SizedBox(height: 6),
            Builder(builder: (_) {
              final serviceName =
                  _selectedService?['name'] as String? ?? '';
              final filteredMembers = serviceName.isEmpty
                  ? widget.teamMembers
                  : widget.teamMembers
                      .where((m) =>
                          m.isActive &&
                          m.assignedServiceNames.contains(serviceName))
                      .toList();
              if (_selectedService == null) {
                return const Text(
                  'Sélectionnez d\'abord un service',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.secondary400),
                );
              }
              if (filteredMembers.isEmpty) {
                return const Text(
                  'Aucun employé assigné à ce service',
                  style: TextStyle(
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
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: selected
                                ? AppColors.brand500
                                : AppColors.secondary200,
                            child: selected
                                ? const Icon(Icons.check,
                                    size: 12, color: Colors.white)
                                : Text(
                                    m.name.isNotEmpty
                                        ? m.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.secondary500),
                                  ),
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
            _label('Date *'),
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
            _label('Heure *'),
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
                  child: const Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          size: 16, color: Color(0xFFDC2626)),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Le salon est fermé ce jour-là',
                          style: TextStyle(
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
                      label: 'Matin',
                      icon: Icons.wb_sunny_outlined,
                      slots: morning,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (afternoon.isNotEmpty)
                    _timeSlotSection(
                      label: 'Après-midi',
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
                    const Text('Résumé',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand700)),
                    const SizedBox(height: 6),
                    Text(
                      '${_selectedService!['name']} · ${(_selectedService!['price'] as num?)?.toStringAsFixed(0) ?? '0'} MAD · ${_selectedService!['duration'] ?? 30} min',
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.brand950),
                    ),
                    if (_selectedMember != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Avec ${_selectedMember!.name}',
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
                  _loading ? 'Création...' : 'Créer le rendez-vous',
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
              '${slots.length} créneaux',
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
              return GestureDetector(
                onTap: () {
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
                    color: isSelected ? AppColors.brand600 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.brand600
                          : AppColors.secondary200,
                      width: isSelected ? 1.5 : 1,
                    ),
                    boxShadow: isSelected
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
                      color: isSelected
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
