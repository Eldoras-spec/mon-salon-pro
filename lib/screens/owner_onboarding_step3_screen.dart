import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../services/app_localizations.dart';
import 'owner_onboarding_step5_screen.dart';

class DaySchedule {
  final String dayName;
  bool isOpen;
  TimeOfDay? openTime;
  TimeOfDay? closeTime;

  DaySchedule({
    required this.dayName,
    this.isOpen = true,
    this.openTime = const TimeOfDay(hour: 9, minute: 0),
    this.closeTime = const TimeOfDay(hour: 18, minute: 0),
  });
}

const List<Map<String, String>> _kTimezones = [
  {'label': 'Casablanca (GMT+1)', 'value': 'Africa/Casablanca'},
  {'label': 'Paris (GMT+1/+2)', 'value': 'Europe/Paris'},
  {'label': 'London (GMT+0/+1)', 'value': 'Europe/London'},
  {'label': 'New York (GMT-5/-4)', 'value': 'America/New_York'},
  {'label': 'Chicago (GMT-6/-5)', 'value': 'America/Chicago'},
  {'label': 'Denver (GMT-7/-6)', 'value': 'America/Denver'},
  {'label': 'Los Angeles (GMT-8/-7)', 'value': 'America/Los_Angeles'},
  {'label': 'Dubai (GMT+4)', 'value': 'Asia/Dubai'},
  {'label': 'Riyadh (GMT+3)', 'value': 'Asia/Riyadh'},
  {'label': 'Tokyo (GMT+9)', 'value': 'Asia/Tokyo'},
  {'label': 'Sydney (GMT+10/+11)', 'value': 'Australia/Sydney'},
];

class OwnerOnboardingStep3Screen extends StatefulWidget {
  final Map<String, dynamic> salonData;
  const OwnerOnboardingStep3Screen({super.key, required this.salonData});

  @override
  State<OwnerOnboardingStep3Screen> createState() =>
      _OwnerOnboardingStep3ScreenState();
}

