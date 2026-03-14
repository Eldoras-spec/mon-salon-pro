import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/salon_model.dart';
import '../models/appointment_model.dart';
import '../models/user_model.dart';
import '../models/notification_model.dart';
import '../models/review_model.dart';
import '../models/inventory_model.dart';
import '../models/charge_model.dart';
import '../models/promotion_model.dart';
import '../models/team_member_model.dart';
import '../models/waitlist_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/review_reward_model.dart';

class DatabaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // --- Salon Operations ---

  // Generate URL-friendly slug from salon name + city
  String _generateSlug(String name, String city) {
    const diacritics = 'àâäéèêëïîôùûüÿçñáíóú';
    const replacements = 'aaaeeeeiioouuycnaiou';
    var slug = '$name $city'.toLowerCase();
    for (int i = 0; i < diacritics.length; i++) {
      slug = slug.replaceAll(diacritics[i], replacements[i]);
    }
    slug = slug.replaceAll(RegExp(r'[^a-z0-9\s-]'), '');
    slug = slug.replaceAll(RegExp(r'[\s-]+'), '-');
    slug = slug.replaceAll(RegExp(r'^-|-$'), '');
    return slug;
  }

  // Ensure slug is unique by appending a number if needed
  Future<String> _ensureUniqueSlug(String baseSlug, String salonId) async {
    var slug = baseSlug;
    var counter = 1;
    while (true) {
      final snap = await _firestore
          .collection('salons')
          .where('slug', isEqualTo: slug)
          .limit(1)
          .get();
      if (snap.docs.isEmpty || snap.docs.first.id == salonId) return slug;
      slug = '$baseSlug-$counter';
      counter++;
    }
  }

  // Generate and save slug for existing salons that don't have one
  Future<String> ensureSalonSlug(String salonId, String name, String city) async {
    final baseSlug = _generateSlug(name, city);
    final slug = await _ensureUniqueSlug(baseSlug, salonId);
    await _firestore.collection('salons').doc(salonId).update({'slug': slug});
    return slug;
  }

  // Create or Update Salon
  Future<void> saveSalon(SalonModel salon) async {
    // Ensure serviceCategories is up to date based on services
    final categories = salon.services
        .map((s) => s['category'] as String)
        .toSet()
        .toList();

    // Generate slug if not set
    String? slug = salon.slug;
    if (slug == null || slug.isEmpty) {
      final baseSlug = _generateSlug(salon.name, salon.city);
      slug = await _ensureUniqueSlug(baseSlug, salon.id);
    }

    final updatedSalon = SalonModel(
      id: salon.id,
      ownerId: salon.ownerId,
      name: salon.name,
      address: salon.address,
      city: salon.city,
      country: salon.country,
      description: salon.description,
      category: salon.category,
      rating: salon.rating,
      reviewCount: salon.reviewCount,
      images: salon.images,
      logoUrl: salon.logoUrl,
      workingHours: salon.workingHours,
      services: salon.services,
      serviceCategories: categories,
      createdAt: salon.createdAt,
      latitude: salon.latitude,
      longitude: salon.longitude,
      socialLinks: salon.socialLinks,
      servicePacks: salon.servicePacks,
      slug: slug,
    );

    await _firestore
        .collection('salons')
        .doc(updatedSalon.id)
        .set(updatedSalon.toMap());
  }

  // Get all salons (Stream)
  Stream<List<SalonModel>> get salons {
    return _firestore
        .collection('salons')
        .orderBy('rating', descending: true)
        .limit(30)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs.map((doc) => SalonModel.fromFirestore(doc)).toList();
        });
  }

  // Get salons by category (Stream)
  Stream<List<SalonModel>> getSalonsByCategory(String category) {
    return _firestore
        .collection('salons')
        .where('serviceCategories', arrayContains: category)
        .orderBy('rating', descending: true)
        .limit(30)
        .snapshots()
        .map((snapshot) {
          return snapshot.docs
              .map((doc) => SalonModel.fromFirestore(doc))
              .toList();
        });
  }

  // Get salon by ID
  Future<SalonModel?> getSalon(String id) async {
    DocumentSnapshot doc = await _firestore.collection('salons').doc(id).get();
    if (doc.exists) {
      return SalonModel.fromFirestore(doc);
    }
    return null;
  }

  // Get salons by list of IDs (for favorites)
  Stream<List<SalonModel>> getSalonsByIds(List<String> ids) {
    if (ids.isEmpty) {
      return Stream.value([]);
    }
    final limitedIds = ids.take(30).toList();
    return _firestore
        .collection('salons')
        .where(FieldPath.documentId, whereIn: limitedIds)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => SalonModel.fromFirestore(doc)).toList());
  }

  // Search salons by name or city (client-side filter on a broad Firestore fetch)
  Future<List<SalonModel>> searchSalons(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.trim().toLowerCase();
    final snapshot = await _firestore
        .collection('salons')
        .orderBy('rating', descending: true)
        .limit(150)
        .get();
    return snapshot.docs
        .map((doc) => SalonModel.fromFirestore(doc))
        .where((s) =>
            s.name.toLowerCase().contains(q) ||
            s.city.toLowerCase().contains(q) ||
            s.category.toLowerCase().contains(q) ||
            s.services.any((svc) =>
                (svc['name'] ?? '').toString().toLowerCase().contains(q)))
        .toList();
  }

  // --- Appointment Operations ---

  // Create Appointment
  Future<void> createAppointment(AppointmentModel appointment) async {
    await _firestore
        .collection('appointments')
        .doc(appointment.id)
        .set(appointment.toMap());
  }

  // Get client appointments (Stream) — sorted client-side to avoid composite index
  Stream<List<AppointmentModel>> getClientAppointments(String clientId, {String? status}) {
    return _firestore
        .collection('appointments')
        .where('clientId', isEqualTo: clientId)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => AppointmentModel.fromFirestore(doc))
              .where((a) => status == null || a.status == status)
              .toList();
          list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
          return list;
        });
  }

  // Get completed appointments once (for recommendations)
  Future<List<AppointmentModel>> getCompletedAppointmentsOnce(String clientId) async {
    final snapshot = await _firestore
        .collection('appointments')
        .where('clientId', isEqualTo: clientId)
        .where('status', isEqualTo: 'completed')
        .limit(20)
        .get();
    return snapshot.docs.map((doc) => AppointmentModel.fromFirestore(doc)).toList();
  }

  // Update appointment status
  Future<void> updateAppointmentStatus(String id, String status) async {
    await _firestore.collection('appointments').doc(id).update({
      'status': status,
    });
  }

  // --- Favorites ---

  // (This can be stored in the User document or a separate collection)
  // Let's store favorites as a list of IDs in the user document for simplicity
  Future<void> toggleFavorite(
    String userId,
    String salonId,
    bool isFavorite,
  ) async {
    DocumentReference userRef = _firestore.collection('users').doc(userId);
    if (isFavorite) {
      await userRef.update({
        'favorites': FieldValue.arrayUnion([salonId]),
      });
    } else {
      await userRef.update({
        'favorites': FieldValue.arrayRemove([salonId]),
      });
    }
  }

  // Get user by ID (Stream)
  Stream<UserModel?> getUserStream(String uid) {
    return _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? UserModel.fromFirestore(doc) : null);
  }

  // Update user with claimed offer
  Future<void> claimFirstBookingOffer(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'hasClaimedOffer': true,
    });
  }

  // Permanently marks the promo code as used — blocks any future reuse
  Future<void> markPromoCodeUsed(String userId) async {
    await _firestore.collection('users').doc(userId).update({
      'promoCodeUsed': true,
    });
  }

  // Update FCM token for push notifications
  Future<void> updateFcmToken(String userId, String token) async {
    await _firestore.collection('users').doc(userId).update({
      'fcmToken': token,
    });
  }

  // --- Notification Operations ---

  // Stream all notifications for a user (ordered by date, max 30 days)
  Stream<List<NotificationModel>> getNotifications(String userId) {
    final cutoff = DateTime.now().subtract(const Duration(days: 30));
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .limit(50)
        .snapshots()
        .map((snapshot) {
          final list = snapshot.docs
              .map((doc) => NotificationModel.fromFirestore(doc))
              .where((n) => n.createdAt.isAfter(cutoff))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  // Stream unread notification count (for badge)
  Stream<int> getUnreadNotificationCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }

  // Mark a single notification as read
  Future<void> markNotificationRead(String notificationId) async {
    await _firestore.collection('notifications').doc(notificationId).update({
      'isRead': true,
    });
  }

  // Mark all notifications as read (batch)
  Future<void> markAllNotificationsRead(String userId) async {
    final batch = _firestore.batch();
    final snapshot = await _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .get();
    for (final doc in snapshot.docs) {
      batch.update(doc.reference, {'isRead': true});
    }
    await batch.commit();
  }

  // ── Owner-specific queries ────────────────────────────────────────────────

  /// Returns the salon that belongs to [ownerId] as a live stream.
  Stream<SalonModel?> getOwnerSalon(String ownerId) {
    return _firestore
        .collection('salons')
        .where('ownerId', isEqualTo: ownerId)
        .limit(1)
        .snapshots()
        .map((snap) => snap.docs.isEmpty
            ? null
            : SalonModel.fromFirestore(snap.docs.first));
  }

  /// Returns all appointments booked at [salonId], ordered by date desc.
  Stream<List<AppointmentModel>> getSalonAppointments(String salonId) {
    return _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .limit(100)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AppointmentModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
          return list;
        });
  }

  /// Fetches the full name of a client by their user ID.
  Future<String> getClientName(String clientId) async {
    try {
      final doc = await _firestore.collection('users').doc(clientId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        return (data['fullName'] as String?)?.trim().isNotEmpty == true
            ? data['fullName'] as String
            : 'Client';
      }
    } catch (_) {}
    return 'Client';
  }

  Future<String?> getClientPhone(String clientId) async {
    try {
      final doc = await _firestore.collection('users').doc(clientId).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final phone = data['phone'] as String?;
        if (phone != null && phone.trim().isNotEmpty) return phone;
      }
    } catch (_) {}
    return null;
  }

  // Save a new notification to Firestore
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
  }) async {
    await _firestore.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'isRead': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Review Operations ---

  /// Stream all reviews for a salon, ordered by date desc.
  Stream<List<ReviewModel>> getReviews(String salonId) {
    return _firestore
        .collection('reviews')
        .where('salonId', isEqualTo: salonId)
        .limit(30)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((doc) => ReviewModel.fromFirestore(doc))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Check if [userId] has already reviewed [salonId].
  Future<bool> hasUserReviewed(String salonId, String userId) async {
    final snap = await _firestore
        .collection('reviews')
        .where('salonId', isEqualTo: salonId)
        .where('userId', isEqualTo: userId)
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  // --- Points / Rewards ---

  /// Returns total valid (non-expired, non-used) points for [userId] at [salonId].
  Future<double> getUserPointsForSalon(String userId, String salonId) async {
    final now = DateTime.now();
    final snap = await _firestore
        .collection('points')
        .where('userId', isEqualTo: userId)
        .where('salonId', isEqualTo: salonId)
        .where('isUsed', isEqualTo: false)
        .get();
    double total = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final expiresAt = (data['expiresAt'] as Timestamp).toDate();
      if (expiresAt.isAfter(now)) {
        total += (data['amount'] as num).toDouble();
      }
    }
    return total;
  }

  /// Awards 5 % of [bookingAmount] as points to [userId] for [salonId].
  /// Idempotent (one award per booking). Prevents self-charging.
  Future<void> awardPoints({
    required String userId,
    required String salonId,
    required double bookingAmount,
    required String bookingId,
  }) async {
    // Anti-fraud: never award if the client is the salon owner
    final salonDoc = await _firestore.collection('salons').doc(salonId).get();
    if (!salonDoc.exists) return;
    final ownerId =
        ((salonDoc.data() as Map<String, dynamic>)['ownerId'] as String?) ?? '';
    if (ownerId == userId) return;

    // Idempotency: skip if points were already awarded for this booking
    final existing = await _firestore
        .collection('points')
        .where('bookingId', isEqualTo: bookingId)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) return;

    final pointAmount = bookingAmount * 0.05;
    if (pointAmount <= 0) return;

    await _firestore.collection('points').add({
      'userId': userId,
      'salonId': salonId,
      'amount': pointAmount,
      'bookingId': bookingId,
      'isUsed': false,
      'expiresAt': Timestamp.fromDate(
          DateTime.now().add(const Duration(days: 30))),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  /// Marks all valid (non-expired) points for [userId] at [salonId] as used.
  Future<void> redeemPoints(String userId, String salonId) async {
    final now = DateTime.now();
    final snap = await _firestore
        .collection('points')
        .where('userId', isEqualTo: userId)
        .where('salonId', isEqualTo: salonId)
        .where('isUsed', isEqualTo: false)
        .get();
    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      final expiresAt =
          ((doc.data())['expiresAt'] as Timestamp).toDate();
      if (expiresAt.isAfter(now)) {
        batch.update(doc.reference, {'isUsed': true});
      }
    }
    await batch.commit();
  }

  // ── Inventory Operations ──────────────────────────────────────────────────

  Stream<List<InventoryModel>> getInventory(String salonId) {
    return _firestore
        .collection('inventory')
        .where('salonId', isEqualTo: salonId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => InventoryModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          return list;
        });
  }

  Future<void> addInventoryItem(InventoryModel item) async {
    await _firestore.collection('inventory').add(item.toMap());
  }

  Future<void> updateInventoryItem(String id, Map<String, dynamic> data) async {
    await _firestore.collection('inventory').doc(id).update(data);
  }

  Future<void> deleteInventoryItem(String id) async {
    await _firestore.collection('inventory').doc(id).delete();
  }

  // ── Charge Operations ─────────────────────────────────────────────────────

  Stream<List<ChargeModel>> getCharges(String salonId, int month, int year) {
    return _firestore
        .collection('charges')
        .where('salonId', isEqualTo: salonId)
        .where('month', isEqualTo: month)
        .where('year', isEqualTo: year)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => ChargeModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Returns total revenue (sum of completed appointment prices) for a given month/year.
  Future<double> getMonthlyRevenue(
      String salonId, int month, int year) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .get();
    return snap.docs.fold<double>(0, (acc, d) {
      final data = d.data();
      final status = data['status'] as String? ?? '';
      if (status != 'completed') return acc;
      final ts = data['dateTime'] as Timestamp?;
      if (ts == null) return acc;
      final dt = ts.toDate();
      if (dt.isBefore(start) || !dt.isBefore(end)) return acc;
      return acc + ((data['price'] as num?)?.toDouble() ?? 0);
    });
  }

  Future<void> addCharge(ChargeModel charge) async {
    await _firestore.collection('charges').add(charge.toMap());
  }

  Future<void> deleteCharge(String id) async {
    await _firestore.collection('charges').doc(id).delete();
  }

  // ── Promotion Operations ──────────────────────────────────────────────────

  Stream<List<PromotionModel>> getPromotions(String salonId) {
    return _firestore
        .collection('promotions')
        .where('salonId', isEqualTo: salonId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => PromotionModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  /// Fetches active promotions across all salons, paired with their salon.
  Future<List<({SalonModel salon, PromotionModel promo})>> getDealsWithSalons(
      {int limit = 10}) async {
    // Single-field where only — no composite index required.
    final snap = await _firestore
        .collection('promotions')
        .where('isActive', isEqualTo: true)
        .limit(limit * 2)
        .get();

    // Sort client-side by createdAt descending, then filter expired.
    final promos = snap.docs
        .map((d) => PromotionModel.fromFirestore(d))
        .where((p) => !p.isExpired)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    final limited = promos.take(limit).toList();

    if (limited.isEmpty) return [];

    final salonIds = limited.map((p) => p.salonId).toSet().take(10).toList();

    final salonSnap = await _firestore
        .collection('salons')
        .where(FieldPath.documentId, whereIn: salonIds)
        .get();

    final salonsMap = {
      for (final doc in salonSnap.docs)
        doc.id: SalonModel.fromFirestore(doc),
    };

    return limited
        .where((p) => salonsMap.containsKey(p.salonId))
        .map((p) => (salon: salonsMap[p.salonId]!, promo: p))
        .toList();
  }

  Stream<List<PromotionModel>> getActivePromotions(String salonId, {String? clientId}) {
    return _firestore
        .collection('promotions')
        .where('salonId', isEqualTo: salonId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => PromotionModel.fromFirestore(d))
            .where((p) => !p.isExpired)
            .where((p) => p.isVisibleTo(clientId))
            .toList());
  }

  Future<void> addPromotion(PromotionModel promo) async {
    await _firestore.collection('promotions').add(promo.toMap());
  }

  Future<void> togglePromotionActive(String id, bool isActive) async {
    await _firestore
        .collection('promotions')
        .doc(id)
        .update({'isActive': isActive});
  }

  Future<void> deletePromotion(String id) async {
    await _firestore.collection('promotions').doc(id).delete();
  }

  // ── Team Member Operations ────────────────────────────────────────────────

  /// Stream all team members for a salon.
  Stream<List<TeamMemberModel>> getTeamMembers(String salonId) {
    return _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => TeamMemberModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => a.name.compareTo(b.name));
          return list;
        });
  }

  /// One-shot fetch of appointments for a salon on a specific date (non-cancelled).
  Future<List<AppointmentModel>> getSalonAppointmentsForDate(
      String salonId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    // Single-field where to avoid composite index requirement;
    // date filtering done client-side.
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .get();
    return snap.docs
        .map((d) => AppointmentModel.fromFirestore(d))
        .where((a) =>
            a.status != 'cancelled' &&
            !a.dateTime.isBefore(startOfDay) &&
            a.dateTime.isBefore(endOfDay))
        .toList();
  }

  /// One-shot fetch of all team members (used in booking flow).
  Future<List<TeamMemberModel>> getTeamMembersOnce(String salonId) async {
    final snap = await _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .get();
    final list =
        snap.docs.map((d) => TeamMemberModel.fromFirestore(d)).toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }

  /// Add a new team member to a salon.
  Future<TeamMemberModel> addTeamMember(TeamMemberModel member) async {
    final docRef = await _firestore
        .collection('salons')
        .doc(member.salonId)
        .collection('teamMembers')
        .add(member.toMap());
    return TeamMemberModel(
      id: docRef.id,
      salonId: member.salonId,
      name: member.name,
      role: member.role,
      pinHash: member.pinHash,
      phone: member.phone,
      isActive: member.isActive,
      createdAt: member.createdAt,
      unavailableDates: member.unavailableDates,
      assignedServiceNames: member.assignedServiceNames,
    );
  }

  /// Update a team member's fields.
  Future<void> updateTeamMember(
      String salonId, String memberId, Map<String, dynamic> data) async {
    await _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .doc(memberId)
        .update(data);
  }

  /// Delete a team member.
  Future<void> deleteTeamMember(String salonId, String memberId) async {
    await _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .doc(memberId)
        .delete();
  }

  /// Assign an appointment to a team member.
  Future<void> assignAppointment(
      String appointmentId, String memberId, String memberName) async {
    await _firestore.collection('appointments').doc(appointmentId).update({
      'assignedMemberId': memberId,
      'assignedMemberName': memberName,
    });
  }

  /// Stream appointments assigned to a specific team member.
  Stream<List<AppointmentModel>> getMemberAppointments(
      String salonId, String memberId) {
    return _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('assignedMemberId', isEqualTo: memberId)
        .limit(50)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => AppointmentModel.fromFirestore(d))
              .toList();
          list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
          return list;
        });
  }

  /// Get appointments for a specific member on a specific date (one-shot).
  Future<List<AppointmentModel>> getAppointmentsForMemberOnDate(
      String salonId, String memberId, DateTime dayStart, DateTime dayEnd) async {
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('assignedMemberId', isEqualTo: memberId)
        .get();
    return snap.docs
        .map((d) => AppointmentModel.fromFirestore(d))
        .where((a) =>
            a.dateTime.isAfter(dayStart.subtract(const Duration(seconds: 1))) &&
            a.dateTime.isBefore(dayEnd) &&
            a.status != 'cancelled')
        .toList();
  }

  /// Update the unavailable dates list for a team member.
  Future<void> setUnavailableDates(
      String salonId, String memberId, List<String> dates) {
    return _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .doc(memberId)
        .update({'unavailableDates': dates});
  }

  /// Update the unavailable time slots for a team member.
  Future<void> setUnavailableSlots(
      String salonId, String memberId, Map<String, List<String>> slots) {
    return _firestore
        .collection('salons')
        .doc(salonId)
        .collection('teamMembers')
        .doc(memberId)
        .update({'unavailableSlots': slots});
  }

  // ── Waitlist ───────────────────────────────────────────────────────────────

  /// Add a client to the waitlist for a specific salon/date/service.
  Future<void> addToWaitlist(WaitlistEntry entry) {
    return _firestore.collection('waitlist').doc(entry.id).set(entry.toMap());
  }

  /// Check if a client is already on the waitlist for a given salon + date.
  Future<bool> isOnWaitlist(String clientId, String salonId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snap = await _firestore
        .collection('waitlist')
        .where('clientId', isEqualTo: clientId)
        .where('salonId', isEqualTo: salonId)
        .get();
    return snap.docs.any((d) {
      final dt = (d.data()['desiredDate'] as Timestamp).toDate();
      return !dt.isBefore(startOfDay) && dt.isBefore(endOfDay);
    });
  }

  /// Get waitlist entries for a salon on a specific date (for notification on cancel).
  Future<List<WaitlistEntry>> getWaitlistForDate(String salonId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snap = await _firestore
        .collection('waitlist')
        .where('salonId', isEqualTo: salonId)
        .where('notified', isEqualTo: false)
        .get();
    return snap.docs
        .map((d) => WaitlistEntry.fromFirestore(d))
        .where((e) =>
            !e.desiredDate.isBefore(startOfDay) &&
            e.desiredDate.isBefore(endOfDay))
        .toList();
  }

  /// Mark a waitlist entry as notified.
  Future<void> markWaitlistNotified(String entryId) {
    return _firestore.collection('waitlist').doc(entryId).update({'notified': true});
  }

  /// Remove a waitlist entry.
  Future<void> removeFromWaitlist(String entryId) {
    return _firestore.collection('waitlist').doc(entryId).delete();
  }

  /// Get client's active waitlist entries.
  Stream<List<WaitlistEntry>> getClientWaitlist(String clientId) {
    return _firestore
        .collection('waitlist')
        .where('clientId', isEqualTo: clientId)
        .where('notified', isEqualTo: false)
        .snapshots()
        .map((snap) {
          final list = snap.docs.map((d) => WaitlistEntry.fromFirestore(d)).toList();
          list.sort((a, b) => a.desiredDate.compareTo(b.desiredDate));
          return list;
        });
  }

  // ─────────────────────────────────────────────────────────────────────────

  /// Submit a review and recalculate the salon average rating atomically.
  Future<void> submitReview({
    required String salonId,
    required String userId,
    required String userName,
    required int rating,
    required String comment,
  }) async {
    final reviewRef = _firestore.collection('reviews').doc();
    final salonRef = _firestore.collection('salons').doc(salonId);

    await _firestore.runTransaction((tx) async {
      final salonSnap = await tx.get(salonRef);
      final data = salonSnap.data() as Map<String, dynamic>;
      final currentCount = (data['reviewCount'] ?? 0) as int;
      final currentRating = (data['rating'] ?? 0.0).toDouble();

      // Compute new average
      final newCount = currentCount + 1;
      final newRating =
          ((currentRating * currentCount) + rating) / newCount;

      tx.set(reviewRef, {
        'salonId': salonId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment,
        'createdAt': FieldValue.serverTimestamp(),
      });

      tx.update(salonRef, {
        'rating': double.parse(newRating.toStringAsFixed(1)),
        'reviewCount': newCount,
      });
    });
  }

  // ─── Update single salon field ───────────────────────────────────────────

  Future<void> updateSalonField(String salonId, String field, dynamic value) async {
    await _firestore.collection('salons').doc(salonId).update({field: value});
  }

  // ─── Gallery Management ──────────────────────────────────────────────────

  Future<void> updateSalonImages(String salonId, List<String> images) async {
    await _firestore.collection('salons').doc(salonId).update({
      'images': images,
    });
  }

  // ─── Before/After ────────────────────────────────────────────────────────

  Future<void> addBeforeAfter(String salonId, Map<String, dynamic> data) async {
    await _firestore
        .collection('salons')
        .doc(salonId)
        .collection('beforeAfter')
        .add(data);
  }

  Stream<List<Map<String, dynamic>>> getBeforeAfterStream(String salonId) {
    return _firestore
        .collection('salons')
        .doc(salonId)
        .collection('beforeAfter')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map((d) {
              final data = d.data();
              data['id'] = d.id;
              return data;
            }).toList());
  }

  Future<void> deleteBeforeAfter(String salonId, String docId) async {
    await _firestore
        .collection('salons')
        .doc(salonId)
        .collection('beforeAfter')
        .doc(docId)
        .delete();
  }

  // --- Products (Boutique) ---

  Stream<List<ProductModel>> getProducts(String salonId) {
    return _firestore
        .collection('products')
        .where('salonId', isEqualTo: salonId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ProductModel.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<ProductModel>> getActiveProducts(String salonId) {
    return _firestore
        .collection('products')
        .where('salonId', isEqualTo: salonId)
        .where('isActive', isEqualTo: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ProductModel.fromFirestore(d))
            .where((p) => p.stock > 0)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<String> addProduct(ProductModel product) async {
    final ref =
        await _firestore.collection('products').add(product.toMap());
    return ref.id;
  }

  Future<void> updateProduct(String productId, Map<String, dynamic> data) async {
    await _firestore.collection('products').doc(productId).update(data);
  }

  Future<void> deleteProduct(String productId) async {
    await _firestore.collection('products').doc(productId).delete();
  }

  Future<void> decrementProductStock(String productId, int quantity) async {
    await _firestore.collection('products').doc(productId).update({
      'stock': FieldValue.increment(-quantity),
    });
  }

  // --- Orders (Boutique) ---

  Stream<List<OrderModel>> getSalonOrders(String salonId) {
    return _firestore
        .collection('orders')
        .where('salonId', isEqualTo: salonId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderModel.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Stream<List<OrderModel>> getClientOrders(String clientId) {
    return _firestore
        .collection('orders')
        .where('clientId', isEqualTo: clientId)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => OrderModel.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<String> createOrder(OrderModel order) async {
    final ref = await _firestore.collection('orders').add(order.toMap());
    // Decrement stock for each item
    for (final item in order.items) {
      await decrementProductStock(item.productId, item.quantity);
    }
    return ref.id;
  }

  Future<void> updateOrderStatus(String orderId, String status) async {
    await _firestore.collection('orders').doc(orderId).update({
      'status': status,
    });
  }

  // ── Google Review Rewards ─────────────────────────────────────────────────

  Stream<List<ReviewRewardModel>> getPendingReviewRewards(String salonId) {
    return _firestore
        .collection('reviewRewards')
        .where('salonId', isEqualTo: salonId)
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => ReviewRewardModel.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
  }

  Future<void> validateReviewReward(String rewardId, String promoCode) async {
    await _firestore.collection('reviewRewards').doc(rewardId).update({
      'status': 'validated',
      'promoCode': promoCode,
      'validatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> rejectReviewReward(String rewardId) async {
    await _firestore.collection('reviewRewards').doc(rewardId).update({
      'status': 'rejected',
      'validatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGoogleReviewReward(
      String salonId, Map<String, dynamic> config) async {
    await _firestore.collection('salons').doc(salonId).update({
      'googleReviewReward': config,
    });
  }
}
