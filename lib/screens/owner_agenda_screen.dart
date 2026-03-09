import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/team_member_model.dart';
import '../services/database_service.dart';

const _memberColors = [
  Color(0xFFFDE68A), // amber
  Color(0xFFA7F3D0), // emerald
  Color(0xFFBFDBFE), // blue
  Color(0xFFFBCFE8), // pink
  Color(0xFFC4B5FD), // violet
  Color(0xFFFED7AA), // orange
  Color(0xFF99F6E4), // teal
];

const _memberTextColors = [
  Color(0xFF92400E), // amber dark
  Color(0xFF065F46), // emerald dark
  Color(0xFF1E40AF), // blue dark
  Color(0xFF9D174D), // pink dark
  Color(0xFF5B21B6), // violet dark
  Color(0xFFC2410C), // orange dark
  Color(0xFF115E59), // teal dark
];

class OwnerAgendaScreen extends StatefulWidget {
  final String salonId;
  const OwnerAgendaScreen({super.key, required this.salonId});

  @override
  State<OwnerAgendaScreen> createState() => _OwnerAgendaScreenState();
}

class _OwnerAgendaScreenState extends State<OwnerAgendaScreen> {
  final _db = DatabaseService();

  DateTime _selectedDate = DateTime.now();
  List<TeamMemberModel> _members = [];
  List<AppointmentModel> _appointments = [];
  bool _loading = true;

  // Timeline config
  static const int _startHour = 8;
  static const int _endHour = 20;
  static const double _pixelsPerMinute = 2.5;
  static const double _timeColumnWidth = 44.0;
  static const double _memberColumnWidth = 120.0;

