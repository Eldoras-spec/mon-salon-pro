import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/promotion_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../models/waitlist_model.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/notification_service.dart';
import '../models/user_model.dart';
import '../widgets/custom_button.dart';

class ClientBookingFlowScreen extends StatefulWidget {
  final SalonModel salon;
  final Map<String, dynamic>? initialService;

  const ClientBookingFlowScreen({
    super.key,
    required this.salon,
    this.initialService,
  });

  @override
  State<ClientBookingFlowScreen> createState() =>
      _ClientBookingFlowScreenState();
}

class _ClientBookingFlowScreenState extends State<ClientBookingFlowScreen> {
  final _databaseService = DatabaseService();
  final _authService = AuthService();
  final _notificationService = NotificationService();

  Map<String, dynamic>? _selectedService;
  final List<Map<String, dynamic>> _selectedServices = []; // multi-select
  String? _activeServiceCategory; // null = show all
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String? _selectedTime;
  bool _isLoading = false;

  List<TeamMemberModel> _teamMembers = [];
  TeamMemberModel? _selectedMember; // null = no preference

  // Existing appointments for the selected date (for slot filtering)
  List<AppointmentModel> _existingAppointments = [];
  bool _appointmentsLoading = true;

  UserModel? _user;
  final TextEditingController _promoController = TextEditingController();
  bool _isPromoApplied = false;
  double _discountAmount = 0.0;

  // Salon promotions (auto-applied)
  List<PromotionModel> _salonPromos = [];
  PromotionModel? _appliedSalonPromo;
  double _salonPromoDiscount = 0.0;

  // Reward points
  double _availablePoints = 0.0;
  bool _usePoints = false;
  bool _pointsLoading = false;

  static const List<String> _timeSlots = [
    '09:00', '09:30', '10:00', '10:30', '11:00', '11:30',
    '14:00', '14:30', '15:00', '15:30', '16:00', '16:30',
  ];

  @override
  void initState() {
    super.initState();
    _selectedService = widget.initialService;
    if (widget.initialService != null) {
      _selectedServices.add(widget.initialService!);
    }
    _loadUserData();
    _loadPoints();
    _loadTeamMembers();
    _loadSalonPromos();
    _loadAppointmentsForDate(_selectedDate);
  }

  Future<void> _loadTeamMembers() async {
    final members =
        await _databaseService.getTeamMembersOnce(widget.salon.id);
    if (mounted) setState(() => _teamMembers = members);
  }

