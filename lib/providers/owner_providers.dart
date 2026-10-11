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
import '../utils/timezone_helper.dart';
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
final ownerSalonProvider = StreamProvider.autoDispose<SalonModel?>((ref) {
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
final ownerAppointmentsProvider = StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getSalonAppointments(salon.id);
});

/// Live stream of appointments around "now" (last 7 days + next 7 days).
/// This is the cheap window the home dashboard needs: today's RDV + current
/// week stats + a recent-5 fallback. Uses a server-side `dateTime` filter
/// so reads scale with current activity, not lifetime salon history.
final ownerHomeAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  // Wall-clock-UTC bounds in the salon TZ (appointments are stored that
  // way); DateTime(...) local shifted the window by the device offset.
  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  final start = DateTime.utc(now.year, now.month, now.day - 7);
  final end = DateTime.utc(now.year, now.month, now.day + 8);
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
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  final start = DateTime.utc(now.year, now.month - 6, now.day);
  final end = DateTime.utc(now.year, now.month, now.day + 8);
  return _db.streamSalonAppointmentsForRange(salon.id, start, end);
});

/// Live stream of appointments for the current calendar month (salon TZ).
/// Used by the home revenue-by-employee widget when the Month filter is
/// active. Today + Week filters reuse [ownerHomeAppointmentsProvider]
/// (±7d) which already covers their range, so this provider only kicks
/// in when the owner taps "Mois".
///
/// Bounds: 1st of the current month at 00:00 → 1st of next month at 00:00.
/// Wall-clock comparisons elsewhere (appointment.dateTime is wall-clock-
/// UTC) match these bounds without TZ conversion.
final ownerCurrentMonthAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  final start = DateTime.utc(now.year, now.month, 1);
  final end = DateTime.utc(now.year, now.month + 1, 1);
  return _db.streamSalonAppointmentsForRange(salon.id, start, end);
});

/// Live stream of inventory items for the owner's salon.
///
/// Owner-only: the `inventory where salonId` rule denies employees,
/// so we short-circuit before opening a doomed Firestore listener.
final ownerInventoryProvider = StreamProvider.autoDispose<List<InventoryModel>>((ref) {
  if (ref.watch(employeeSessionProvider).value != null) return Stream.value([]);
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getInventory(salon.id);
});

/// Live stream of all promotions for the owner's salon.
final ownerPromotionsProvider = StreamProvider.autoDispose<List<PromotionModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getPromotions(salon.id);
});

/// Live stream of all team members for the owner's salon.
final ownerTeamProvider = StreamProvider.autoDispose<List<TeamMemberModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getTeamMembers(salon.id);
});

/// Live stream of Before/After items for the owner's salon.
final ownerBeforeAfterProvider =
    StreamProvider.autoDispose<List<Map<String, dynamic>>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getBeforeAfterStream(salon.id);
});

/// Live stream of all products for the owner's salon.
final ownerProductsProvider = StreamProvider.autoDispose<List<ProductModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  return _db.getProducts(salon.id);
});

/// Filter cutoff for the owner's orders stream. `null` = no cutoff (all
/// orders). The Boutique → Commandes tab drives this via its dropdown so
/// the underlying Firestore listener only loads the visible window.
final ownerOrdersCutoffProvider = StateProvider<DateTime?>((ref) {
  // Default = last 14 days. Matches the dropdown's default selection.
  return DateTime.now().subtract(const Duration(days: 14));
});

/// Live stream of orders for the owner's salon, narrowed to
/// `createdAt >= ownerOrdersCutoffProvider`.
///
/// Owner-only: the `orders where salonId` rule denies employees.
final ownerOrdersProvider = StreamProvider.autoDispose<List<OrderModel>>((ref) {
  if (ref.watch(employeeSessionProvider).value != null) return Stream.value([]);
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final since = ref.watch(ownerOrdersCutoffProvider);
  return _db.getSalonOrders(salon.id, since: since);
});

/// Owner salon's revenue for the CURRENT calendar month.
/// Implemented as a Firestore aggregation query (sum on the server) so
/// the dashboard widget is 1 read instead of N (where N = completed RDV
/// of the month).
///
/// Refresh strategy: invalidated by appointment status mutations
/// (createAppointment / updateAppointmentStatus) and explicit refresh.
final ownerCurrentMonthRevenueProvider =
    FutureProvider.autoDispose<double>((ref) async {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return 0.0;
  // Re-aggregate whenever a nearby appointment changes (e.g. the CF
  // auto-completing past RDV) — 1 read per change instead of a stale total.
  ref.watch(ownerHomeAppointmentsProvider);
  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  return _db.getMonthlyRevenue(salon.id, now.year, now.month);
});