  final ScrollController _verticalController = ScrollController();
  final ScrollController _headerScrollController = ScrollController();
  final ScrollController _gridScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadData();
    // Sync horizontal scroll between header and grid
    _headerScrollController.addListener(() {
      if (_gridScrollController.hasClients) {
        _gridScrollController.jumpTo(_headerScrollController.offset);
      }
    });
    _gridScrollController.addListener(() {
      if (_headerScrollController.hasClients) {
        _headerScrollController.jumpTo(_gridScrollController.offset);
      }
    });
  }

  @override
  void dispose() {
    _verticalController.dispose();
    _headerScrollController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final members = await _db.getTeamMembersOnce(widget.salonId);
      final appointments =
          await _db.getSalonAppointmentsForDate(widget.salonId, _selectedDate);
      if (mounted) {
        setState(() {
          _members = members.where((m) => m.isActive).toList();
          _appointments = appointments;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Agenda load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  void _changeDate(int delta) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: delta));
    });
    _loadData();
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
    _loadData();
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  // Total height of the timeline
  double get _timelineHeight =>
      (_endHour - _startHour) * 60 * _pixelsPerMinute;

  // Y offset for a given time
  double _yForTime(DateTime dt) {
    final minutes = (dt.hour - _startHour) * 60 + dt.minute;
    return minutes * _pixelsPerMinute;
  }

  List<AppointmentModel> _appointmentsForMember(String memberId) {
    return _appointments
        .where((a) => a.assignedMemberId == memberId)
        .toList();
  }

  List<AppointmentModel> _unassignedAppointments() {
    return _appointments.where((a) => a.assignedMemberId == null).toList();
  }

  String get _fullDateLabel {
    final f = DateFormat('EEE d MMMM', 'fr_FR').format(_selectedDate);
    return f[0].toUpperCase() + f.substring(1);
  }

  Future<void> _shareAgenda() async {
    final dateLabel =
        DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_selectedDate);
    final buf = StringBuffer();
    buf.writeln('📅 Planning du $dateLabel');
    buf.writeln('─────────────────────');

    if (_appointments.isEmpty) {
      buf.writeln('Aucun rendez-vous prévu.');
    } else {
      for (final m in _members) {
        final memberAppts = _appointmentsForMember(m.id);
        if (memberAppts.isEmpty) continue;
        memberAppts.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        buf.writeln('\n👤 ${m.name}');
        for (final a in memberAppts) {
          final start = DateFormat('HH:mm').format(a.dateTime);
          final end = DateFormat('HH:mm')
              .format(a.dateTime.add(Duration(minutes: a.durationMinutes)));
          final client = a.clientName ?? 'Client';
          buf.writeln('  ⏰ $start - $end | ${a.serviceName} | $client');
        }
      }
      final unassigned = _unassignedAppointments();
      if (unassigned.isNotEmpty) {
        unassigned.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        buf.writeln('\n📌 Non assigné');
        for (final a in unassigned) {
          final start = DateFormat('HH:mm').format(a.dateTime);
          final client = a.clientName ?? 'Client';
          buf.writeln('  ⏰ $start | ${a.serviceName} | $client');
        }
      }
    }

    buf.writeln('\n─────────────────────');
    buf.writeln('Total: ${_appointments.length} RDV');

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Planning copié ! Collez-le dans WhatsApp ou SMS.'),
          backgroundColor: Color(0xFF16A34A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Text(
              'Agenda',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.chevron_left, color: AppColors.brand600, size: 22),
              onPressed: () => _changeDate(-1),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
            GestureDetector(
              onTap: isToday ? null : _goToToday,
              child: Text(
                isToday ? "Aujourd'hui" : _fullDateLabel,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand950,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, color: AppColors.brand600, size: 22),
              onPressed: () => _changeDate(1),
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32),
            ),
          ],
        ),
        titleSpacing: 0,
        actions: const [SizedBox(width: 8)],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: _shareAgenda,
        backgroundColor: AppColors.brand700,
        child: const Icon(Icons.copy_rounded, color: Colors.white, size: 20),
      ),
      body: RefreshIndicator(
        color: AppColors.brand600,
        onRefresh: () async {
          await _loadData();
        },
        child: Column(
          children: [
            // Member header row
            if (!_loading && _members.isNotEmpty)
              _buildMemberHeader(),

            // Timeline grid
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.brand600))
                  : _members.isEmpty
                      ? _buildEmptyState()
                      : _buildTimelineGrid(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberHeader() {
    final unassigned = _unassignedAppointments();
    return Container(
      height: 76,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Empty space for time column
          SizedBox(width: _timeColumnWidth),
          // Scrollable member headers
          Expanded(
            child: SingleChildScrollView(
              controller: _headerScrollController,
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ..._members.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final member = entry.value;
                    final color = _memberColors[idx % _memberColors.length];
                    final apptCount = _appointmentsForMember(member.id).length;
                    return SizedBox(
                      width: _memberColumnWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color,
                            child: Text(
                              _initials(member.name),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _memberTextColors[
                                    idx % _memberTextColors.length],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.brand950,
                            ),
                          ),
                          Text(
                            '$apptCount RDV',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary400,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  // Unassigned column if needed
                  if (unassigned.isNotEmpty)
                    SizedBox(
                      width: _memberColumnWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.secondary200,
                            child: const Icon(Icons.help_outline,
                                size: 16, color: AppColors.secondary500),
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Non assigné',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondary500,
                            ),
                          ),
                          Text(
                            '${unassigned.length} RDV',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary400,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineGrid() {
    final unassigned = _unassignedAppointments();

    const double topPadding = 12.0;

    return SingleChildScrollView(
      controller: _verticalController,
      child: SizedBox(
        height: _timelineHeight + topPadding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time labels column
            SizedBox(
              width: _timeColumnWidth,
              height: _timelineHeight + topPadding,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (int h = _startHour; h <= _endHour; h++)
                    Positioned(
                      top: topPadding + (h - _startHour) * 60 * _pixelsPerMinute - 7,
                      left: 0,
                      right: 4,
                      child: Text(
                        '${h.toString().padLeft(2, '0')}:00',
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary400,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Member columns (horizontally scrollable)
            Expanded(
              child: SingleChildScrollView(
                controller: _gridScrollController,
                scrollDirection: Axis.horizontal,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._members.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final member = entry.value;
                      return _buildMemberColumn(
                        member.id,
                        idx,
                        _appointmentsForMember(member.id),
                      );
                    }),
                    if (unassigned.isNotEmpty)
                      _buildMemberColumn(
                        null,
                        _members.length,
                        unassigned,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberColumn(
      String? memberId, int colorIndex, List<AppointmentModel> appts) {
    final bgColor = memberId != null
        ? _memberColors[colorIndex % _memberColors.length]
        : AppColors.secondary200;
    final textColor = memberId != null
        ? _memberTextColors[colorIndex % _memberTextColors.length]
        : AppColors.secondary600;

    const double topPadding = 12.0;

    return Container(
      width: _memberColumnWidth,
      height: _timelineHeight + topPadding,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: AppColors.secondary100, width: 0.5),
        ),
      ),
      child: Stack(
        children: [
          // Hour grid lines
          for (int h = _startHour; h <= _endHour; h++)
            Positioned(
              top: topPadding + (h - _startHour) * 60 * _pixelsPerMinute,
              left: 0,
              right: 0,
              child: Divider(
                height: 0.5,
                thickness: 0.5,
                color: AppColors.secondary100,
              ),
            ),

          // Half-hour grid lines (lighter)
          for (int h = _startHour; h < _endHour; h++)
            Positioned(
              top: topPadding + (h - _startHour) * 60 * _pixelsPerMinute + 30 * _pixelsPerMinute,
              left: 0,
              right: 0,
              child: Divider(
                height: 0.5,
                thickness: 0.3,
                color: AppColors.secondary50,
              ),
            ),

          // Current time indicator (red line)
          if (DateUtils.isSameDay(_selectedDate, DateTime.now()))
            _buildNowIndicator(),

          // Appointment blocks
          ...appts.map((appt) {
            final top = topPadding + _yForTime(appt.dateTime).clamp(0.0, _timelineHeight);
            final height =
                (appt.durationMinutes * _pixelsPerMinute).clamp(20.0, _timelineHeight + topPadding - top);
            final endTime =
                appt.dateTime.add(Duration(minutes: appt.durationMinutes));

            return Positioned(
              top: top,
              left: 3,
              right: 3,
              height: height,
              child: GestureDetector(
                onTap: () => _showAppointmentDetails(appt, colorIndex),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bgColor.withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: bgColor,
                      width: 1,
                    ),
                  ),
                  clipBehavior: Clip.hardEdge,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${DateFormat('HH:mm').format(appt.dateTime)} - ${DateFormat('HH:mm').format(endTime)}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (height > 35 && appt.assignedMemberName != null)
                        Text(
                          appt.assignedMemberName!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: textColor,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (height > 45)
                        Text(
                          appt.serviceName,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: textColor.withValues(alpha: 0.85),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (height > 65 && appt.clientName != null)
                        Text(
                          appt.clientName!.length > 10
                              ? '${appt.clientName!.substring(0, 10)}…'
                              : appt.clientName!,
                          style: TextStyle(
                            fontSize: 10,
                            color: textColor.withValues(alpha: 0.7),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildNowIndicator() {
    final now = DateTime.now();
    final rawTop = _yForTime(now);
    if (rawTop < 0 || rawTop > _timelineHeight) return const SizedBox.shrink();

    return Positioned(
      top: 12.0 + rawTop,
      left: 0,
      right: 0,
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFEF4444),
              shape: BoxShape.circle,
            ),
          ),
          Expanded(
            child: Container(height: 1.5, color: const Color(0xFFEF4444)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined,
              size: 48, color: AppColors.secondary300),
          const SizedBox(height: 12),
          const Text(
            'Aucun membre dans l\'équipe',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary500,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ajoutez des membres pour voir le planning',
            style: TextStyle(fontSize: 13, color: AppColors.secondary400),
          ),
        ],
      ),
    );
  }

  void _showAppointmentDetails(AppointmentModel appt, int colorIndex) async {
    final endTime = appt.dateTime.add(Duration(minutes: appt.durationMinutes));
    final dateStr =
        DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(appt.dateTime);
    final capitalDate = dateStr[0].toUpperCase() + dateStr.substring(1);

    final color = colorIndex < _members.length
        ? _memberColors[colorIndex % _memberColors.length]
        : AppColors.secondary200;

    // Fetch phone: from appointment field, or from user profile
    String? phone = appt.clientPhone;
    if ((phone == null || phone.isEmpty) &&
        appt.clientId != 'walk-in') {
      phone = await _db.getClientPhone(appt.clientId);
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Service name
            Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    appt.serviceName,
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Details
            if (appt.clientName != null) ...[
              _detailRow(Icons.face_outlined, appt.clientName!),
              const SizedBox(height: 8),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              _detailRow(Icons.phone_outlined, phone),
              const SizedBox(height: 8),
            ],
            _detailRow(Icons.calendar_today_outlined, capitalDate),
            const SizedBox(height: 8),
            _detailRow(
              Icons.access_time,
              '${DateFormat('HH:mm').format(appt.dateTime)} - ${DateFormat('HH:mm').format(endTime)}  (${appt.durationMinutes} min)',
            ),
            const SizedBox(height: 8),
            if (appt.assignedMemberName != null) ...[
              _detailRow(Icons.person_outline, appt.assignedMemberName!),
              const SizedBox(height: 8),
            ],
            _detailRow(
              Icons.monetization_on_outlined,
              '${appt.price.toStringAsFixed(0)} MAD',
            ),
            const SizedBox(height: 8),
            _detailRow(
              Icons.info_outline,
              appt.status == 'upcoming'
                  ? 'À venir'
                  : appt.status == 'completed'
                      ? 'Terminé'
                      : 'Annulé',
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.secondary400),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppColors.brand950),
          ),
        ),
      ],
    );
  }
}
