import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/timezone_helper.dart';

// `salon.workingHours` is keyed by lowercase French day names — set this
// way at onboarding (cf owner_onboarding_step3_screen.dart) and used by
// every other screen in the app (owner_appointments_screen.dart,
// member_home_screen.dart, owner_salon_screen.dart). MUST match.
const _dayKeys = [
  'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
];

/// Bottom sheet that lets the owner / employee reschedule an existing
/// appointment. Available slots are filtered against the assigned
/// member's availability (recurring days off, full-day blocks, hourly
/// blocks, existing appointments). Returns true if the appointment was
/// rescheduled, false / null otherwise.
Future<bool?> showRescheduleAppointmentSheet({
  required BuildContext context,
  required AppointmentModel appointment,
  required SalonModel salon,
  required List<TeamMemberModel> teamMembers,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _RescheduleSheet(
      appointment: appointment,
      salon: salon,
      teamMembers: teamMembers,
    ),
  );
}

class _RescheduleSheet extends StatefulWidget {
  const _RescheduleSheet({
    required this.appointment,
    required this.salon,
    required this.teamMembers,
  });
  final AppointmentModel appointment;
  final SalonModel salon;
  final List<TeamMemberModel> teamMembers;

  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  late DateTime _selectedDate;
  String? _selectedTime; // "HH:mm" — null until user picks
  List<AppointmentModel> _dayAppointments = const [];
  bool _loadingSlots = false;
  bool _saving = false;