  Future<void> _loadAppointmentsForDate(DateTime date) async {
    setState(() => _appointmentsLoading = true);
    try {
      final appointments = await _databaseService.getSalonAppointmentsForDate(
          widget.salon.id, date);
      if (mounted) {
        setState(() {
          _existingAppointments = appointments;
          _appointmentsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading appointments: $e');
      if (mounted) setState(() => _appointmentsLoading = false);
    }
  }

  bool get _isMultiService => _selectedServices.length > 1;

  /// Total duration of all selected services (multi-service mode).
  int get _totalDuration => _selectedServices.fold(
      0, (sum, s) => sum + ((s['duration'] as int?) ?? 30));

  /// Total price of all selected services.
  double get _totalPrice => _selectedServices.fold(
      0.0, (sum, s) => sum + ((s['price'] ?? 0.0) as num).toDouble());

  /// Get the duration (in minutes) of the currently selected service.
  int get _serviceDuration {
    if (_isMultiService) return _totalDuration;
    if (_selectedService == null) return 30;
    return (_selectedService!['duration'] as int?) ?? 30;
  }

  /// Get the effective duration for an existing appointment.
  /// Uses the stored durationMinutes if available (non-default),
  /// otherwise looks up the service duration from the salon's config.
  int _effectiveDuration(AppointmentModel appt) {
    // If the appointment has a stored duration (added after the update), use it
    if (appt.durationMinutes > 0 && appt.durationMinutes != 30) {
      return appt.durationMinutes;
    }
    // Try to find the matching service in the salon's services list
    for (final s in widget.salon.services) {
      final sName = (s['name'] ?? s['title'] ?? '') as String;
      if (sName == appt.serviceName && s['duration'] != null) {
        return s['duration'] as int;
      }
    }
    // Fallback to the stored value (30 min default for legacy appointments)
    return appt.durationMinutes;
  }

  /// Check whether a time slot overlaps with an existing appointment.
  bool _overlaps(DateTime slotStart, DateTime slotEnd, AppointmentModel appt) {
    final apptStart = appt.dateTime;
    final apptEnd = apptStart.add(Duration(minutes: _effectiveDuration(appt)));
    return slotStart.isBefore(apptEnd) && slotEnd.isAfter(apptStart);
  }

  /// Check if a time slot is already booked (conflicts with existing appointments).
  bool _isSlotBooked(String timeSlot) {
    final parts = timeSlot.split(':');
    final slotStart = DateTime(_selectedDate.year, _selectedDate.month,
        _selectedDate.day, int.parse(parts[0]), int.parse(parts[1]));

    // Multi-service: check if the entire chain can be scheduled
    if (_isMultiService) {
      return !_canChainServicesAt(slotStart);
    }

    final slotEnd = slotStart.add(Duration(minutes: _serviceDuration));

    if (_selectedMember != null) {
      // A specific member is selected — blocked if that member has an overlapping appointment
      return _isMemberBusyAtSlot(_selectedMember!.id, slotStart, slotEnd);
    }

    // "Pas de préférence" — blocked only if ALL available members are busy
    final availableMembers = _availableMembersForDate(_selectedDate);
    if (availableMembers.isEmpty) return false;
    return availableMembers.every((m) =>
        _isMemberBusyAtSlot(m.id, slotStart, slotEnd));
  }

  /// Try to chain all selected services starting at [startTime].
  /// Returns true if every service can be auto-assigned to an available member.
  bool _canChainServicesAt(DateTime startTime) {
    final iso = _isoDate(_selectedDate);
    // Track simulated bookings per member during this chain
    final simulatedBusy = <String, List<_TimeRange>>{};

    var cursor = startTime;
    for (final svc in _selectedServices) {
      final duration = (svc['duration'] as int?) ?? 30;
      final svcEnd = cursor.add(Duration(minutes: duration));
      final svcName = (svc['name'] ?? svc['title'] ?? '') as String;

      // Find members assigned to this service and available on this date
      final candidates = _teamMembers
          .where((m) =>
              m.isActive &&
              m.assignedServiceNames.contains(svcName) &&
              !m.unavailableDates.contains(iso))
          .toList();

      if (candidates.isEmpty) {
        // No team assignment = no restriction, service can be done
        cursor = svcEnd;
        continue;
      }

      // Find a candidate not busy during [cursor, svcEnd)
      bool found = false;
      for (final m in candidates) {
        final busy = _isMemberBusyAtSlot(m.id, cursor, svcEnd);
        // Also check simulated bookings from earlier in the chain
        final simulated = simulatedBusy[m.id] ?? [];
        final simBusy = simulated.any((r) =>
            cursor.isBefore(r.end) && svcEnd.isAfter(r.start));
        if (!busy && !simBusy) {
          simulatedBusy.putIfAbsent(m.id, () => []).add(_TimeRange(cursor, svcEnd));
          found = true;
          break;
        }
      }
      if (!found) return false;

      cursor = svcEnd;
    }
    return true;
  }

  /// Resolve the chain: returns list of (service, member, startTime) or null if impossible.
  List<_ChainedBooking>? _resolveChain(DateTime startTime) {
    final iso = _isoDate(_selectedDate);
    final simulatedBusy = <String, List<_TimeRange>>{};
    final result = <_ChainedBooking>[];

    var cursor = startTime;
    for (final svc in _selectedServices) {
      final duration = (svc['duration'] as int?) ?? 30;
      final svcEnd = cursor.add(Duration(minutes: duration));
      final svcName = (svc['name'] ?? svc['title'] ?? '') as String;

      final candidates = _teamMembers
          .where((m) =>
              m.isActive &&
              m.assignedServiceNames.contains(svcName) &&
              !m.unavailableDates.contains(iso))
          .toList();

      TeamMemberModel? assigned;
      if (candidates.isNotEmpty) {
        for (final m in candidates) {
          final busy = _isMemberBusyAtSlot(m.id, cursor, svcEnd);
          final simulated = simulatedBusy[m.id] ?? [];
          final simBusy = simulated.any((r) =>
              cursor.isBefore(r.end) && svcEnd.isAfter(r.start));
          if (!busy && !simBusy) {
            simulatedBusy.putIfAbsent(m.id, () => []).add(_TimeRange(cursor, svcEnd));
            assigned = m;
            break;
          }
        }
        if (assigned == null) return null;
      }

      result.add(_ChainedBooking(
        service: svc,
        member: assigned,
        startTime: cursor,
        duration: duration,
      ));
      cursor = svcEnd;
    }
    return result;
  }

  /// Check if a specific member is busy during a given time range.
  bool _isMemberBusyAtSlot(String memberId, DateTime slotStart, DateTime slotEnd) {
    for (final appt in _existingAppointments) {
      if (appt.assignedMemberId != memberId) continue;
      if (_overlaps(slotStart, slotEnd, appt)) return true;
    }
    // Check unavailable time slots
    final member = _teamMembers.where((m) => m.id == memberId).firstOrNull;
    if (member != null) {
      final iso = _isoDate(slotStart);
      final slots = member.unavailableSlots[iso] ?? [];
      for (final slot in slots) {
        final parts = slot.split('-');
        if (parts.length != 2) continue;
        final sParts = parts[0].split(':');
        final eParts = parts[1].split(':');
        final sTime = DateTime(slotStart.year, slotStart.month, slotStart.day,
            int.parse(sParts[0]), int.parse(sParts[1]));
        final eTime = DateTime(slotStart.year, slotStart.month, slotStart.day,
            int.parse(eParts[0]), int.parse(eParts[1]));
        if (slotStart.isBefore(eTime) && slotEnd.isAfter(sTime)) return true;
      }
    }
    return false;
  }

  // ISO date string "yyyy-MM-dd"
  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // The canonical service name used for matching assignedServiceNames
  String get _serviceName =>
      (_selectedService?['name'] ?? _selectedService?['title'] ?? '') as String;

  // Members assigned to the currently selected service
  List<TeamMemberModel> _membersForService() {
    if (_selectedService == null) return [];
    final name = _serviceName;
    return _teamMembers
        .where((m) => m.isActive && m.assignedServiceNames.contains(name))
        .toList();
  }

  // Is a given date fully blocked (all assigned members unavailable)?
  bool _isDateBlocked(DateTime date) {
    if (_isMultiService) {
      final iso = _isoDate(date);
      for (final svc in _selectedServices) {
        final svcName = (svc['name'] ?? svc['title'] ?? '') as String;
        final candidates = _teamMembers
            .where((m) => m.isActive && m.assignedServiceNames.contains(svcName))
            .toList();
        if (candidates.isEmpty) continue; // no restriction
        if (candidates.every((m) => m.unavailableDates.contains(iso))) return true;
      }
      return false;
    }
    final relevant = _membersForService();
    if (relevant.isEmpty) return false; // no assignments = no restriction
    final iso = _isoDate(date);
    return relevant.every((m) => m.unavailableDates.contains(iso));
  }

  // Members available on a given date for the selected service
  List<TeamMemberModel> _availableMembersForDate(DateTime date) {
    final iso = _isoDate(date);
    return _membersForService()
        .where((m) => !m.unavailableDates.contains(iso))
        .toList();
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  bool _allSlotsBooked() {
    if (_selectedServices.isEmpty || _appointmentsLoading) return false;
    return _timeSlots.every((t) => _isSlotBooked(t));
  }

  Future<void> _joinWaitlist() async {
    final uid = _authService.currentUserId;
    if (uid == null || _selectedService == null) return;

    final already = await _databaseService.isOnWaitlist(
        uid, widget.salon.id, _selectedDate);
    if (already) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vous êtes déjà sur la liste d\'attente pour cette date.'),
            backgroundColor: AppColors.brand600,
          ),
        );
      }
      return;
    }

