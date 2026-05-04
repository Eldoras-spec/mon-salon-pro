import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/appointment_model.dart';
import '../models/review_reward_model.dart';
import '../services/database_service.dart';
import '../services/message_service.dart';
import 'owner_providers.dart';

final _db = DatabaseService();

enum OwnerTaskType {
  messages,
  pendingOrders,
  noShowRisk,
  badReviews,
  pendingRewards,
  lowStock,
}

class NoShowRiskClient {
  const NoShowRiskClient({
    required this.clientId,
    required this.clientName,
    required this.clientPhone,
    required this.totalPast,
    required this.cancelledPast,
    required this.rate,
    required this.todayAppt,
    this.isCrossSalon = false,
  });

  final String clientId;
  final String clientName;
  final String? clientPhone;
  final int totalPast;
  final int cancelledPast;
  final int rate; // 0..100
  final AppointmentModel todayAppt;

  /// True when the flag comes from the GLOBAL cross-salon reputation
  /// (`clientReputation/{uid}`) rather than this salon's own history —
  /// the client doesn't have enough cancellations on THIS salon but
  /// has a high cancellation rate across other salons. The owner only
  /// sees the aggregate rate, never which salons flagged the client.
  final bool isCrossSalon;
}

class OwnerTask {
  const OwnerTask({
    required this.type,
    required this.count,
    required this.priority,
  });

  /// Fixed type of the task (determines icon, color, route).
  final OwnerTaskType type;

  /// Number of items in this task (e.g. 3 unread messages).
  final int count;

  /// Display priority (lower = shown first).
  final int priority;
}

// ── Individual counters ──────────────────────────────────────────────────────

/// Unread messages (client → salon) across all conversations of this salon.
final unreadMessagesCountProvider = StreamProvider<int>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value(0);
  return MessageService().getOwnerUnreadCount(salon.id);
});

/// Orders still waiting for owner confirmation (status == 'pending').
final pendingOrdersCountProvider = Provider<int>((ref) {
  final orders = ref.watch(ownerOrdersProvider).value ?? [];
  return orders.where((o) => o.status == 'pending').length;
});

/// Bad reviews (rating ≤ 2) posted in the last 7 days.
/// Server-side filtered by `createdAt` — rating is filtered client-side
/// because the dataset is bounded by the 7-day window.
final badReviewsCountProvider = StreamProvider<int>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value(0);
  final cutoff = DateTime.now().subtract(const Duration(days: 7));
  return _db
      .streamRecentReviews(salon.id, cutoff)
      .map((reviews) => reviews.where((r) => r.rating <= 2).length);
});

/// Google review rewards waiting for owner validation.
final pendingRewardsCountProvider = StreamProvider<int>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value(0);
  return _db
      .getPendingReviewRewards(salon.id)
      .map<int>((List<ReviewRewardModel> list) => list.length);
});

/// Inventory items at or below their low-stock threshold.
final lowStockCountProvider = Provider<int>((ref) {
  final inv = ref.watch(ownerInventoryProvider).value ?? [];
  return inv.where((i) => i.isLow).length;
});