/// Number of completed appointments during the current calendar month.
/// Same aggregation pattern as [ownerCurrentMonthRevenueProvider].
final ownerCurrentMonthCompletedCountProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return 0;
  ref.watch(ownerHomeAppointmentsProvider);
  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  return _db.getMonthlyCompletedCount(salon.id, now.year, now.month);
});

/// Rolling window for the appointments list view.
/// `lastWeek` is the default — last 7 days of history is enough for daily
/// owner decisions, and the future side of the window is always unbounded
/// so all upcoming RDV stay visible regardless of period.
enum AppointmentsPeriod { lastWeek, last3Months, last6Months, lastYear }

/// Selected period for the appointments list (shared between owner and member views).
final appointmentsPeriodProvider =
    StateProvider<AppointmentsPeriod>((_) => AppointmentsPeriod.lastWeek);

/// Live stream of all appointments within the selected period.
/// Replaces [ownerAppointmentsProvider] for the RDV list + member dashboard —
/// no hard limit, server-side filtered by dateTime.
final ownerAppointmentsRangeProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final period = ref.watch(appointmentsPeriodProvider);

  final now = TimezoneHelper.salonWallClockNow(salon.timezone);
  final start = switch (period) {
    AppointmentsPeriod.lastWeek =>
      DateTime.utc(now.year, now.month, now.day - 7),
    AppointmentsPeriod.last3Months => DateTime.utc(now.year, now.month - 3, 1),
    AppointmentsPeriod.last6Months => DateTime.utc(now.year, now.month - 6, 1),
    AppointmentsPeriod.lastYear => DateTime.utc(now.year - 1, now.month, 1),
  };
  // End = far future so upcoming bookings stay visible regardless of period.
  final end = DateTime.utc(now.year + 5);

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
({DateTime start, DateTime end}) resolveStatisticsRange(StatisticsPeriod p,
    [String? salonTimezone]) {
  // Wall-clock-UTC bounds (salon TZ), matching appointment.dateTime.
  final now = TimezoneHelper.salonWallClockNow(salonTimezone);
  final end = DateTime.utc(now.year, now.month, now.day)
      .add(const Duration(days: 1));
  return switch (p) {
    StatisticsPeriod.currentWeek => (
        start: DateTime.utc(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1)),
        end: end,
      ),
    StatisticsPeriod.currentMonth => (
        start: DateTime.utc(now.year, now.month, 1),
        end: end,
      ),
    // Ranges match the activity chart exactly (90 daily bins, 6 / 12
    // monthly bins incl. the current month) — they used to load up to a
    // month more than the chart showed.
    StatisticsPeriod.last3Months => (
        start: DateTime.utc(now.year, now.month, now.day)
            .subtract(const Duration(days: 89)),
        end: end,
      ),
    StatisticsPeriod.last6Months => (
        start: DateTime.utc(now.year, now.month - 5, 1),
        end: end,
      ),
    StatisticsPeriod.lastYear => (
        start: DateTime.utc(now.year, now.month - 11, 1),
        end: end,
      ),
  };
}

/// Live stream of appointments for the statistics screen.
/// Server-side filtered by [statisticsPeriodProvider] — no limit.
final ownerStatisticsAppointmentsProvider =
    StreamProvider.autoDispose<List<AppointmentModel>>((ref) {
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final period = ref.watch(statisticsPeriodProvider);
  final r = resolveStatisticsRange(period, salon.timezone);
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
    StreamProvider.autoDispose<List<ClientSummaryModel>>((ref) {
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

/// Unread in-app notifications of the signed-in user (header badge).
/// A provider instead of a StreamBuilder created inline in build(), which
/// re-subscribed on every rebuild and flickered the badge.
final unreadNotificationsCountProvider =
    StreamProvider.autoDispose<int>((ref) {
  final uid = ref.watch(authStateProvider).value?.uid;
  if (uid == null || uid.isEmpty) return Stream.value(0);
  return _db.getUnreadNotificationCount(uid);
});

/// Orders for the statistics screen, server-filtered on the selected
/// period. The stats used `ownerOrdersProvider`, which is narrowed to the
/// Orders tab's cutoff (14 days by default): shop revenue / top products
/// were wrong for any longer period.
final ownerStatisticsOrdersProvider =
    StreamProvider.autoDispose<List<OrderModel>>((ref) {
  if (ref.watch(employeeSessionProvider).value != null) return Stream.value([]);
  final salon = ref.watch(ownerSalonProvider).value;
  if (salon == null) return Stream.value([]);
  final r = resolveStatisticsRange(
      ref.watch(statisticsPeriodProvider), salon.timezone);
  return _db.getSalonOrders(salon.id, since: r.start);
});