    final entry = WaitlistEntry(
      id: const Uuid().v4(),
      clientId: uid,
      clientName: _user?.fullName ?? '',
      salonId: widget.salon.id,
      salonName: widget.salon.name,
      serviceName: _serviceName,
      desiredDate: _selectedDate,
      createdAt: DateTime.now(),
    );

    await _databaseService.addToWaitlist(entry);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez été ajouté à la liste d\'attente ! Vous serez notifié si un créneau se libère.'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _loadSalonPromos() async {
    final clientId = AuthService().currentUserId;
    final promos = await _databaseService
        .getActivePromotions(widget.salon.id, clientId: clientId)
        .first;
    if (mounted) {
      setState(() => _salonPromos = promos);
      _autoApplySalonPromo();
    }
  }

  /// Auto-apply the best salon promo (highest discount, no code required).
  void _autoApplySalonPromo() {
    if (_selectedServices.isEmpty) return;

    PromotionModel? best;
    for (final promo in _salonPromos) {
      // Skip promos that require a code — user must enter those manually
      if (promo.promoCode != null && promo.promoCode!.isNotEmpty) continue;
      if (promo.discountPercent == null || promo.discountPercent! <= 0) continue;
      // Check if promo applies to selected services
      if (promo.applicableServiceNames != null) {
        final serviceNames = _selectedServices
            .map((s) => (s['title'] ?? s['name'] ?? '') as String)
            .toSet();
        if (!serviceNames.any((n) => promo.applicableServiceNames!.contains(n))) {
          continue;
        }
      }
      if (best == null || promo.discountPercent! > best.discountPercent!) {
        best = promo;
      }
    }

    if (best != null) {
      final price = _isMultiService
          ? _totalPrice
          : (_selectedService?['price'] ?? 0.0).toDouble();
      setState(() {
        _appliedSalonPromo = best;
        _salonPromoDiscount = price * (best!.discountPercent! / 100.0);
      });
    } else {
      setState(() {
        _appliedSalonPromo = null;
        _salonPromoDiscount = 0.0;
      });
    }
  }

  Future<void> _loadUserData() async {
    final uid = _authService.currentUserId;
    if (uid != null) {
      final user = await _authService.getUserModel(uid);
      if (mounted) {
        setState(() {
          _user = user;
        });
      }
    }
  }

