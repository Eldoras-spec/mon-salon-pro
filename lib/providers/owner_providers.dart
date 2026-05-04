import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/salon_model.dart';
import '../models/appointment_model.dart';
import '../models/inventory_model.dart';
import '../models/promotion_model.dart';
import '../models/team_member_model.dart';
import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/client_summary_model.dart';
import '../services/database_service.dart';
import 'auth_providers.dart';

final _db = DatabaseService();

/// Resolves the salonId of the currently-logged-in principal:
///  - Owner (auth as the salon owner): uid == salonId
///  - Employee (auth via login code): salonId comes from their custom claim
///  - Otherwise: null (logged out)
final currentSalonIdProvider = Provider<String?>((ref) {
  final employee = ref.watch(employeeSessionProvider).value;
  if (employee != null) return employee.salonId;
  final user = ref.watch(authStateProvider).value;
  return user?.uid;
});

/// Live stream of the owner's salon document.
final ownerSalonProvider = StreamProvider<SalonModel?>((ref) {
  final salonId = ref.watch(currentSalonIdProvider);
  if (salonId == null) return Stream.value(null);
  return _db.getOwnerSalon(salonId);
});

/// Live stream of all appointments booked at the owner's salon.
/// Returns an empty list until the salon document is loaded.
///
/// ⚠️ This provider is capped at 100 docs (server-side `.limit(100)`)
/// without ordering, so for big salons it returns an arbitrary 100
/// appointments. Prefer the bounded providers below for new code:
///   - [ownerHomeAppointmentsProvider] — last 7d + next 7d (home dashboard)
///   - [ownerNoShowWindowAppointmentsProvider] — last 6 months (no-show risk)
///   - [ownerAppointmentsRangeProvider] — period-selector driven (RDV list)
final ownerAppointmentsProvider = StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getSalonAppointments(salon.id);
});

/// Live stream of appointments around "now" (last 7 days + next 7 days).
/// This is the cheap window the home dashboard needs: today's RDV + current
/// week stats + a recent-5 fallback. Uses a server-side `dateTime` filter
/// so reads scale with current activity, not lifetime salon history.
final ownerHomeAppointmentsProvider =
    StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day - 7);
  final end = DateTime(now.year, now.month, now.day + 8);
  return _db.streamSalonAppointmentsForRange(salon.id, start, end);
});

/// Live stream of the last 6 months + next 7 days of appointments.
/// Used by:
///   - `noShowRiskClientsProvider` (today's upcoming + per-salon history)
///   - `agendaRiskClientsProvider` (next 7 days upcoming + history for the
///     agenda risk badges)
///
/// Cancellation patterns are visible inside 6 months for most clients,
/// so this trades a bit of accuracy on long-time clients for bounded
/// reads (no full-history scan). The +7d forward window costs ~3% extra
/// reads vs today-only and is negligible.
final ownerNoShowWindowAppointmentsProvider =
    StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 6, now.day);
  final end = DateTime(now.year, now.month, now.day + 8);
  return _db.streamSalonAppointmentsForRange(salon.id, start, end);
});

/// Live stream of inventory items for the owner's salon.
final ownerInventoryProvider = StreamProvider<List<InventoryModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getInventory(salon.id);
});

/// Live stream of all promotions for the owner's salon.
final ownerPromotionsProvider = StreamProvider<List<PromotionModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getPromotions(salon.id);
});

/// Live stream of all team members for the owner's salon.
final ownerTeamProvider = StreamProvider<List<TeamMemberModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getTeamMembers(salon.id);
});

/// Live stream of Before/After items for the owner's salon.
final ownerBeforeAfterProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getBeforeAfterStream(salon.id);
});

/// Live stream of all products for the owner's salon.
final ownerProductsProvider = StreamProvider<List<ProductModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getProducts(salon.id);
});

/// Live stream of all orders for the owner's salon.
final ownerOrdersProvider = StreamProvider<List<OrderModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getSalonOrders(salon.id);
});

/// Live stream of the owner salon's revenue for the CURRENT calendar month.
/// Server-side filtered — no client-side limit, scales to any salon size.
final ownerCurrentMonthRevenueProvider = StreamProvider<double>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value(0.0);
  final now = DateTime.now();
  return _db.streamMonthlyRevenue(salon.id, now.year, now.month);
});

