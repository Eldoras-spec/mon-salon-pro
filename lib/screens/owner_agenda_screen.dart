import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:linked_scroll_controller/linked_scroll_controller.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/owner_tasks_provider.dart';
import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/team_member_model.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../utils/currency_helper.dart';
import '../widgets/member_avatar.dart';

const _memberColors = [
  Color(0xFFFDE68A), // amber
  Color(0xFFA7F3D0), // emerald
  Color(0xFFBFDBFE), // blue
  Color(0xFFD9F99D), // lime
  Color(0xFFC4B5FD), // violet
  Color(0xFFFED7AA), // orange
  Color(0xFF99F6E4), // teal
  Color(0xFFFECDD3), // rose
  Color(0xFFFBCFE8), // pink
  Color(0xFFBAE6FD), // sky
  Color(0xFFC7D2FE), // indigo
  Color(0xFFF5D0FE), // fuchsia
  Color(0xFFE2E8F0), // slate
];

const _memberTextColors = [
  Color(0xFF92400E), // amber dark
  Color(0xFF065F46), // emerald dark
  Color(0xFF1E40AF), // blue dark
  Color(0xFF3F6212), // lime dark
  Color(0xFF5B21B6), // violet dark
  Color(0xFFC2410C), // orange dark
  Color(0xFF115E59), // teal dark
  Color(0xFF9F1239), // rose dark
  Color(0xFF9D174D), // pink dark
  Color(0xFF075985), // sky dark
  Color(0xFF3730A3), // indigo dark
  Color(0xFF86198F), // fuchsia dark
  Color(0xFF475569), // slate dark
];

class OwnerAgendaScreen extends ConsumerStatefulWidget {
  final String salonId;
  final String currency;
  const OwnerAgendaScreen({super.key, required this.salonId, this.currency = 'MAD'});

  @override
  ConsumerState<OwnerAgendaScreen> createState() => _OwnerAgendaScreenState();
}

class _OwnerAgendaScreenState extends ConsumerState<OwnerAgendaScreen> {
  final _db = DatabaseService();

  DateTime _selectedDate = DateTime.now();
  DateTime _calendarMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _calendarOpen = false;
  List<TeamMemberModel> _members = [];
  List<AppointmentModel> _appointments = [];
  // Full month of appointments around the selected date — used to filter
  // [_appointments] in-memory on day swipe (no extra Firestore read).
  List<AppointmentModel> _selectedMonthApts = [];
  // Monthly appointments cache for calendar dots: { "2026-04-14": [AppointmentModel, ...] }
  Map<String, List<AppointmentModel>> _monthAppointments = {};
  bool _loading = true;

  // Live Firestore subscriptions — re-keyed when the month changes so
  // we keep one listener per visible month at most. New RDV created
  // anywhere will appear instantly without re-opening the screen.
  StreamSubscription<List<AppointmentModel>>? _selectedMonthSub;
  StreamSubscription<List<AppointmentModel>>? _calendarDotsSub;
  String? _selectedMonthKey; // 'yyyy-M'
  String? _calendarDotsKey;

  // Timeline config
  static const int _startHour = 8;
  static const int _endHour = 22;
  static const double _pixelsPerMinute = 2.5;
  static const double _timeColumnWidth = 44.0;
  static const double _memberColumnWidth = 120.0;