  Future<void> _loadPoints() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    setState(() => _pointsLoading = true);
    final pts = await _databaseService.getUserPointsForSalon(uid, widget.salon.id);
    if (mounted) {
      setState(() {
        _availablePoints = pts;
        _usePoints = pts > 0; // auto-apply when points are available
        _pointsLoading = false;
      });
    }
  }

  double get _pointsDiscount {
    if (!_usePoints || _availablePoints <= 0 || _selectedServices.isEmpty) {
      return 0.0;
    }
    final price = _isMultiService
        ? _totalPrice
        : (_selectedService!['price'] ?? 0.0).toDouble();
    return _availablePoints.clamp(0.0, price).toDouble();
  }

  void _applyPromoCode() {
    final code = _promoController.text.trim().toUpperCase();

    // 1) Check salon-specific promo codes
    final salonPromo = _salonPromos.where((p) =>
        p.promoCode != null &&
        p.promoCode!.toUpperCase() == code &&
        p.discountPercent != null &&
        p.discountPercent! > 0).firstOrNull;

    if (salonPromo != null) {
      final price = _isMultiService
          ? _totalPrice
          : (_selectedService?['price'] ?? 0.0).toDouble();
      setState(() {
        _isPromoApplied = true;
        _discountAmount = price * (salonPromo.discountPercent! / 100.0);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Code promo appliqué ! -${salonPromo.discountPercent!.toStringAsFixed(0)}% de réduction.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 2) ELITE10 global promo code
    if (code != 'ELITE10') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Code promo invalide.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (_user?.promoCodeUsed == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ce code promo a déjà été utilisé.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (!(_user?.hasClaimedOffer ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Vous devez d\'abord collecter cette offre sur l\'accueil.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // All checks passed — apply the ELITE10 discount
    setState(() {
      _isPromoApplied = true;
      final originalPrice = _isMultiService
          ? _totalPrice
          : (_selectedService?['price'] ?? 0.0).toDouble();
      _discountAmount = originalPrice * 0.10;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Code promo appliqué ! 10% de réduction.'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _handleBooking() async {
    if (_selectedServices.isEmpty || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez sélectionner un service et un horaire'),
        ),
      );
      return;
    }

    final uid = _authService.currentUserId;
    if (uid == null) return;

    setState(() => _isLoading = true);

    try {
      // Parse 24h time "HH:mm"
      final hourMin = _selectedTime!.split(':');
      final int hour = int.parse(hourMin[0]);
      final int minute = int.parse(hourMin[1]);

      final startDateTime = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        hour,
        minute,
      );

      if (_isMultiService) {
        await _handleMultiServiceBooking(uid, startDateTime);
      } else {
        await _handleSingleServiceBooking(uid, startDateTime);
      }

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isMultiService
                ? '${_selectedServices.length} réservations confirmées !'
                : 'Réservation confirmée !'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleSingleServiceBooking(String uid, DateTime appointmentDateTime) async {
    final service = _selectedServices.first;
    final duration = (service['duration'] as int?) ?? 30;

    // Auto-assign a member when "Pas de préférence" is selected
    TeamMemberModel? assignedMember = _selectedMember;
    if (assignedMember == null) {
      final slotEnd = appointmentDateTime.add(Duration(minutes: duration));
      final available = _availableMembersForDate(_selectedDate)
          .where((m) => !_isMemberBusyAtSlot(m.id, appointmentDateTime, slotEnd))
          .toList();
      if (available.isNotEmpty) {
        available.shuffle();
        assignedMember = available.first;
      }
    }

    final originalPrice = (service['price'] ?? 0.0).toDouble();
    final appointment = AppointmentModel(
      id: const Uuid().v4(),
      clientId: uid,
      salonId: widget.salon.id,
      salonName: widget.salon.name,
      serviceName: service['title'] ?? service['name'] ?? 'Service',
      price: (originalPrice - _discountAmount - _salonPromoDiscount - _pointsDiscount).clamp(0.0, originalPrice),
      dateTime: appointmentDateTime,
      status: 'upcoming',
      createdAt: DateTime.now(),
      durationMinutes: duration,
      clientName: _user?.fullName,
      clientPhone: _user?.phone,
      assignedMemberId: assignedMember?.id,
      assignedMemberName: assignedMember?.name,
    );

    await _databaseService.createAppointment(appointment);

    if (_pointsDiscount > 0) {
      await _databaseService.redeemPoints(uid, widget.salon.id);
    }
    if (_isPromoApplied) {
      await _databaseService.markPromoCodeUsed(uid);
    }

    final serviceName = service['title'] ?? service['name'] ?? 'Service';
    final notifBody =
        '$serviceName chez ${widget.salon.name} le ${DateFormat('dd/MM/yyyy').format(appointmentDateTime)} à $_selectedTime';

    await _databaseService.saveNotification(
      userId: uid,
      title: 'Réservation Confirmée ! ✅',
      body: notifBody,
      type: 'appointment',
    );
    await _notificationService.showLocalNotification(
      title: 'Réservation Confirmée ! ✅',
      body: notifBody,
      payload: 'booking_${appointment.id}',
    );
    await _notificationService.scheduleReminderNotification(
      appointmentId: appointment.id,
      serviceName: serviceName,
      salonName: widget.salon.name,
      appointmentTime: appointmentDateTime,
    );
    await _notificationService.saveTokenForUser(uid);
  }

  Future<void> _handleMultiServiceBooking(String uid, DateTime startDateTime) async {
    final chain = _resolveChain(startDateTime);
    if (chain == null) {
      throw Exception('Impossible de chaîner les services à cet horaire.');
    }

    final groupId = const Uuid().v4();

    // Apply discount/points proportionally across total price
    final total = _totalPrice;
    final totalDiscount = _discountAmount + _salonPromoDiscount + _pointsDiscount;

    for (final booking in chain) {
      final svc = booking.service;
      final originalPrice = (svc['price'] ?? 0.0).toDouble();
      // Proportional discount for this service
      final ratio = total > 0 ? originalPrice / total : 0.0;
      final svcDiscount = totalDiscount * ratio;

      final appointment = AppointmentModel(
        id: const Uuid().v4(),
        clientId: uid,
        salonId: widget.salon.id,
        salonName: widget.salon.name,
        serviceName: svc['title'] ?? svc['name'] ?? 'Service',
        price: (originalPrice - svcDiscount).clamp(0.0, originalPrice),
        dateTime: booking.startTime,
        status: 'upcoming',
        createdAt: DateTime.now(),
        durationMinutes: booking.duration,
        clientName: _user?.fullName,
        clientPhone: _user?.phone,
        assignedMemberId: booking.member?.id,
        assignedMemberName: booking.member?.name,
        groupId: groupId,
      );

      await _databaseService.createAppointment(appointment);
    }

    if (_pointsDiscount > 0) {
      await _databaseService.redeemPoints(uid, widget.salon.id);
    }
    if (_isPromoApplied) {
      await _databaseService.markPromoCodeUsed(uid);
    }

    // Single notification for the group
    final serviceNames = chain
        .map((b) => b.service['title'] ?? b.service['name'] ?? 'Service')
        .join(' + ');
    final notifBody =
        '$serviceNames chez ${widget.salon.name} le ${DateFormat('dd/MM/yyyy').format(startDateTime)} à $_selectedTime';

    await _databaseService.saveNotification(
      userId: uid,
      title: 'Réservations Confirmées ! ✅',
      body: notifBody,
      type: 'appointment',
    );
    await _notificationService.showLocalNotification(
      title: 'Réservations Confirmées ! ✅',
      body: notifBody,
      payload: 'booking_group_$groupId',
    );
    // Schedule reminder for the first appointment
    await _notificationService.scheduleReminderNotification(
      appointmentId: chain.first.service['name'] ?? 'multi',
      serviceName: serviceNames,
      salonName: widget.salon.name,
      appointmentTime: startDateTime,
    );
    await _notificationService.saveTokenForUser(uid);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Réserver',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand900,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand900),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSalonInfo(),
                const SizedBox(height: 32),
                _buildServiceSelector(),
                const SizedBox(height: 32),
                _buildDateSelector(),
                const SizedBox(height: 32),
                _buildMemberSelector(),
                if (_isMultiService ||
                    (!_isMultiService &&
                        _availableMembersForDate(_selectedDate).isNotEmpty &&
                        _selectedService != null))
                  const SizedBox(height: 32),
                _buildTimeSelector(),
                const SizedBox(height: 32),
                _buildPromoCodeInput(),
                const SizedBox(height: 32),
                _buildPointsSection(),
                const SizedBox(height: 32),
                _buildSummaryCard(),
                const SizedBox(height: 100),
              ],
            ),
          ),
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: CustomButton(
              text: 'Confirmer la réservation',
              onPressed: _handleBooking,
              isLoading: _isLoading,
              icon: Icons.check_circle_outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalonInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary200),
      ),
      child: Row(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              image: DecorationImage(
                image: NetworkImage(
                  widget.salon.images.isNotEmpty
                      ? widget.salon.images[0]
                      : 'https://storage.googleapis.com/uxpilot-auth.appspot.com/da0a95d19e-2dd9a8bff1799331920e.png',
                ),
                fit: BoxFit.cover,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.salon.name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.salon.address,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> get _serviceCategories {
    final cats = <String>{};
    for (final s in widget.salon.services) {
      final cat = s['category'] as String?;
      if (cat != null && cat.isNotEmpty) cats.add(cat);
    }
    return cats.toList();
  }

  List<Map<String, dynamic>> get _filteredServices {
    if (_activeServiceCategory == null) return widget.salon.services;
    return widget.salon.services
        .where((s) => s['category'] == _activeServiceCategory)
        .toList();
  }

  Widget _buildServiceSelector() {
    final categories = _serviceCategories;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (categories.length > 1) ...[
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: categories.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final isAll = index == 0;
                final cat = isAll ? null : categories[index - 1];
                final isActive = _activeServiceCategory == cat;
                return GestureDetector(
                  onTap: () => setState(() => _activeServiceCategory = cat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isActive ? AppColors.brand600 : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isActive ? AppColors.brand600 : AppColors.secondary300,
                      ),
                    ),
                    child: Text(
                      isAll ? 'Tous' : cat!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isActive ? Colors.white : AppColors.brand800,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _filteredServices.length,
          itemBuilder: (context, index) {
            final service = _filteredServices[index];
            final isSelected = _selectedServices.contains(service);
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: () => setState(() {
                  if (_selectedServices.contains(service)) {
                    _selectedServices.remove(service);
                  } else {
                    _selectedServices.add(service);
                  }
                  // Keep _selectedService in sync for single-service flow
                  if (_selectedServices.length == 1) {
                    _selectedService = _selectedServices.first;
                  } else if (_selectedServices.isEmpty) {
                    _selectedService = null;
                  } else {
                    _selectedService = _selectedServices.first;
                  }
                  _selectedMember = null;
                  _selectedTime = null;
                  _autoApplySalonPromo();
                }),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.brand50 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.brand500
                          : AppColors.secondary200,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Checkbox indicator
                      Container(
                        width: 22,
                        height: 22,
                        margin: const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.brand600 : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.brand600
                                : AppColors.secondary300,
                            width: 1.5,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, size: 14, color: Colors.white)
                            : null,
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              service['title'] ?? service['name'] ?? 'Service',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? AppColors.brand900
                                    : AppColors.brand950,
                              ),
                            ),
                            if (service['category'] != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                service['category'],
                                style: TextStyle(
                                  fontSize: 11,
                                  color: isSelected
                                      ? AppColors.brand600
                                      : AppColors.secondary400,
                                ),
                              ),
                            ],
                            const SizedBox(height: 4),
                            Text(
                              '${service['duration'] ?? 30} mins',
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.secondary500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${(service['price'] ?? 0.0).toStringAsFixed(0)} MAD',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        // Multi-service total banner
        if (_selectedServices.length > 1) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.brand200),
            ),
            child: Row(
              children: [
                const Icon(Icons.shopping_bag_outlined,
                    size: 18, color: AppColors.brand600),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_selectedServices.length} services · $_totalDuration mins',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand800,
                    ),
                  ),
                ),
                Text(
                  '${_totalPrice.toStringAsFixed(0)} MAD',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.brand600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDateSelector() {
    return SizedBox(
      height: 100,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: 14, // 2 weeks
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final date = DateTime.now().add(Duration(days: index + 1));
          final isSelected = DateUtils.isSameDay(date, _selectedDate);
          final isBlocked = _isDateBlocked(date);

          return InkWell(
            onTap: isBlocked
                ? null
                : () {
                    setState(() {
                      _selectedDate = date;
                      _selectedMember = null;
                      _selectedTime = null;
                    });
                    _loadAppointmentsForDate(date);
                  },
            child: Opacity(
              opacity: isBlocked ? 0.35 : 1.0,
              child: Container(
              width: 70,
              decoration: BoxDecoration(
                color: isSelected ? AppColors.brand600 : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? AppColors.brand600
                      : AppColors.secondary200,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    DateFormat('E', 'fr_FR').format(date).toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white70
                          : AppColors.secondary500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${date.day}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : AppColors.brand950,
                    ),
                  ),
                ],
              ),
            ), // Container
            ), // Opacity
          );
        },
      ),
    );
  }

  Widget _buildTimeSelector() {
    if (_appointmentsLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(
                color: AppColors.brand600, strokeWidth: 2),
          ),
        ),
      );
    }

    final morning = _timeSlots
        .where((t) => int.parse(t.split(':')[0]) < 12)
        .toList();
    final afternoon = _timeSlots
        .where((t) => int.parse(t.split(':')[0]) >= 12)
        .toList();

    // Build set of booked slots
    final bookedSlots = <String>{};
    for (final slot in _timeSlots) {
      if (_isSlotBooked(slot)) bookedSlots.add(slot);
    }

    final allBooked = _allSlotsBooked();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (morning.isNotEmpty) ...[
          _TimePeriodRow(
            label: 'Matin',
            icon: Icons.wb_sunny_outlined,
            slots: morning,
            selected: _selectedTime,
            bookedSlots: bookedSlots,
            onSelect: (t) => setState(() => _selectedTime = t),
          ),
          const SizedBox(height: 20),
        ],
        if (afternoon.isNotEmpty)
          _TimePeriodRow(
            label: 'Après-midi',
            icon: Icons.wb_twilight_outlined,
            slots: afternoon,
            selected: _selectedTime,
            bookedSlots: bookedSlots,
            onSelect: (t) => setState(() => _selectedTime = t),
          ),

        // ── Waitlist banner when all slots are booked ──────────────────
        if (allBooked && _selectedServices.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFFED7AA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.schedule_rounded,
                        size: 18, color: Color(0xFFEA580C)),
                    SizedBox(width: 8),
                    Text(
                      'Tous les créneaux sont pris',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Color(0xFFEA580C),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Rejoignez la liste d\'attente pour être notifié si un créneau se libère.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9A3412),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _joinWaitlist,
                    icon: const Icon(Icons.notifications_active_outlined,
                        size: 16),
                    label: const Text('Rejoindre la liste d\'attente',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildMemberSelector() {
    // In multi-service mode, members are auto-assigned
    if (_isMultiService) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.secondary50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.secondary200),
        ),
        child: const Row(
          children: [
            Icon(Icons.auto_awesome, size: 18, color: AppColors.brand600),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Les membres seront assignés automatiquement pour chaque service.',
                style: TextStyle(fontSize: 12, color: AppColors.secondary600),
              ),
            ),
          ],
        ),
      );
    }
    if (_selectedService == null) return const SizedBox.shrink();
    final members = _availableMembersForDate(_selectedDate);
    if (members.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Avec qui ?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.brand900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Sélectionnez un membre ou laissez au choix du salon',
          style: TextStyle(fontSize: 12, color: AppColors.secondary400),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 96,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              // "No preference" option
              _MemberChip(
                name: 'Pas de\npréférence',
                initials: '★',
                isSelected: _selectedMember == null,
                onTap: () => setState(() {
                  _selectedMember = null;
                  _selectedTime = null;
                }),
              ),
              const SizedBox(width: 10),
              ...members.map(
                (m) => Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: _MemberChip(
                    name: m.name,
                    initials: _initials(m.name),
                    isSelected: _selectedMember?.id == m.id,
                    onTap: () => setState(() {
                      _selectedMember = m;
                      _selectedTime = null;
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromoCodeInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Promo Code',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: AppColors.brand900,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _promoController,
                enabled: !_isPromoApplied,
                decoration: InputDecoration(
                  hintText: 'Entrez un code promo',
                  hintStyle: const TextStyle(color: AppColors.secondary400),
                  filled: true,
                  fillColor: AppColors.secondary50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _isPromoApplied ? null : _applyPromoCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _isPromoApplied ? 'Appliqué' : 'Appliquer',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPointsSection() {
    if (_pointsLoading) {
      return const Center(
        child: SizedBox(
          height: 24,
          width: 24,
          child: CircularProgressIndicator(
              color: AppColors.brand600, strokeWidth: 2),
        ),
      );
    }
    if (_availablePoints <= 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.stars_rounded,
                color: Color(0xFFD97706), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Points de fidélité',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Vous avez ${_availablePoints.toStringAsFixed(2)} MAD de points',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary600,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _usePoints,
            onChanged: (val) => setState(() => _usePoints = val),
            activeThumbColor: AppColors.brand600,
            activeTrackColor: AppColors.brand200,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMultiServiceLines() {
    // Try to resolve the chain if a time is selected, to show member assignments
    List<_ChainedBooking>? chain;
    if (_selectedTime != null) {
      final parts = _selectedTime!.split(':');
      final start = DateTime(_selectedDate.year, _selectedDate.month,
          _selectedDate.day, int.parse(parts[0]), int.parse(parts[1]));
      chain = _resolveChain(start);
    }

    final widgets = <Widget>[];
    for (int i = 0; i < _selectedServices.length; i++) {
      final svc = _selectedServices[i];
      final name = svc['title'] ?? svc['name'] ?? 'Service';
      final price = (svc['price'] ?? 0.0).toDouble();
      final dur = (svc['duration'] as int?) ?? 30;

      // Get member + time from chain if available
      String? memberName;
      String? timeStr;
      if (chain != null && i < chain.length) {
        memberName = chain[i].member?.name;
        final t = chain[i].startTime;
        timeStr = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      }

      widgets.add(Padding(
        padding: EdgeInsets.only(bottom: i < _selectedServices.length - 1 ? 10 : 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$name · ${dur}min',
                    style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  '${price.toStringAsFixed(0)} MAD',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
            if (memberName != null || timeStr != null) ...[
              const SizedBox(height: 2),
              Row(
                children: [
                  if (timeStr != null) ...[
                    const Icon(Icons.access_time, size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(timeStr, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                  if (timeStr != null && memberName != null)
                    const SizedBox(width: 10),
                  if (memberName != null) ...[
                    const Icon(Icons.person_outline, size: 12, color: Colors.white54),
                    const SizedBox(width: 4),
                    Text(memberName, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                  ],
                ],
              ),
            ],
          ],
        ),
      ));
    }
    return widgets;
  }

  Widget _buildSummaryCard() {
    if (_selectedServices.isEmpty) return const SizedBox.shrink();

    final originalPrice = _isMultiService
        ? _totalPrice
        : (_selectedService!['price'] ?? 0.0).toDouble();
    final totalPrice =
        (originalPrice - _discountAmount - _salonPromoDiscount - _pointsDiscount).clamp(0.0, originalPrice);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.brand950,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          // In multi-service mode, list each service with assigned member
          if (_isMultiService) ...[
            ..._buildMultiServiceLines(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Sous-total',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  '${originalPrice.toStringAsFixed(2)} MAD',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Prix',
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  '${originalPrice.toStringAsFixed(2)} MAD',
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ],
            ),
          if (_appliedSalonPromo != null && _salonPromoDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    '${_appliedSalonPromo!.title} (-${_appliedSalonPromo!.discountPercent!.toStringAsFixed(0)}%)',
                    style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '-${_salonPromoDiscount.toStringAsFixed(2)} MAD',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
          if (_isPromoApplied) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Code promo',
                  style: TextStyle(color: Colors.greenAccent, fontSize: 14),
                ),
                Text(
                  '-${_discountAmount.toStringAsFixed(2)} MAD',
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
          if (_pointsDiscount > 0) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Points de fidélité',
                  style: TextStyle(color: Color(0xFFFBBF24), fontSize: 14),
                ),
                Text(
                  '-${_pointsDiscount.toStringAsFixed(2)} MAD',
                  style: const TextStyle(
                    color: Color(0xFFFBBF24),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ],
          const Divider(color: Colors.white24, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${totalPrice.toStringAsFixed(2)} MAD',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 24,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 32),
          Row(
            children: [
              const Icon(Icons.event, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(
                DateFormat('MMMM dd, yyyy').format(_selectedDate),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              const Spacer(),
              const Icon(Icons.access_time, color: Colors.white70, size: 16),
              const SizedBox(width: 8),
              Text(
                _selectedTime ?? '--:--',
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Time Period Row ──────────────────────────────────────────────────────────

class _TimePeriodRow extends StatelessWidget {
  const _TimePeriodRow({
    required this.label,
    required this.icon,
    required this.slots,
    required this.selected,
    required this.onSelect,
    this.bookedSlots = const {},
  });

  final String label;
  final IconData icon;
  final List<String> slots;
  final String? selected;
  final ValueChanged<String> onSelect;
  final Set<String> bookedSlots;

  @override
  Widget build(BuildContext context) {
    final availableCount = slots.where((s) => !bookedSlots.contains(s)).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Period header
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
              '$availableCount créneaux',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary400,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        // Horizontal scrollable chips
        SizedBox(
          height: 46,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: slots.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final time = slots[index];
              final isBooked = bookedSlots.contains(time);
              final isSelected = selected == time;
              return GestureDetector(
                onTap: isBooked ? null : () => onSelect(time),
                child: Opacity(
                  opacity: isBooked ? 0.4 : 1.0,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    decoration: BoxDecoration(
                      color: isBooked
                          ? AppColors.secondary100
                          : isSelected
                              ? AppColors.brand600
                              : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isBooked
                            ? AppColors.secondary300
                            : isSelected
                                ? AppColors.brand600
                                : AppColors.secondary200,
                        width: isSelected ? 1.5 : 1,
                      ),
                      boxShadow: isSelected && !isBooked
                          ? [
                              BoxShadow(
                                color:
                                    AppColors.brand600.withValues(alpha: 0.25),
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
                        color: isBooked
                            ? AppColors.secondary400
                            : isSelected
                                ? Colors.white
                                : AppColors.secondary700,
                        letterSpacing: 0.5,
                        decoration:
                            isBooked ? TextDecoration.lineThrough : null,
                      ),
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
}

// ─── Member Chip ──────────────────────────────────────────────────────────────

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.name,
    required this.initials,
    required this.isSelected,
    required this.onTap,
  });

  final String name;
  final String initials;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 76,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.brand50 : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.brand500 : AppColors.secondary200,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  isSelected ? AppColors.brand600 : AppColors.secondary100,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : AppColors.secondary500,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: TextStyle(
                fontSize: 10,
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? AppColors.brand600
                    : AppColors.secondary600,
              ),
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Helper classes for multi-service chaining ────────────────────────────────

class _TimeRange {
  final DateTime start;
  final DateTime end;
  const _TimeRange(this.start, this.end);
}

class _ChainedBooking {
  final Map<String, dynamic> service;
  final TeamMemberModel? member;
  final DateTime startTime;
  final int duration;
  const _ChainedBooking({
    required this.service,
    this.member,
    required this.startTime,
    required this.duration,
  });
}