/// Clients with upcoming appointment TODAY who are flagged for no-show risk.
///
/// Two-tier evaluation:
///   1. **Per-salon** (existing): cancellation rate ≥ 25% with min 2 past
///      appointments on THIS salon.
///   2. **Cross-salon** (new fallback): if no per-salon flag, query the
///      global `clientReputation/{uid}` doc and flag if rate ≥ 30% with
///      min 3 past appointments lifetime. The owner never sees the
///      per-salon breakdown — only the aggregate rate, for privacy.
///
/// Async because the cross-salon check needs a Firestore read per
/// upcoming-today client (bounded, typically < 20 reads per dashboard).
final noShowRiskClientsProvider =
    FutureProvider<List<NoShowRiskClient>>((ref) async {
  // 6-month window is enough to read a client's cancellation rate;
  // avoids the lifetime-history scan of `ownerAppointmentsProvider`.
  final appointments = ref.watch(ownerNoShowWindowAppointmentsProvider).value ?? [];
  if (appointments.isEmpty) return [];

  final now = DateTime.now();
  final todayStart = DateTime(now.year, now.month, now.day);
  final todayEnd = todayStart.add(const Duration(days: 1));

  // Upcoming appointments today (excluding walk-ins without clientId).
  // Skip RDVs that are fully paid or have a deposit — the upfront payment
  // already absorbs the no-show risk, so they shouldn't appear in this
  // list even if the client has a high cancellation history.
  final todayUpcoming = appointments.where((a) =>
      a.status == 'upcoming' &&
      !a.dateTime.isBefore(todayStart) &&
      a.dateTime.isBefore(todayEnd) &&
      a.clientId.isNotEmpty &&
      a.clientId != 'walk-in' &&
      a.paymentStatus != 'paid' &&
      a.paymentStatus != 'deposit_paid').toList();

  final results = <NoShowRiskClient>[];
  final seenClients = <String>{};
  for (final appt in todayUpcoming) {
    if (seenClients.contains(appt.clientId)) continue;
    seenClients.add(appt.clientId);

    // ── Tier 1: per-salon history ───────────────────────────────────
    final past = appointments.where((a) =>
        a.clientId == appt.clientId &&
        a.dateTime.isBefore(todayStart)).toList();
    if (past.length >= 2) {
      final cancelled = past.where((a) => a.status == 'cancelled').length;
      final rate = ((cancelled / past.length) * 100).round();
      if (rate >= 25) {
        results.add(NoShowRiskClient(
          clientId: appt.clientId,
          clientName: appt.clientName ?? 'Client',
          clientPhone: appt.clientPhone,
          totalPast: past.length,
          cancelledPast: cancelled,
          rate: rate,
          todayAppt: appt,
          isCrossSalon: false,
        ));
        continue; // already flagged, skip cross-salon check
      }
    }

    // ── Tier 2: cross-salon reputation ──────────────────────────────
    try {
      final repSnap = await FirebaseFirestore.instance
          .collection('clientReputation')
          .doc(appt.clientId)
          .get();
      if (!repSnap.exists) continue;
      final data = repSnap.data();
      if (data == null) continue;
      final totalPastLifetime = (data['totalPast'] as num?)?.toInt() ?? 0;
      final cancelledLifetime = (data['cancelledCount'] as num?)?.toInt() ?? 0;
      final rateLifetime = (data['cancellationRate'] as num?)?.toInt() ?? 0;
      if (totalPastLifetime < 3 || rateLifetime < 30) continue;
      results.add(NoShowRiskClient(
        clientId: appt.clientId,
        clientName: appt.clientName ?? 'Client',
        clientPhone: appt.clientPhone,
        totalPast: totalPastLifetime,
        cancelledPast: cancelledLifetime,
        rate: rateLifetime,
        todayAppt: appt,
        isCrossSalon: true,
      ));
    } catch (_) {
      // Best-effort: if rules block read or doc fetch fails,
      // don't flag — better than a false positive.
    }
  }

  results.sort((a, b) => b.rate.compareTo(a.rate));
  return results;
});

/// Count of high-risk clients with appointment today.
final noShowRiskCountProvider = Provider<int>((ref) {
  return ref.watch(noShowRiskClientsProvider).valueOrNull?.length ?? 0;
});

// ── Aggregator ───────────────────────────────────────────────────────────────

/// Combined list of non-empty tasks, ordered by priority.
final ownerTasksProvider = Provider<List<OwnerTask>>((ref) {
  final unread = ref.watch(unreadMessagesCountProvider).value ?? 0;
  final orders = ref.watch(pendingOrdersCountProvider);
  final noShowRisks = ref.watch(noShowRiskCountProvider);
  final badReviews = ref.watch(badReviewsCountProvider).value ?? 0;
  final rewards = ref.watch(pendingRewardsCountProvider).value ?? 0;
  final lowStock = ref.watch(lowStockCountProvider);

  final tasks = <OwnerTask>[
    if (unread > 0)
      OwnerTask(type: OwnerTaskType.messages, count: unread, priority: 1),
    if (orders > 0)
      OwnerTask(type: OwnerTaskType.pendingOrders, count: orders, priority: 2),
    if (noShowRisks > 0)
      OwnerTask(
          type: OwnerTaskType.noShowRisk, count: noShowRisks, priority: 3),
    if (badReviews > 0)
      OwnerTask(type: OwnerTaskType.badReviews, count: badReviews, priority: 4),
    if (rewards > 0)
      OwnerTask(type: OwnerTaskType.pendingRewards, count: rewards, priority: 5),
    if (lowStock > 0)
      OwnerTask(type: OwnerTaskType.lowStock, count: lowStock, priority: 6),
  ];

  tasks.sort((a, b) => a.priority.compareTo(b.priority));
  return tasks;
});