  TeamMemberModel? get _assignedMember {
    final id = widget.appointment.assignedMemberId;
    if (id == null) return null;
    for (final m in widget.teamMembers) {
      if (m.id == id) return m;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    final dt = widget.appointment.dateTime;
    _selectedDate = DateTime(dt.year, dt.month, dt.day);
    // Pre-fill the existing time so the user sees the current slot
    // highlighted (it is allowed to "pick" the same slot — no-op save).
    _selectedTime =
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    _loadDayAppointments();
  }

  Future<void> _loadDayAppointments() async {
    setState(() => _loadingSlots = true);
    try {
      final appts = await DatabaseService()
          .getSalonAppointmentsForDate(widget.salon.id, _selectedDate);
      // Exclude the current appointment from the busy set so its own slot
      // doesn't appear as conflicting with itself.
      final filtered =
          appts.where((a) => a.id != widget.appointment.id).toList();
      if (mounted) setState(() => _dayAppointments = filtered);
    } catch (_) {
      if (mounted) setState(() => _dayAppointments = const []);
    } finally {
      if (mounted) setState(() => _loadingSlots = false);
    }
  }

  Map<String, dynamic>? _hoursForDate(DateTime d) {
    // Salon-wide closure overrides weekly hours (no slots that day).
    if (widget.salon.isClosedOnDate(d)) return null;
    final key = _dayKeys[d.weekday - 1];
    return widget.salon.workingHours[key] as Map<String, dynamic>?;
  }

  bool _isDayOpen(DateTime d) {
    final h = _hoursForDate(d);
    return h != null && h['isOpen'] == true;
  }

  /// 30-min slots. We do NOT skip past slots when rescheduling to a future
  /// date; for today, we still skip past times (no point booking 13:00
  /// when it's already 15:00).
  List<String> _generateSlots() {
    final h = _hoursForDate(_selectedDate);
    if (h == null || h['isOpen'] != true) return const [];
    final openParts = (h['open'] as String).split(':');
    final closeParts = (h['close'] as String).split(':');
    final openMin = int.parse(openParts[0]) * 60 + int.parse(openParts[1]);
    final closeMin = int.parse(closeParts[0]) * 60 + int.parse(closeParts[1]);
    // Anchor "now" to the SALON timezone, not the device. Otherwise an
    // owner travelling abroad (or testing on an emulator stuck in UTC)
    // sees stale slots from the salon's past or hides slots that are
    // still future from the salon's perspective.
    final salonNow = TimezoneHelper.salonNow(widget.salon.timezone);
    final isToday = _selectedDate.year == salonNow.year &&
        _selectedDate.month == salonNow.month &&
        _selectedDate.day == salonNow.day;
    final nowMin = salonNow.hour * 60 + salonNow.minute;
    final out = <String>[];
    for (int m = openMin; m < closeMin; m += 30) {
      if (isToday && m <= nowMin) continue;
      final hh = m ~/ 60;
      final mm = m % 60;
      out.add('${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}');
    }
    return out;
  }

  /// Mirror of `_isSlotBlocked` from owner_appointments_screen — but
  /// scoped to the appointment's existing assigned member (if any) and
  /// the appointment's own duration.
  bool _isSlotBlocked(String timeStr) {
    final member = _assignedMember;
    final duration = widget.appointment.durationMinutes;

    final parts = timeStr.split(':');
    final h = int.parse(parts[0]);
    final m = int.parse(parts[1]);
    // Wall-clock-UTC so the conflict comparison against `appt.dateTime`
    // (also wall-clock-UTC) is in the same space — local + later
    // `.toUtc()` would drift by the device's offset.
    final slotStart = DateTime.utc(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, h, m);
    final slotEnd = slotStart.add(Duration(minutes: duration));

    // Walk-in / unassigned: only check salon-level conflicts vs the
    // entire team. We treat any conflicting appointment booked at the
    // same time as blocking only when it overlaps every potential
    // member — i.e., never block. Owners can shuffle later via "Assigner
    // à un membre". The slot is open as long as the salon is open.
    if (member == null) return false;

    // Full-day unavailability (recurring + ad-hoc).
    if (member.isUnavailableOnDate(_selectedDate)) return true;

    // Hourly unavailability.
    final iso = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final unavailSlots = member.unavailableSlots[iso] ?? const [];
    for (final slot in unavailSlots) {
      final sp = slot.split('-');
      if (sp.length != 2) continue;
      final s = sp[0].split(':');
      final e = sp[1].split(':');
      final sMin = int.parse(s[0]) * 60 + int.parse(s[1]);
      final eMin = int.parse(e[0]) * 60 + int.parse(e[1]);
      final startMin = h * 60 + m;
      final endMin = startMin + duration;
      if (startMin < eMin && endMin > sMin) return true;
    }

    // Existing appointments for this member. All operands are now
    // wall-clock-UTC — direct comparison.
    for (final appt in _dayAppointments) {
      if (appt.assignedMemberId != member.id) continue;
      final apptStart = appt.dateTime;
      final apptEnd = apptStart.add(Duration(minutes: appt.durationMinutes));
      if (slotStart.isBefore(apptEnd) && slotEnd.isAfter(apptStart)) return true;
    }

    return false;
  }

  Future<void> _pickDate() async {
    // Bound the pickable range in salon TZ — without this, an owner in a
    // different TZ from the salon could pick a date that's already over
    // from the salon's perspective.
    final today = TimezoneHelper.salonToday(widget.salon.timezone);
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      selectableDayPredicate: (date) {
        if (!_isDayOpen(date)) return false;
        final m = _assignedMember;
        if (m != null && m.isUnavailableOnDate(date)) return false;
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
        _selectedDate = DateTime(picked.year, picked.month, picked.day);
        _selectedTime = null;
      });
      _loadDayAppointments();
    }
  }

  Future<void> _save() async {
    if (_selectedTime == null) return;
    final parts = _selectedTime!.split(':');
    final newDt = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
      int.parse(parts[0]),
      int.parse(parts[1]),
    );
    if (newDt.isAtSameMomentAs(widget.appointment.dateTime)) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() => _saving = true);
    try {
      await DatabaseService()
          .rescheduleAppointment(widget.appointment.id, newDt);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              (l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e')),
          backgroundColor: Colors.redAccent,
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final slots = _generateSlots();
    final dateLabel =
        DateFormat('EEEE d MMMM', 'fr_FR').format(_selectedDate);
    final memberLabel = _assignedMember?.name ??
        (l?.tr('appointments_no_member') ?? 'Aucun membre assigné');

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            l?.tr('appointments_reschedule_title') ?? 'Modifier l\'horaire',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.appointment.serviceName} · $memberLabel',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.secondary500),
          ),
          const SizedBox(height: 16),

          // Date row
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.brand200),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_today_rounded,
                      size: 18, color: AppColors.brand600),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      dateLabel,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.secondary400),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            l?.tr('appointments_pick_time') ?? 'Choisir un horaire',
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.secondary600),
          ),
          const SizedBox(height: 8),

          if (_loadingSlots)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (slots.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l?.tr('appointments_closed_that_day') ?? 'Salon fermé ce jour-là',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.secondary400),
              ),
            )
          else
            SizedBox(
              height: 200,
              child: SingleChildScrollView(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: slots.map((s) {
                    final blocked = _isSlotBlocked(s);
                    final selected = _selectedTime == s;
                    return GestureDetector(
                      onTap: blocked
                          ? null
                          : () => setState(() => _selectedTime = s),
                      child: Container(
                        width: 70,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: blocked
                              ? AppColors.secondary100
                              : (selected ? AppColors.brand600 : Colors.white),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: blocked
                                ? AppColors.secondary200
                                : (selected
                                    ? AppColors.brand600
                                    : AppColors.brand200),
                          ),
                        ),
                        child: Text(
                          s,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: blocked
                                ? AppColors.secondary300
                                : (selected ? Colors.white : AppColors.brand700),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_selectedTime == null || _saving) ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded, size: 18),
              label: Text(l?.tr('common_save') ?? 'Enregistrer'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand600,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