/// Live stream of the number of completed appointments during the current
/// calendar month. Same index as [ownerCurrentMonthRevenueProvider].
final ownerCurrentMonthCompletedCountProvider = StreamProvider<int>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value(0);
  final now = DateTime.now();
  return _db.streamMonthlyCompletedCount(salon.id, now.year, now.month);
});

/// Rolling window for the appointments list view.
enum AppointmentsPeriod { last3Months, last6Months, lastYear }

/// Selected period for the appointments list (shared between owner and member views).
final appointmentsPeriodProvider =
    StateProvider<AppointmentsPeriod>((_) => AppointmentsPeriod.last3Months);

/// Live stream of all appointments within the selected period.
/// Replaces [ownerAppointmentsProvider] for the RDV list + member dashboard —
/// no hard limit, server-side filtered by dateTime.
final ownerAppointmentsRangeProvider =
    StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final period = ref.watch(appointmentsPeriodProvider);

  final now = DateTime.now();
  final months = switch (period) {
    AppointmentsPeriod.last3Months => 3,
    AppointmentsPeriod.last6Months => 6,
    AppointmentsPeriod.lastYear => 12,
  };
  final start = DateTime(now.year, now.month - months, 1);
  // End = far future so upcoming bookings stay visible regardless of period.
  final end = DateTime(now.year + 5);

  return _db.streamSalonAppointmentsForRange(salon.id, start, end);
});

/// Period selector for the statistics screen.
/// Five explicit ranges, each resolving to a precise (start, end) pair.
enum StatisticsPeriod {
  currentWeek,
  currentMonth,
  last3Months,
  last6Months,
  lastYear,
}

/// Selected period for the statistics screen.
final statisticsPeriodProvider =
    StateProvider<StatisticsPeriod>((_) => StatisticsPeriod.currentMonth);

/// Resolves a [StatisticsPeriod] into a concrete (start, end) date range.
/// `end` is always "now + 1 day" to include today's appointments.
({DateTime start, DateTime end}) resolveStatisticsRange(StatisticsPeriod p) {
  final now = DateTime.now();
  final end = DateTime(now.year, now.month, now.day)
      .add(const Duration(days: 1));
  return switch (p) {
    StatisticsPeriod.currentWeek => (
        start: DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1)),
        end: end,
      ),
    StatisticsPeriod.currentMonth => (
        start: DateTime(now.year, now.month, 1),
        end: end,
      ),
    StatisticsPeriod.last3Months => (
        start: DateTime(now.year, now.month - 3, 1),
        end: end,
      ),
    StatisticsPeriod.last6Months => (
        start: DateTime(now.year, now.month - 6, 1),
        end: end,
      ),
    StatisticsPeriod.lastYear => (
        start: DateTime(now.year - 1, now.month, 1),
        end: end,
      ),
  };
}

/// Live stream of appointments for the statistics screen.
/// Server-side filtered by [statisticsPeriodProvider] — no limit.
final ownerStatisticsAppointmentsProvider =
    StreamProvider<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final period = ref.watch(statisticsPeriodProvider);
  final r = resolveStatisticsRange(period);
  return _db.streamSalonAppointmentsForRange(salon.id, r.start, r.end);
});

/// Period selector for the "Clients" screen — controls how far back the
/// ledger stream is filtered on `lastVisit`. Default is 6 months so that
/// the screen stays responsive; the owner opts into the full history.
enum ClientsPeriod { last6Months, lastYear, all }

final clientsPeriodProvider =
    StateProvider<ClientsPeriod>((_) => ClientsPeriod.last6Months);

/// Live stream of the `clientSummaries` ledger for the owner's salon,
/// filtered by the selected period. Nothing is recomputed client-side.
final ownerClientSummariesProvider =
    StreamProvider<List<ClientSummaryModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final period = ref.watch(clientsPeriodProvider);
  final now = DateTime.now();
  DateTime? since;
  switch (period) {
    case ClientsPeriod.last6Months:
      since = DateTime(now.year, now.month - 6, 1);
      break;
    case ClientsPeriod.lastYear:
      since = DateTime(now.year - 1, now.month, 1);
      break;
    case ClientsPeriod.all:
      since = null;
      break;
  }
  return _db.streamClientSummaries(salon.id, since: since);
});
