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
import '../models/client_summary_model.dart';

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
      currency: salon.currency,
      rewardPointsEnabled: salon.rewardPointsEnabled,
      aiPromosEnabled: salon.aiPromosEnabled,
      aiPromoConfig: salon.aiPromoConfig,
      googleReviewReward: salon.googleReviewReward,
      isPremium: salon.isPremium,
      galleryStorageUsed: salon.galleryStorageUsed,
      salonType: salon.salonType,
      plan: salon.plan,
      timezone: salon.timezone,
    );

    // Build the write map manually so we never overwrite server-controlled
    // fields with the locally-cached value. Plan, isPremium, trial flags,
    // rating / reviewCount, and bot lifecycle fields are written by Cloud
    // Functions only (RC webhook, onReviewWrite, onSalonPlanChange). If we
    // include them in saveSalon's merge write, a stale local SalonModel
    // will silently revert any server-side change between fetch and save.
    final fullMap = updatedSalon.toMap();
    const serverControlled = {
      'plan',
      'pendingPlan',
      'pendingPlanSetAt',
      'isPremium',
      'subscriptionTier',
      'trialEndsAt',
      'freeCapGraceEndsAt',
      'paidPlanEverActivated',
      'lastRevenueCatEventType',
      'lastRevenueCatEventAt',
      'rating',
      'reviewCount',
      'botStatus',
      'botWhatsapp',
      'botSetupComplete',
      'botFirstMsgSent',
    };
    final clientMap = <String, dynamic>{
      for (final entry in fullMap.entries)
        if (!serverControlled.contains(entry.key)) entry.key: entry.value,
    };

    await _firestore
        .collection('salons')
        .doc(updatedSalon.id)
        .set(clientMap, SetOptions(merge: true));
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

  // Create Appointment — splits PII into `private/contact` subcollection
  // so `appointments/{id}` stays safe for public read.
  Future<void> createAppointment(AppointmentModel appointment) async {
    final docRef =
        _firestore.collection('appointments').doc(appointment.id);
    final batch = _firestore.batch();
    batch.set(docRef, appointment.toPublicMap());
    final privateMap = appointment.toPrivateMap();
    if (privateMap.isNotEmpty) {
      batch.set(docRef.collection('private').doc('contact'), privateMap);
    }
    await batch.commit();
  }

  /// Dual-source hydration: for each appointment doc, merge PII into the
  /// model. For appointments with a real `clientId` (registered user), we
  /// resolve name + phone via the in-session user cache instead of the
  /// `private/contact` subcoll — this saves ~1 read per appointment per
  /// query, which is the dominant per-appt cost on agenda/home/RDV list.
  ///
  /// Trade-off: the owner sees the user's CURRENT profile name/phone rather
  /// than the snapshot taken at booking time. In practice clients rarely
  /// rename themselves and this matches what they want owners to see.
  ///
  /// Walk-in bookings (`clientId == 'walk-in'`) and other anonymous flows
  /// have no user doc to fall back on, so we still read the subcoll.
  /// Falls back gracefully if subcol is absent (legacy flat docs).
  Future<List<AppointmentModel>> _enrichWithPrivate(
      Iterable<DocumentSnapshot<Map<String, dynamic>>> docs) async {
    return Future.wait(docs.map((doc) async {
      final appt = AppointmentModel.fromFirestore(doc);
      // Legacy flat format already has PII in main doc
      if (appt.clientName != null || appt.clientPhone != null) {
        return appt;
      }
      // Registered client → cheap path via cached user doc.
      if (appt.clientId.isNotEmpty && appt.clientId != 'walk-in') {
        final user = await getCachedUser(appt.clientId);
        if (user != null) {
          final name = user.fullName.trim();
          final wa = user.whatsapp.trim();
          return appt.copyWith(
            clientName: name.isNotEmpty ? name : null,
            clientPhone: wa.isNotEmpty ? wa : null,
          );
        }
      }
      // Walk-in or user doc missing → read the private subcoll.
      try {
        final priv = await doc.reference
            .collection('private')
            .doc('contact')
            .get();
        if (priv.exists) {
          final data = priv.data()!;
          return appt.copyWith(
            clientName: data['clientName'] as String?,
            clientPhone: data['clientPhone'] as String?,
            managementToken: data['managementToken'] as String?,
          );
        }
      } catch (_) {
        // Private subcol unreadable (rules block or not yet migrated) — return appt as-is
      }
      return appt;
    }));
  }

  // Get completed appointments once (for recommendations)
  Future<List<AppointmentModel>> getCompletedAppointmentsOnce(String clientId) async {
    final snapshot = await _firestore
        .collection('appointments')
        .where('clientId', isEqualTo: clientId)
        .where('status', isEqualTo: 'completed')
        .limit(20)
        .get();
    return _enrichWithPrivate(snapshot.docs);
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

  /// Live stream of all appointments for [salonId] within a date range.
  /// Server-side filtered — no client-side limit, scales to any volume.
  /// Requires composite index (salonId ASC, dateTime ASC).
  Stream<List<AppointmentModel>> streamSalonAppointmentsForRange(
      String salonId, DateTime start, DateTime end) {
    return _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dateTime', isLessThan: Timestamp.fromDate(end))
        .snapshots()
        .asyncMap((snap) async {
          final list = await _enrichWithPrivate(snap.docs);
          list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
          return list;
        });
  }

  /// Live stream of per-client aggregates for a salon, maintained by the
  /// `maintainClientSummary` Cloud Function. [since] filters server-side on
  /// `lastVisit` — pass null to stream every client (opt-in "All" view).
  Stream<List<ClientSummaryModel>> streamClientSummaries(
      String salonId, {DateTime? since}) {
    Query<Map<String, dynamic>> q = _firestore
        .collection('salons')
        .doc(salonId)
        .collection('clientSummaries')
        .orderBy('lastVisit', descending: true);
    if (since != null) {
      q = q.where('lastVisit',
          isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }
    return q.snapshots().map((snap) =>
        snap.docs.map((d) => ClientSummaryModel.fromFirestore(d)).toList());
  }

  /// Number of completed appointments for [salonId] during [year]/[month].
  /// Uses Firestore server-side count() aggregation — 1 read regardless of
  /// how many docs match. Refresh by invalidating the wrapping provider.
  Future<int> getMonthlyCompletedCount(
      String salonId, int year, int month) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final agg = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('status', isEqualTo: 'completed')
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dateTime', isLessThan: Timestamp.fromDate(end))
        .count()
        .get();
    return agg.count ?? 0;
  }

  /// Total revenue for [salonId] during [year]/[month] (one-shot).
  /// Uses Firestore server-side sum() aggregation — 1 read regardless of
  /// how many completed RDV the month contains. Replaces the previous
  /// stream variant that downloaded every doc and folded client-side.
  Future<double> getMonthlyRevenue(
      String salonId, int year, int month) async {
    final start = DateTime(year, month);
    final end = DateTime(year, month + 1);
    final agg = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('status', isEqualTo: 'completed')
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dateTime', isLessThan: Timestamp.fromDate(end))
        .aggregate(sum('price'))
        .get();
    final raw = agg.getSum('price');
    return raw?.toDouble() ?? 0.0;
  }

  /// Returns all appointments booked at [salonId], ordered by date desc.
  Stream<List<AppointmentModel>> getSalonAppointments(String salonId) {
    return _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .limit(100)
        .snapshots()
        .asyncMap((snap) async {
          final list = await _enrichWithPrivate(snap.docs);
          list.sort((a, b) => b.dateTime.compareTo(a.dateTime));
          return list;
        });
  }

  // Session-scope cache of user docs. The agenda / home / appointments
  // screens previously hit `users/{id}.get()` once for `getClientName`
  // AND once for `getClientPhone` per appointment per render — for a
  // 138-RDV salon that's 276 reads on every screen open. Caching at
  // this layer collapses both into a single fetch per uid per session
  // (Firestore document caches at the SDK level too, but only within
  // an active listener — for one-shot `.get()` it doesn't help).
  // Cleared on signout via `clearUserCache()` (called from auth flow).
  static final Map<String, Future<UserModel?>> _userCache = {};

  /// Returns the cached UserModel for `uid`, fetching once if absent.
  /// Falls back to null if the doc doesn't exist or the fetch errors.
  Future<UserModel?> getCachedUser(String uid) {
    if (uid.isEmpty || uid == 'walk-in') return Future.value(null);
    return _userCache.putIfAbsent(uid, () async {
      try {
        final doc = await _firestore.collection('users').doc(uid).get();
        return doc.exists ? UserModel.fromFirestore(doc) : null;
      } catch (_) {
        return null;
      }
    });
  }

  /// Drops one entry (or the whole map) from the cache. Call after a
  /// mutation that changes the user doc, or on signout.
  static void clearUserCache([String? uid]) {
    if (uid == null) {
      _userCache.clear();
    } else {
      _userCache.remove(uid);
    }
  }

  /// Fetches the full name of a client by their user ID.
  Future<String> getClientName(String clientId) async {
    final user = await getCachedUser(clientId);
    final name = user?.fullName.trim();
    return (name != null && name.isNotEmpty) ? name : 'Client';
  }

  Future<String?> getClientPhone(String clientId) async {
    final user = await getCachedUser(clientId);
    // UserModel.whatsapp already folds the legacy `phone` fallback in.
    final wa = user?.whatsapp.trim();
    if (wa != null && wa.isNotEmpty) return wa;
    return null;
  }

  // Save a new notification to Firestore.
  // pushSent defaults to true so the onNewNotification Cloud Function skips
  // this doc (the local app already showed the banner). Set false only when
  // the server should send an FCM push for this notification.
  Future<void> saveNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    bool pushSent = true,
  }) async {
    await _firestore.collection('notifications').add({
      'userId': userId,
      'title': title,
      'body': body,
      'type': type,
      'isRead': false,
      'pushSent': pushSent,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // --- Review Operations ---

  /// Stream reviews posted after [since] for [salonId], newest first.
  /// Server-side filtered by `createdAt` — no arbitrary limit, scales
  /// whatever the salon's total review count.
  /// Requires composite index: reviews (salonId ASC, createdAt ASC).
  Stream<List<ReviewModel>> streamRecentReviews(String salonId, DateTime since) {
    return _firestore
        .collection('reviews')
        .where('salonId', isEqualTo: salonId)
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(since))
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

  /// Cascades isActive to every AI-generated promo of the salon. Called
  /// when the owner flips the master `aiPromosEnabled` switch so the
  /// existing rule docs (anniversaire/top client/fidèle/absent) reflect
  /// the new master state immediately, without waiting for the daily
  /// `generateSmartPromotions` cron pass.
  Future<void> setAiPromotionsActive(String salonId, bool isActive) async {
    final snap = await _firestore
        .collection('promotions')
        .where('salonId', isEqualTo: salonId)
        .where('isAiGenerated', isEqualTo: true)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = _firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'isActive': isActive});
    }
    await batch.commit();
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
  /// Server-side filtered by date — requires index (salonId, dateTime).
  Future<List<AppointmentModel>> getSalonAppointmentsForDate(
      String salonId, DateTime date) async {
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('dateTime',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .where('dateTime', isLessThan: Timestamp.fromDate(endOfDay))
        .get();
    final all = await _enrichWithPrivate(snap.docs);
    return all.where((a) => a.status != 'cancelled').toList();
  }

  /// Get all appointments for a salon within a date range (for calendar dots).
  /// Server-side filtered by date — requires index (salonId, dateTime).
  Future<List<AppointmentModel>> getSalonAppointmentsForRange(
      String salonId, DateTime start, DateTime end) async {
    final endExclusive = end.add(const Duration(days: 1));
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('dateTime', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
        .where('dateTime', isLessThan: Timestamp.fromDate(endExclusive))
        .get();
    return snap.docs
        .map((d) => AppointmentModel.fromFirestore(d))
        .where((a) => a.status != 'cancelled')
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
      agendaColorIndex: member.agendaColorIndex,
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

  /// Get upcoming appointments assigned to a member (one-shot).
  /// Used when deleting a member to warn about active bookings.
  Future<List<AppointmentModel>> getUpcomingAppointmentsForMember(
      String salonId, String memberId) async {
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('assignedMemberId', isEqualTo: memberId)
        .where('status', isEqualTo: 'upcoming')
        .get();
    final list = await _enrichWithPrivate(snap.docs);
    list.sort((a, b) => a.dateTime.compareTo(b.dateTime));
    return list;
  }

  /// Get all upcoming appointments for a salon (one-shot).
  /// Used by reassignment logic to check member availability.
  Future<List<AppointmentModel>> getUpcomingAppointmentsForSalon(
      String salonId) async {
    final snap = await _firestore
        .collection('appointments')
        .where('salonId', isEqualTo: salonId)
        .where('status', isEqualTo: 'upcoming')
        .get();
    return snap.docs.map((d) => AppointmentModel.fromFirestore(d)).toList();
  }

  /// Batch reassign appointments to new members.
  /// [assignments] maps appointmentId → {memberId, memberName}.
  Future<void> reassignAppointments(
      Map<String, Map<String, String>> assignments) async {
    final batch = _firestore.batch();
    assignments.forEach((apptId, data) {
      batch.update(_firestore.collection('appointments').doc(apptId), {
        'assignedMemberId': data['memberId'],
        'assignedMemberName': data['memberName'],
      });
    });
    await batch.commit();
  }

  /// Assign an appointment to a team member.
  Future<void> assignAppointment(
      String appointmentId, String memberId, String memberName) async {
    await _firestore.collection('appointments').doc(appointmentId).update({
      'assignedMemberId': memberId,
      'assignedMemberName': memberName,
    });
  }

  /// Reschedule an existing appointment to a new wall-clock UTC date+time.
  /// Wall-clock UTC = the local date+time the user picked, stored without
  /// timezone conversion (matches how the rest of the system stores
  /// appointments, cf project memory).
  Future<void> rescheduleAppointment(
      String appointmentId, DateTime newDateTime) async {
    final wallClockUtc = DateTime.utc(
      newDateTime.year,
      newDateTime.month,
      newDateTime.day,
      newDateTime.hour,
      newDateTime.minute,
    );
    await _firestore.collection('appointments').doc(appointmentId).update({
      'dateTime': Timestamp.fromDate(wallClockUtc),
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
        .asyncMap((snap) async {
          final list = await _enrichWithPrivate(snap.docs);
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

  /// Live stream of pending (not yet notified) waitlist entries for a salon.
  Stream<List<WaitlistEntry>> getSalonWaitlistPending(String salonId) {
    return _firestore
        .collection('waitlist')
        .where('salonId', isEqualTo: salonId)
        .where('notified', isEqualTo: false)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => WaitlistEntry.fromFirestore(d))
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
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

  /// Submit a review. Salon rating/reviewCount are recomputed server-side
  /// by the `onReviewWrite` Cloud Function — clients only write the review doc.
  Future<void> submitReview({
    required String salonId,
    required String userId,
    required String userName,
    required int rating,
    required String comment,
  }) async {
    await _firestore.collection('reviews').add({
      'salonId': salonId,
      'userId': userId,
      'userName': userName,
      'rating': rating,
      'comment': comment,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // ─── Update single salon field ───────────────────────────────────────────

  Future<void> updateSalonField(String salonId, String field, dynamic value) async {
    await _firestore.collection('salons').doc(salonId).update({field: value});
  }

  // ─── Blacklist Management ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getBlacklist(String salonId) async {
    final doc = await _firestore.collection('salons').doc(salonId).get();
    final data = doc.data();
    if (data == null || data['blacklist'] == null) return [];
    return List<Map<String, dynamic>>.from(data['blacklist']);
  }

  Future<void> addToBlacklist(String salonId, Map<String, dynamic> entry) async {
    await _firestore.collection('salons').doc(salonId).update({
      'blacklist': FieldValue.arrayUnion([entry]),
    });
  }

  Future<void> removeFromBlacklist(String salonId, Map<String, dynamic> entry) async {
    await _firestore.collection('salons').doc(salonId).update({
      'blacklist': FieldValue.arrayRemove([entry]),
    });
  }

  Future<bool> isBlacklisted(String salonId, {String? phone, String? userId}) async {
    final blacklist = await getBlacklist(salonId);
    for (final entry in blacklist) {
      if (phone != null && entry['phone'] == phone) return true;
      if (userId != null && entry['userId'] == userId) return true;
    }
    return false;
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
    final orderRef = _firestore.collection('orders').doc(orderId);
    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) return;
      final prevStatus = (snap.data()?['status'] ?? '') as String;
      if (prevStatus == status) return;

      // Transitioning INTO cancelled from a non-cancelled state → restore stock.
      // Read all product docs first (Firestore transactions require reads before writes),
      // skip any that have been deleted since the order was placed.
      final toRestore = <DocumentReference, int>{};
      if (status == 'cancelled' && prevStatus != 'cancelled') {
        final items = (snap.data()?['items'] as List?) ?? const [];
        for (final raw in items) {
          final map = raw as Map<String, dynamic>;
          final productId = map['productId'] as String?;
          final qty = (map['quantity'] as num?)?.toInt() ?? 0;
          if (productId == null || productId.isEmpty || qty <= 0) continue;
          final productRef = _firestore.collection('products').doc(productId);
          final productSnap = await tx.get(productRef);
          if (productSnap.exists) toRestore[productRef] = qty;
        }
      }

      for (final entry in toRestore.entries) {
        tx.update(entry.key, {'stock': FieldValue.increment(entry.value)});
      }
      tx.update(orderRef, {'status': status});
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