  final ScrollController _verticalController = ScrollController();
  // LinkedScrollControllerGroup keeps the header row and the grid row
  // horizontally in sync without manual jumpTo cascades. Drag in either
  // surface drives both — fixes the iOS overscroll-induced freeze that
  // the previous setState/listener pattern produced.
  final LinkedScrollControllerGroup _hScrollGroup = LinkedScrollControllerGroup();
  late final ScrollController _headerScrollController = _hScrollGroup.addAndGet();
  late final ScrollController _gridScrollController = _hScrollGroup.addAndGet();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _selectedMonthSub?.cancel();
    _calendarDotsSub?.cancel();
    _verticalController.dispose();
    _headerScrollController.dispose();
    _gridScrollController.dispose();
    super.dispose();
  }

  /// One-shot members load + ensure month subscription is active.
  /// Called from initState and as the RefreshIndicator handler.
  ///
  /// `_loading` starts true via the field default and is flipped to false
  /// by the stream listener on its first emission. We DON'T re-toggle
  /// `_loading` here on refresh: the subscription is already live so
  /// `_ensureSelectedMonthSubscription` no-ops, the listener doesn't
  /// re-fire, and `_loading=true` would otherwise stay forever and
  /// freeze the UI in a permanent spinner (RefreshIndicator handles
  /// its own pull-to-refresh spinner separately).
  Future<void> _loadData() async {
    try {
      final members = await _db.getTeamMembersOnce(widget.salonId);
      if (!mounted) return;
      setState(() {
        _members = members.where((m) => m.isActive).toList();
      });
      _ensureSelectedMonthSubscription(_selectedDate);
    } catch (e) {
      debugPrint('Agenda load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Re-subscribe to the live appointments stream for the month
  /// containing [forDate] if needed. Stream emissions update both the
  /// full-month buffer (used to filter on day swipe in-memory) and
  /// [_appointments] (the currently visible day). No-op if already
  /// subscribed to the same month.
  void _ensureSelectedMonthSubscription(DateTime forDate) {
    final key = '${forDate.year}-${forDate.month}';
    if (_selectedMonthKey == key && _selectedMonthSub != null) return;
    _selectedMonthKey = key;
    _selectedMonthSub?.cancel();

    final start = DateTime(forDate.year, forDate.month, 1);
    final end = DateTime(forDate.year, forDate.month + 1, 0, 23, 59);
    _selectedMonthSub = _db
        .streamSalonAppointmentsForRange(widget.salonId, start, end)
        .listen((apts) {
      if (!mounted) return;
      setState(() {
        _selectedMonthApts = apts;
        _appointments = apts
            .where((a) => DateUtils.isSameDay(a.dateTime, _selectedDate))
            .toList();
        _loading = false;
      });
    }, onError: (e) {
      debugPrint('Selected-month stream error: $e');
      if (mounted) setState(() => _loading = false);
    });
  }

  /// Live subscription for the calendar overlay dots — separate from the
  /// selected-date stream because the user can navigate the calendar
  /// month without changing the visible day. When months coincide,
  /// Firestore client dedupes the underlying network listener so this
  /// is effectively free.
  void _ensureCalendarDotsSubscription(DateTime forMonth) {
    final key = '${forMonth.year}-${forMonth.month}';
    if (_calendarDotsKey == key && _calendarDotsSub != null) return;
    _calendarDotsKey = key;
    _calendarDotsSub?.cancel();

    final start = DateTime(forMonth.year, forMonth.month, 1);
    final end = DateTime(forMonth.year, forMonth.month + 1, 0, 23, 59);
    _calendarDotsSub = _db
        .streamSalonAppointmentsForRange(widget.salonId, start, end)
        .listen((apts) {
      if (!mounted) return;
      final map = <String, List<AppointmentModel>>{};
      for (final a in apts) {
        final mapKey = DateFormat('yyyy-MM-dd').format(a.dateTime);
        map.putIfAbsent(mapKey, () => []).add(a);
      }
      setState(() => _monthAppointments = map);
    }, onError: (e) {
      debugPrint('Calendar dots stream error: $e');
    });
  }

  /// Update [_selectedDate] and re-derive the visible day's appointments.
  /// If the new date is in the same month as the current subscription,
  /// the filter happens instantly from in-memory data (no network call).
  /// If it's in a different month, we re-subscribe and the listener
  /// updates [_appointments] on the first emission.
  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _appointments = _selectedMonthApts
          .where((a) => DateUtils.isSameDay(a.dateTime, date))
          .toList();
    });
    _ensureSelectedMonthSubscription(date);
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
    final l = AppLocalizations.of(context);
    final dateLabel =
        DateFormat('EEEE d MMMM yyyy', 'fr_FR').format(_selectedDate);
    final buf = StringBuffer();
    buf.writeln('📅 Planning du $dateLabel');
    buf.writeln('─────────────────────');

    if (_appointments.isEmpty) {
      buf.writeln(l?.tr('agenda_no_appointments') ?? 'Aucun rendez-vous prévu.');
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
          final client = a.clientName ?? (l?.tr('agenda_client') ?? 'Client');
          buf.writeln('  ⏰ $start - $end | ${a.serviceName} | $client');
        }
      }
      final unassigned = _unassignedAppointments();
      if (unassigned.isNotEmpty) {
        unassigned.sort((a, b) => a.dateTime.compareTo(b.dateTime));
        buf.writeln('\n📌 ${l?.tr('agenda_unassigned') ?? 'Non assigné'}');
        for (final a in unassigned) {
          final start = DateFormat('HH:mm').format(a.dateTime);
          final client = a.clientName ?? (l?.tr('agenda_client') ?? 'Client');
          buf.writeln('  ⏰ $start | ${a.serviceName} | $client');
        }
      }
    }

    buf.writeln('\n─────────────────────');
    buf.writeln('Total: ${_appointments.length} RDV');

    await Clipboard.setData(ClipboardData(text: buf.toString()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('agenda_planning_copied') ?? 'Planning copié ! Collez-le dans WhatsApp ou SMS.'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isToday = DateUtils.isSameDay(_selectedDate, DateTime.now());

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: MediaQuery.sizeOf(context).shortestSide >= 600
            ? const SizedBox.shrink()
            : IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.brand900),
                onPressed: () => Navigator.pop(context),
              ),
        leadingWidth: MediaQuery.sizeOf(context).shortestSide >= 600 ? 16 : null,
        title: Row(
          children: [
            Text(
              l?.tr('agenda_title') ?? 'Agenda',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                setState(() => _calendarOpen = !_calendarOpen);
                if (_calendarOpen) _ensureCalendarDotsSubscription(_calendarMonth);
              },
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    isToday ? (l?.tr('agenda_today') ?? "Aujourd'hui") : _fullDateLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand950,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _calendarOpen ? Icons.keyboard_arrow_up : Icons.calendar_month_rounded,
                    size: 18, color: AppColors.brand600,
                  ),
                ],
              ),
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
            // Calendar overlay
            if (_calendarOpen)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.45,
                ),
                child: SingleChildScrollView(child: _buildCalendarOverlay()),
              ),

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

  // ── Calendar overlay ──────────────────────────────────────────
  Widget _buildCalendarOverlay() {
    final now = DateTime.now();
    final firstDay = DateTime(_calendarMonth.year, _calendarMonth.month, 1);
    final lastDay = DateTime(_calendarMonth.year, _calendarMonth.month + 1, 0);
    final startWeekday = firstDay.weekday; // 1=Mon ... 7=Sun
    final daysInMonth = lastDay.day;

    final isFr = Localizations.localeOf(context).languageCode == 'fr';
    final monthNames = isFr
        ? ['janv.', 'févr.', 'mars', 'avr.', 'mai', 'juin', 'juil.', 'août', 'sept.', 'oct.', 'nov.', 'déc.']
        : ['Jan.', 'Feb.', 'Mar.', 'Apr.', 'May', 'Jun.', 'Jul.', 'Aug.', 'Sep.', 'Oct.', 'Nov.', 'Dec.'];
    final dayHeaders = isFr
        ? ['L', 'M', 'M', 'J', 'V', 'S', 'D']
        : ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    // Build member color map for dots — honors custom agendaColorIndex when set
    final memberColorMap = <String, Color>{};
    for (int i = 0; i < _members.length; i++) {
      final ci = _members[i].agendaColorIndex ?? i;
      memberColorMap[_members[i].id] = _memberTextColors[ci % _memberTextColors.length];
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Month navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left, size: 20, color: AppColors.brand600),
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month - 1);
                  });
                  _ensureCalendarDotsSubscription(_calendarMonth);
                },
              ),
              Text(
                '${monthNames[_calendarMonth.month - 1]} ${_calendarMonth.year}',
                style: GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 15, color: AppColors.brand950),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right, size: 20, color: AppColors.brand600),
                onPressed: () {
                  setState(() {
                    _calendarMonth = DateTime(_calendarMonth.year, _calendarMonth.month + 1);
                  });
                  _ensureCalendarDotsSubscription(_calendarMonth);
                },
              ),
            ],
          ),

          // Month chips
          SizedBox(
            height: 32,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 12,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, i) {
                final isActive = i == _calendarMonth.month - 1;
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _calendarMonth = DateTime(_calendarMonth.year, i + 1);
                    });
                    _ensureCalendarDotsSubscription(_calendarMonth);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.brand600 : AppColors.secondary50,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      monthNames[i],
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                        color: isActive ? Colors.white : AppColors.secondary500,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),

          // Day of week headers
          Row(
            children: dayHeaders.map((d) => Expanded(
              child: Center(
                child: Text(d, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondary400)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 6),

          // Calendar grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: MediaQuery.sizeOf(context).shortestSide >= 600 ? 1.8 : 1.0,
            ),
            itemCount: ((startWeekday - 1) + daysInMonth + (7 - ((startWeekday - 1 + daysInMonth) % 7)) % 7),
            itemBuilder: (context, index) {
              final dayOffset = index - (startWeekday - 1);
              if (dayOffset < 0 || dayOffset >= daysInMonth) return const SizedBox.shrink();

              final day = dayOffset + 1;
              final date = DateTime(_calendarMonth.year, _calendarMonth.month, day);
              final key = DateFormat('yyyy-MM-dd').format(date);
              final dayAppointments = _monthAppointments[key] ?? [];
              final isSelected = DateUtils.isSameDay(date, _selectedDate);
              final isCurrentDay = DateUtils.isSameDay(date, now);

              // Get unique member colors for dots (max 4)
              final memberIds = dayAppointments
                  .map((a) => a.assignedMemberId)
                  .where((id) => id != null)
                  .toSet()
                  .take(4)
                  .toList();
              final dotColors = memberIds
                  .map((id) => memberColorMap[id] ?? AppColors.secondary400)
                  .toList();
              // Add a dot for unassigned appointments
              if (dayAppointments.any((a) => a.assignedMemberId == null) && dotColors.length < 4) {
                dotColors.add(AppColors.secondary400);
              }

              return GestureDetector(
                onTap: () {
                  setState(() => _calendarOpen = false);
                  _selectDate(date);
                },
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isSelected ? AppColors.brand600 : null,
                        border: isCurrentDay && !isSelected ? Border.all(color: AppColors.brand600, width: 1.5) : null,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$day',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected || isCurrentDay ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.white : isCurrentDay ? AppColors.brand600 : AppColors.brand950,
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    // Dots
                    SizedBox(
                      height: 6,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: dotColors.map((c) => Container(
                          width: 5,
                          height: 5,
                          margin: const EdgeInsets.symmetric(horizontal: 1),
                          decoration: BoxDecoration(shape: BoxShape.circle, color: c),
                        )).toList(),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),

          const SizedBox(height: 4),
          Divider(color: AppColors.secondary100, height: 1),
        ],
      ),
    );
  }

  Widget _buildMemberHeader() {
    final l = AppLocalizations.of(context);
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
                    final ci = member.agendaColorIndex ?? idx;
                    final color = _memberColors[ci % _memberColors.length];
                    final apptCount = _appointmentsForMember(member.id).length;
                    return SizedBox(
                      width: _memberColumnWidth,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          MemberAvatar(
                            name: member.name,
                            photoUrl: member.photoUrl,
                            radius: 18,
                            backgroundColor: color,
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
                            (l?.tr('agenda_count') ?? '{count} RDV').replaceAll('{count}', '$apptCount'),
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
                          Text(
                            l?.tr('agenda_unassigned') ?? 'Non assigné',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondary500,
                            ),
                          ),
                          Text(
                            (l?.tr('agenda_count') ?? '{count} RDV').replaceAll('{count}', '${unassigned.length}'),
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
                        member.agendaColorIndex ?? idx,
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
            final risk = ref
                .watch(agendaRiskClientsProvider)
                .valueOrNull?[appt.clientId];

            return Positioned(
              top: top,
              left: 3,
              right: 3,
              height: height,
              child: GestureDetector(
                onTap: () => _showAppointmentDetails(appt, colorIndex),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: bgColor.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: risk != null
                              ? const Color(0xFFF59E0B)
                              : bgColor,
                          width: risk != null ? 1.5 : 1,
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
                    if (risk != null)
                      Positioned(
                        top: 2,
                        right: 2,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showRiskStats(appt, risk),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Color(0xFFF59E0B),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ),
                  ],
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
    final l = AppLocalizations.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.groups_outlined,
              size: 48, color: AppColors.secondary300),
          const SizedBox(height: 12),
          Text(
            l?.tr('agenda_no_team_members') ?? 'Aucun membre dans l\'équipe',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('agenda_add_members_hint') ?? 'Ajoutez des membres pour voir le planning',
            style: const TextStyle(fontSize: 13, color: AppColors.secondary400),
          ),
        ],
      ),
    );
  }

  void _showAppointmentDetails(AppointmentModel appt, int colorIndex) async {
    final l = AppLocalizations.of(context);
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
            if (appt.selectedOptions != null && appt.selectedOptions!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: appt.selectedOptions!
                    .map((opt) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brand50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.brand200),
                          ),
                          child: Text(
                            opt,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.brand700,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
            // No-show risk pill (per-salon or cross-salon)
            Builder(builder: (_) {
              final risk = ref
                  .read(agendaRiskClientsProvider)
                  .valueOrNull?[appt.clientId];
              if (risk == null) return const SizedBox.shrink();
              final l = AppLocalizations.of(context);
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(context);
                    _showRiskStats(appt, risk);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            size: 18, color: Color(0xFFD97706)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${l?.tr('agenda_risk_pill') ?? 'Risque de no-show'} · ${risk.rate}%',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF854D0E),
                            ),
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded,
                            size: 18, color: Color(0xFF854D0E)),
                      ],
                    ),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            // Details
            if (appt.clientName != null) ...[
              _detailRow(Icons.face_outlined, appt.clientName!),
              const SizedBox(height: 8),
            ],
            if (phone != null && phone.isNotEmpty) ...[
              Builder(builder: (_) {
                final wa = phone!;
                return InkWell(
                  onTap: () {
                    final digits = wa.replaceAll(RegExp(r'\D'), '');
                    launchUrl(
                      Uri.parse('https://wa.me/$digits'),
                      mode: LaunchMode.externalApplication,
                    );
                  },
                  child: _detailRow(FontAwesomeIcons.whatsapp, wa),
                );
              }),
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
              CurrencyHelper.format(appt.price, widget.currency),
            ),
            const SizedBox(height: 8),
            _detailRow(
              Icons.info_outline,
              appt.status == 'upcoming'
                  ? (l?.tr('appointments_status_upcoming') ?? 'À venir')
                  : appt.status == 'completed'
                      ? (l?.tr('appointments_status_completed') ?? 'Terminé')
                      : (l?.tr('appointments_status_cancelled') ?? 'Annulé'),
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

  void _showRiskStats(AppointmentModel appt, AgendaRiskInfo risk) {
    final l = AppLocalizations.of(context);
    final clientLabel = appt.clientName?.isNotEmpty == true
        ? appt.clientName!
        : (l?.tr('agenda_client') ?? 'Client');

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
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: const Icon(Icons.warning_amber_rounded,
                      color: Color(0xFFD97706), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l?.tr('agenda_risk_pill') ?? 'Risque de no-show',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        clientLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.secondary500,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${risk.rate}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
            if (risk.isCrossSalon) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.travel_explore_rounded,
                        size: 14, color: Color(0xFF1D4ED8)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l?.tr('noshow_cross_salon_hint') ??
                            'Historique cumulé sur d\'autres salons (jamais venu chez vous)',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF1D4ED8),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${risk.totalPast}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand950,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          risk.isCrossSalon
                              ? (l?.tr('noshow_past_total_global') ??
                                  'RDV totaux')
                              : (l?.tr('noshow_past_total') ?? 'RDV passés'),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.secondary400),
                        ),
                      ],
                    ),
                  ),
                  Container(
                      width: 1, height: 30, color: AppColors.secondary200),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${risk.cancelledPast}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFFDC2626),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l?.tr('noshow_past_cancelled') ?? 'Annulés',
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.secondary400),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              l?.tr('agenda_risk_advice') ??
                  'Conseil : appelez le client pour confirmer le RDV ou demandez une avance pour sécuriser sa venue.',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondary500,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