class _OwnerOnboardingStep3ScreenState
    extends State<OwnerOnboardingStep3Screen> {
  String _selectedTimezone = 'Africa/Casablanca';

  final List<DaySchedule> _schedule = [
    DaySchedule(dayName: 'Lundi', isOpen: true),
    DaySchedule(dayName: 'Mardi', isOpen: true),
    DaySchedule(dayName: 'Mercredi', isOpen: true),
    DaySchedule(
      dayName: 'Jeudi',
      isOpen: true,
      closeTime: const TimeOfDay(hour: 20, minute: 0),
    ),
    DaySchedule(
      dayName: 'Vendredi',
      isOpen: true,
      closeTime: const TimeOfDay(hour: 20, minute: 0),
    ),
    DaySchedule(
      dayName: 'Samedi',
      isOpen: false,
      openTime: const TimeOfDay(hour: 10, minute: 0),
      closeTime: const TimeOfDay(hour: 16, minute: 0),
    ),
    DaySchedule(
      dayName: 'Dimanche',
      isOpen: false,
      openTime: const TimeOfDay(hour: 10, minute: 0),
      closeTime: const TimeOfDay(hour: 16, minute: 0),
    ),
  ];

  // ── Timezone ─────────────────────────────────────────────────────────────────

  String get _timezoneLabel =>
      _kTimezones.firstWhere(
        (t) => t['value'] == _selectedTimezone,
        orElse: () => {'label': _selectedTimezone, 'value': _selectedTimezone},
      )['label']!;

  void _showTimezoneSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.symmetric(vertical: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.secondary200,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Text(
              AppLocalizations.of(context)?.tr('onboarding_step3_timezone') ?? 'Choisir le fuseau horaire',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
          ),
          const Divider(height: 1, color: AppColors.secondary100),
          Flexible(
            child: ListView.separated(
              itemCount: _kTimezones.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppColors.secondary100),
              itemBuilder: (_, i) {
                final tz = _kTimezones[i];
                final selected = tz['value'] == _selectedTimezone;
                return ListTile(
                  title: Text(
                    tz['label']!,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: selected
                          ? AppColors.brand700
                          : AppColors.secondary800,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(Icons.check_rounded,
                          color: AppColors.brand600, size: 18)
                      : null,
                  onTap: () {
                    setState(() => _selectedTimezone = tz['value']!);
                    Navigator.pop(sheetCtx);
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }

  // ── Time picker ──────────────────────────────────────────────────────────────

  Future<void> _selectTime(
    BuildContext context,
    DaySchedule day,
    bool isStart,
  ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStart
          ? (day.openTime ?? const TimeOfDay(hour: 9, minute: 0))
          : (day.closeTime ?? const TimeOfDay(hour: 18, minute: 0)),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          day.openTime = picked;
        } else {
          day.closeTime = picked;
        }
      });
    }
  }

  void _copyMondayToWeekdays() {
    final mon = _schedule[0];
    setState(() {
      for (int i = 1; i <= 4; i++) {
        _schedule[i].isOpen = true;
        _schedule[i].openTime = mon.openTime;
        _schedule[i].closeTime = mon.closeTime;
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)?.tr('onboarding_step3_copied') ?? 'Horaires du lundi copiés vers Mar–Ven'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _handleNext() {
    final updatedData = Map<String, dynamic>.from(widget.salonData);

    final Map<String, dynamic> workingHours = {};
    for (var day in _schedule) {
      if (day.isOpen) {
        workingHours[day.dayName.toLowerCase()] = {
          'isOpen': true,
          'open':
              '${day.openTime!.hour.toString().padLeft(2, '0')}:${day.openTime!.minute.toString().padLeft(2, '0')}',
          'close':
              '${day.closeTime!.hour.toString().padLeft(2, '0')}:${day.closeTime!.minute.toString().padLeft(2, '0')}',
        };
      } else {
        workingHours[day.dayName.toLowerCase()] = {'isOpen': false};
      }
    }

    updatedData['workingHours'] = workingHours;
    updatedData['timezone'] = _selectedTimezone;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            OwnerOnboardingStep5Screen(salonData: updatedData),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(child: _buildFormSection()),
    );
  }

  Widget _buildFormSection() {
    final l = AppLocalizations.of(context);
    return Container(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Nav
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          border: Border.all(color: AppColors.secondary100),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.arrow_back,
                          size: 12,
                          color: AppColors.secondary500,
                        ),
                      ),
                      label: Text(
                        l?.tr('onboarding_back') ?? 'Retour',
                        style: const TextStyle(
                          color: AppColors.secondary500,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Progress
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l?.tr('onboarding_step3_title') ?? 'Horaires d\'ouverture',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand900,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l?.tr('onboarding_step3_step') ?? 'Étape 4 sur 6',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.brand300,
                          borderRadius: BorderRadius.horizontal(
                            left: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                        child: Container(height: 6, color: AppColors.brand300)),
                    const SizedBox(width: 2),
                    Expanded(
                        child: Container(height: 6, color: AppColors.brand500)),
                    const SizedBox(width: 2),
                    Expanded(
                        child: Container(
                            height: 6, color: AppColors.secondary100)),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Container(
                        height: 6,
                        decoration: const BoxDecoration(
                          color: AppColors.secondary100,
                          borderRadius: BorderRadius.horizontal(
                            right: Radius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 32),

                // Header
                Text(
                  l?.tr('onboarding_step3_subtitle') ?? 'Définissez votre planning hebdomadaire',
                  style: GoogleFonts.dmSans(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Configurez vos horaires d\'ouverture habituels. Vous pourrez les ajuster pour les jours fériés ou événements spéciaux.',
                  style: TextStyle(
                    color: AppColors.secondary500,
                    height: 1.5,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 16),

                // Timezone banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    border: Border.all(color: AppColors.secondary100),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.language,
                        color: AppColors.brand500,
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _timezoneLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: _showTimezoneSelector,
                        child: Text(
                          l?.tr('onboarding_step3_timezone_change') ?? 'Changer',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.brand600,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Copy shortcut
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _copyMondayToWeekdays,
                    icon: const Icon(Icons.copy, size: 14),
                    label: Text(
                      l?.tr('onboarding_step3_copy_monday') ?? 'Copier Lun → Mar–Ven',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.brand600,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Days list
                ..._schedule.map((day) => _buildDayRow(day)),

                const SizedBox(height: 32),
                const Divider(color: AppColors.secondary100, height: 1),
                const SizedBox(height: 24),

                // Actions
                CustomButton(
                  text: l?.tr('onboarding_step3_continue') ?? 'Continuer vers l\'équipe',
                  onPressed: _handleNext,
                  icon: Icons.arrow_forward,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: const BorderSide(color: AppColors.secondary200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.arrow_back,
                            size: 14, color: AppColors.secondary700),
                        const SizedBox(width: 8),
                        Text(
                          l?.tr('onboarding_back') ?? 'Retour',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Day row — two-line layout to avoid overflow ───────────────────────────

  Widget _buildDayRow(DaySchedule day) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: day.isOpen ? Colors.white : AppColors.secondary50,
        border: Border.all(color: AppColors.secondary200),
        borderRadius: BorderRadius.circular(12),
      ),
      // Stack lets the indicator stretch to the content's natural height
      // without needing CrossAxisAlignment.stretch in an unbounded context.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Stack(
          children: [
            // Left colour indicator — stretches via Positioned top+bottom=0
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Container(
                width: 4,
                color: day.isOpen ? AppColors.brand500 : Colors.transparent,
              ),
            ),

            // Content (drives the Stack's height)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Line 1 — day name + toggle
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          day.dayName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: day.isOpen
                                ? AppColors.brand950
                                : AppColors.secondary400,
                          ),
                        ),
                      ),
                      Switch(
                        value: day.isOpen,
                        onChanged: (val) =>
                            setState(() => day.isOpen = val),
                        activeThumbColor: AppColors.brand500,
                        activeTrackColor: AppColors.brand200,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),

                  // Line 2 — times or "Fermé"
                  if (day.isOpen) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTimeSelector(
                            day.openTime,
                            () => _selectTime(context, day, true),
                          ),
                        ),
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            '→',
                            style: TextStyle(
                              color: AppColors.secondary400,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildTimeSelector(
                            day.closeTime,
                            () => _selectTime(context, day, false),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                  ] else ...[
                    const SizedBox(height: 4),
                    Text(
                      AppLocalizations.of(context)?.tr('onboarding_step3_closed') ?? 'Fermé',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector(TimeOfDay? time, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.secondary50,
          border: Border.all(color: AppColors.secondary200),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.access_time,
              size: 13,
              color: AppColors.secondary400,
            ),
            const SizedBox(width: 6),
            Text(
              time?.format(context) ?? '--:--',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.secondary700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
