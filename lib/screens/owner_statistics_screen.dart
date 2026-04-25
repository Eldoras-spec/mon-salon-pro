import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/order_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../widgets/member_avatar.dart';
import '../utils/currency_helper.dart';

class OwnerStatisticsScreen extends ConsumerWidget {
  const OwnerStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final appointmentsAsync = ref.watch(ownerStatisticsAppointmentsProvider);
    final ordersAsync = ref.watch(ownerOrdersProvider);
    final currency = ref.watch(ownerSalonProvider).value?.currency ?? 'MAD';

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          l?.tr('statistics_title') ?? 'Statistiques',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 20,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand950),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: appointmentsAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
        data: (appointments) {
          final orders = ordersAsync.valueOrNull ?? [];
          return _StatisticsBody(
              appointments: appointments, orders: orders, currency: currency);
        },
      ),
    );
  }
}

class _StatisticsBody extends ConsumerStatefulWidget {
  const _StatisticsBody({required this.appointments, required this.orders, required this.currency});
  final List<AppointmentModel> appointments;
  final List<OrderModel> orders;
  final String currency;

  @override
  ConsumerState<_StatisticsBody> createState() => _StatisticsBodyState();
}

class _StatisticsBodyState extends ConsumerState<_StatisticsBody> {
  // The appointments list is already server-filtered to the selected period
  // via [ownerStatisticsAppointmentsProvider]; no client-side filtering needed.
  List<AppointmentModel> get _filtered => widget.appointments;

  // Orders are still loaded in full — filter locally to match the current
  // statistics period (orders aren't yet paginated at the DB level).
  List<OrderModel> get _filteredOrders {
    final period = ref.watch(statisticsPeriodProvider);
    final r = resolveStatisticsRange(period);
    return widget.orders
        .where((o) =>
            !o.createdAt.isBefore(r.start) && o.createdAt.isBefore(r.end))
        .toList();
  }

  void _showListBottomSheet(
    BuildContext context, {
    required String title,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    final count = itemCount > 20 ? 20 : itemCount;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        minChildSize: 0.4,
        expand: false,
        builder: (ctx, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.secondary300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: count,
                itemBuilder: (_, i) => itemBuilder(i),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final items = _filtered;
    final completed = items.where((a) => a.status == 'completed').toList();
    final cancelled = items.where((a) => a.status == 'cancelled').toList();
    final upcoming = items.where((a) => a.status == 'upcoming').toList();
    final totalRevenue =
        completed.fold<double>(0, (s, a) => s + a.price);
    final avgPrice =
        completed.isNotEmpty ? totalRevenue / completed.length : 0.0;

    // Top services
    final serviceCounts = <String, int>{};
    final serviceRevenue = <String, double>{};
    for (final a in completed) {
      serviceCounts[a.serviceName] =
          (serviceCounts[a.serviceName] ?? 0) + 1;
      serviceRevenue[a.serviceName] =
          (serviceRevenue[a.serviceName] ?? 0) + a.price;
    }
    final topServices = serviceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Activity breakdown — granularity adapts to the selected period.
    // Week / month / 3 months → daily grid. 6 months / 1 year → monthly grid.
    final period = ref.watch(statisticsPeriodProvider);
    final now = DateTime.now();
    final bool isMonthly = period == StatisticsPeriod.last6Months ||
        period == StatisticsPeriod.lastYear;

    final int binCount;
    final List<DateTime> binStarts;
    if (isMonthly) {
      final monthCount = period == StatisticsPeriod.last6Months ? 6 : 12;
      binCount = monthCount;
      // Oldest month first → current month last. Start-of-month dates.
      binStarts = List.generate(monthCount,
          (i) => DateTime(now.year, now.month - (monthCount - 1 - i), 1));
    } else {
      final int dayCount = switch (period) {
        StatisticsPeriod.currentWeek => 7,
        StatisticsPeriod.currentMonth => 30,
        StatisticsPeriod.last3Months => 90,
        _ => 30,
      };
      binCount = dayCount;
      final start = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: dayCount - 1));
      binStarts = List.generate(dayCount,
          (i) => start.add(Duration(days: i)));
    }
    final dayCounts = List.filled(binCount, 0);
    final dayRevenues = List.filled(binCount, 0.0);
    final startDate = binStarts.first;

    for (final a in items) {
      int? bin;
      if (isMonthly) {
        // Match on (year, month).
        for (int i = 0; i < binStarts.length; i++) {
          if (a.dateTime.year == binStarts[i].year &&
              a.dateTime.month == binStarts[i].month) {
            bin = i;
            break;
          }
        }
      } else {
        final diff = a.dateTime
            .difference(DateTime(
                startDate.year, startDate.month, startDate.day))
            .inDays;
        if (diff >= 0 && diff < binCount) bin = diff;
      }
      if (bin != null) {
        dayCounts[bin]++;
        if (a.status == 'completed') dayRevenues[bin] += a.price;
      }
    }

    // Peak hours
    final hourCounts = List.filled(24, 0);
    for (final a in completed) {
      hourCounts[a.dateTime.hour]++;
    }
    final peakHour = hourCounts.indexOf(
        hourCounts.reduce((a, b) => a > b ? a : b));

    // Member performance
    final memberCounts = <String, int>{};
    final memberRevenue = <String, double>{};
    for (final a in completed) {
      final name = a.assignedMemberName ?? (l?.tr('statistics_unassigned') ?? 'Non assigné');
      memberCounts[name] = (memberCounts[name] ?? 0) + 1;
      memberRevenue[name] = (memberRevenue[name] ?? 0) + a.price;
    }
    final topMembers = memberCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // ── Client analytics ──
    final clientRevenue = <String, double>{};
    final clientVisits = <String, int>{};
    final clientNames = <String, String>{};
    final clientFirstDate = <String, DateTime>{};
    for (final a in completed) {
      final cid = a.clientId;
      clientRevenue[cid] = (clientRevenue[cid] ?? 0) + a.price;
      clientVisits[cid] = (clientVisits[cid] ?? 0) + 1;
      clientNames[cid] = a.clientName ?? '—';
      if (clientFirstDate[cid] == null ||
          a.dateTime.isBefore(clientFirstDate[cid]!)) {
        clientFirstDate[cid] = a.dateTime;
      }
    }
    final topClients = clientRevenue.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final recurringClients = clientVisits.entries
        .where((e) => e.value >= 3)
        .toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final thisMonthStart = DateTime(now.year, now.month, 1);
    final newClientsThisMonth = clientFirstDate.entries
        .where((e) => !e.value.isBefore(thisMonthStart))
        .toList();

    // ── Boutique analytics ──
    final filteredOrders = _filteredOrders;
    final completedOrders = filteredOrders
        .where((o) => o.status == 'delivered' || o.status == 'confirmed')
        .toList();
    final boutiqueRevenue =
        completedOrders.fold<double>(0, (s, o) => s + o.grandTotal);
    final productSales = <String, int>{};
    final productRevenue = <String, double>{};
    for (final o in completedOrders) {
      for (final item in o.items) {
        productSales[item.name] =
            (productSales[item.name] ?? 0) + item.quantity;
        productRevenue[item.name] =
            (productRevenue[item.name] ?? 0) + item.total;
      }
    }
    final topProducts = productSales.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Period selector (5 explicit ranges — server-filtered data)
          _StatisticsPeriodChips(
            selected: ref.watch(statisticsPeriodProvider),
            onSelect: (p) =>
                ref.read(statisticsPeriodProvider.notifier).state = p,
          ),

          const SizedBox(height: 20),

          // KPI cards
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_revenue') ?? 'Revenus',
                  value: CurrencyHelper.format(totalRevenue, widget.currency),
                  icon: Icons.payments_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFD1FAE5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_avg_price') ?? 'Panier moyen',
                  value: CurrencyHelper.format(avgPrice, widget.currency),
                  icon: Icons.shopping_bag_outlined,
                  iconColor: AppColors.brand600,
                  iconBg: const Color(0xFFF5F3FF),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_completed') ?? 'Terminés',
                  value: '${completed.length}',
                  icon: Icons.check_circle_outline,
                  iconColor: const Color(0xFF16A34A),
                  iconBg: const Color(0xFFDCFCE7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_cancelled') ?? 'Annulés',
                  value: '${cancelled.length}',
                  icon: Icons.cancel_outlined,
                  iconColor: const Color(0xFFDC2626),
                  iconBg: const Color(0xFFFEE2E2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_upcoming') ?? 'À venir',
                  value: '${upcoming.length}',
                  icon: Icons.event_outlined,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_peak_hour') ?? 'Heure de pointe',
                  value: completed.isNotEmpty ? '${peakHour}h' : '—',
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFEF3C7),
                ),
              ),
            ],
          ),

          const SizedBox(height: 28),

          // Activity chart
          _SectionHeader(title: l?.tr('statistics_activity') ?? 'Activité'),
          const SizedBox(height: 14),
          _ActivityChart(
            dayCounts: dayCounts,
            dayRevenues: dayRevenues,
            startDate: startDate,
            binStarts: binStarts,
            isWeek: period == StatisticsPeriod.currentWeek,
            isMonthly: isMonthly,
          ),

          const SizedBox(height: 28),

          // Top services
          _SectionHeader(
            title: l?.tr('statistics_popular_services') ?? 'Services populaires',
            onSeeMore: topServices.length > 5
                ? () => _showListBottomSheet(
                      context,
                      title: l?.tr('statistics_popular_services') ?? 'Services populaires',
                      itemCount: topServices.length,
                      itemBuilder: (i) => _ServiceRow(
                        name: topServices[i].key,
                        count: topServices[i].value,
                        revenue: serviceRevenue[topServices[i].key] ?? 0,
                        maxCount: topServices.first.value,
                        currency: widget.currency,
                      ),
                    )
                : null,
          ),
          const SizedBox(height: 14),
          if (topServices.isEmpty)
            _EmptySection(message: l?.tr('statistics_no_completed_service') ?? 'Aucun service terminé')
          else
            ...topServices.take(5).map((e) => _ServiceRow(
                  name: e.key,
                  count: e.value,
                  revenue: serviceRevenue[e.key] ?? 0,
                  maxCount: topServices.first.value,
                  currency: widget.currency,
                )),

          const SizedBox(height: 28),

          // Team performance
          if (topMembers.isNotEmpty) ...[
            _SectionHeader(
              title: l?.tr('statistics_team_performance') ?? 'Performance équipe',
              onSeeMore: topMembers.length > 5
                  ? () => _showListBottomSheet(
                        context,
                        title: l?.tr('statistics_team_performance') ?? 'Performance équipe',
                        itemCount: topMembers.length,
                        itemBuilder: (i) => _MemberRow(
                          name: topMembers[i].key,
                          count: topMembers[i].value,
                          revenue: memberRevenue[topMembers[i].key] ?? 0,
                          maxCount: topMembers.first.value,
                          currency: widget.currency,
                        ),
                      )
                  : null,
            ),
            const SizedBox(height: 14),
            ...topMembers.take(5).map((e) => _MemberRow(
                  name: e.key,
                  count: e.value,
                  revenue: memberRevenue[e.key] ?? 0,
                  maxCount: topMembers.first.value,
                  currency: widget.currency,
                )),
          ],

          // Top clients
          if (topClients.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHeader(
              title: l?.tr('statistics_top_clients') ?? 'Top clients',
              onSeeMore: topClients.length > 5
                  ? () => _showListBottomSheet(
                        context,
                        title: l?.tr('statistics_top_clients') ?? 'Top clients',
                        itemCount: topClients.length,
                        itemBuilder: (i) {
                          final cid = topClients[i].key;
                          return _ClientRow(
                            name: clientNames[cid] ?? '—',
                            visits: clientVisits[cid] ?? 0,
                            revenue: topClients[i].value,
                            currency: widget.currency,
                          );
                        },
                      )
                  : null,
            ),
            const SizedBox(height: 14),
            ...topClients.take(5).map((e) => _ClientRow(
                  name: clientNames[e.key] ?? '—',
                  visits: clientVisits[e.key] ?? 0,
                  revenue: e.value,
                  currency: widget.currency,
                )),
          ],

          // Recurring clients
          if (recurringClients.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHeader(
              title: l?.tr('statistics_recurring_clients') ?? 'Clients récurrents',
              onSeeMore: recurringClients.length > 5
                  ? () => _showListBottomSheet(
                        context,
                        title: l?.tr('statistics_recurring_clients') ?? 'Clients récurrents',
                        itemCount: recurringClients.length,
                        itemBuilder: (i) {
                          final cid = recurringClients[i].key;
                          return _ClientRow(
                            name: clientNames[cid] ?? '—',
                            visits: recurringClients[i].value,
                            revenue: clientRevenue[cid] ?? 0,
                            currency: widget.currency,
                          );
                        },
                      )
                  : null,
            ),
            const SizedBox(height: 14),
            ...recurringClients.take(5).map((e) => _ClientRow(
                  name: clientNames[e.key] ?? '—',
                  visits: e.value,
                  revenue: clientRevenue[e.key] ?? 0,
                  currency: widget.currency,
                )),
          ],

          // New clients this month
          const SizedBox(height: 28),
          _SectionHeader(title: l?.tr('statistics_new_clients_month') ?? 'Nouveaux clients ce mois'),
          const SizedBox(height: 14),
          _KpiCard(
            label: l?.tr('statistics_new_clients') ?? 'Nouveaux clients',
            value: '${newClientsThisMonth.length}',
            icon: Icons.person_add_outlined,
            iconColor: AppColors.brand600,
            iconBg: const Color(0xFFF5F3FF),
          ),

          // Cancellation rate
          if (items.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHeader(title: l?.tr('statistics_cancellation_rate') ?? 'Taux d\'annulation'),
            const SizedBox(height: 14),
            _CancellationRate(
              total: completed.length + cancelled.length,
              cancelled: cancelled.length,
            ),
          ],

          // ── Boutique stats ──
          const SizedBox(height: 28),
          _SectionHeader(title: l?.tr('statistics_boutique_sales') ?? 'Ventes boutique'),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_boutique_revenue') ?? 'CA Boutique',
                  value: CurrencyHelper.format(boutiqueRevenue, widget.currency),
                  icon: Icons.storefront_outlined,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFEF3C7),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_orders') ?? 'Commandes',
                  value: '${completedOrders.length}',
                  icon: Icons.shopping_cart_outlined,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFD1FAE5),
                ),
              ),
            ],
          ),

          // Top products
          if (topProducts.isNotEmpty) ...[
            const SizedBox(height: 28),
            _SectionHeader(
              title: l?.tr('statistics_top_products') ?? 'Top produits vendus',
              onSeeMore: topProducts.length > 5
                  ? () => _showListBottomSheet(
                        context,
                        title: l?.tr('statistics_top_products') ?? 'Top produits vendus',
                        itemCount: topProducts.length,
                        itemBuilder: (i) => _ProductRow(
                          name: topProducts[i].key,
                          quantity: topProducts[i].value,
                          revenue: productRevenue[topProducts[i].key] ?? 0,
                          maxQty: topProducts.first.value,
                          currency: widget.currency,
                        ),
                      )
                  : null,
            ),
            const SizedBox(height: 14),
            ...topProducts.take(5).map((e) => _ProductRow(
                  name: e.key,
                  quantity: e.value,
                  revenue: productRevenue[e.key] ?? 0,
                  maxQty: topProducts.first.value,
                  currency: widget.currency,
                )),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

class _StatisticsPeriodChips extends StatelessWidget {
  const _StatisticsPeriodChips({
    required this.selected,
    required this.onSelect,
  });
  final StatisticsPeriod selected;
  final ValueChanged<StatisticsPeriod> onSelect;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    String label(StatisticsPeriod p) => switch (p) {
          StatisticsPeriod.currentWeek =>
            l?.tr('statistics_period_current_week') ?? 'Cette semaine',
          StatisticsPeriod.currentMonth =>
            l?.tr('statistics_period_current_month') ?? 'Ce mois',
          StatisticsPeriod.last3Months =>
            l?.tr('statistics_period_3m') ?? '3 mois',
          StatisticsPeriod.last6Months =>
            l?.tr('statistics_period_6m') ?? '6 mois',
          StatisticsPeriod.lastYear =>
            l?.tr('statistics_period_1y') ?? '1 an',
        };

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: StatisticsPeriod.values.map((p) {
          final active = p == selected;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onSelect(p),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: active ? AppColors.brand50 : Colors.white,
                  border: Border.all(
                      color: active
                          ? AppColors.brand600
                          : AppColors.secondary200),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label(p),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? AppColors.brand700
                        : AppColors.secondary500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── KPI card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.iconBg,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final Color iconBg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.secondary500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Activity chart ───────────────────────────────────────────────────────────

class _ActivityChart extends StatelessWidget {
  const _ActivityChart({
    required this.dayCounts,
    required this.dayRevenues,
    required this.startDate,
    required this.isWeek,
    this.isMonthly = false,
    this.binStarts = const [],
  });
  final List<int> dayCounts;
  final List<double> dayRevenues;
  final DateTime startDate;
  final bool isWeek;
  // When true, each cell aggregates a full calendar month.
  final bool isMonthly;
  // Start date of each bin (used for monthly view labels/tooltips).
  final List<DateTime> binStarts;

  static const _shortDays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final maxCount = dayCounts.fold<int>(0, (a, b) => a > b ? a : b);
    final now = DateTime.now();
    final int todayIndex;
    if (isMonthly) {
      todayIndex = binStarts.indexWhere(
          (d) => d.year == now.year && d.month == now.month);
    } else {
      todayIndex = now
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays;
    }

    if (isWeek) {
      // Bar chart for weekly view
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(dayCounts.length, (i) {
              final ratio = maxCount > 0 ? dayCounts[i] / maxCount : 0.0;
              final isToday = i == todayIndex;
              final barHeight = 8.0 + (ratio * 100);
              final date = startDate.add(Duration(days: i));

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (dayCounts[i] > 0)
                        Text(
                          '${dayCounts[i]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? AppColors.brand700
                                : AppColors.secondary500,
                          ),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: barHeight,
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppColors.brand500
                              : (dayCounts[i] > 0
                                  ? AppColors.brand200
                                  : AppColors.secondary100),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _shortDays[date.weekday - 1],
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight:
                              isToday ? FontWeight.bold : FontWeight.w500,
                          color: isToday
                              ? AppColors.brand700
                              : AppColors.secondary400,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      );
    }

    // Compact dot chart for monthly view
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Heatmap-style grid. Monthly mode uses larger cells with month
          // abbreviations ("Jan", "Fév", …); daily mode keeps compact squares.
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(dayCounts.length, (i) {
              final ratio = maxCount > 0 ? dayCounts[i] / maxCount : 0.0;
              final date = isMonthly
                  ? binStarts[i]
                  : startDate.add(Duration(days: i));
              final isToday = i == todayIndex;
              final tooltipMsg = isMonthly
                  ? '${DateFormat('MMMM yyyy', 'fr_FR').format(date)}: ${dayCounts[i]} RDV'
                  : '${DateFormat('d MMM', 'fr_FR').format(date)}: ${dayCounts[i]} RDV';
              final cellText = isMonthly
                  ? DateFormat('MMM', 'fr_FR')
                      .format(date)
                      .replaceAll('.', '')
                  : '${date.day}';

              return Tooltip(
                message: tooltipMsg,
                child: Container(
                  width: isMonthly ? 52 : 28,
                  height: isMonthly ? 52 : 28,
                  decoration: BoxDecoration(
                    color: dayCounts[i] == 0
                        ? AppColors.secondary50
                        : AppColors.brand500.withValues(alpha: 0.2 + ratio * 0.8),
                    borderRadius: BorderRadius.circular(isMonthly ? 10 : 6),
                    border: isToday
                        ? Border.all(color: AppColors.brand600, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          cellText,
                          style: TextStyle(
                            fontSize: isMonthly ? 11 : 9,
                            fontWeight: isToday || isMonthly
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: dayCounts[i] > 0
                                ? Colors.white
                                : AppColors.secondary400,
                          ),
                        ),
                        if (isMonthly && dayCounts[i] > 0)
                          Text(
                            '${dayCounts[i]}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              const Text('0',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.secondary400)),
              const SizedBox(width: 12),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.brand200,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Peu',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.secondary400)),
              const SizedBox(width: 12),
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: AppColors.brand500,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 4),
              const Text('Beaucoup',
                  style:
                      TextStyle(fontSize: 10, color: AppColors.secondary400)),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Service row ──────────────────────────────────────────────────────────────

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.name,
    required this.count,
    required this.revenue,
    required this.maxCount,
    required this.currency,
  });
  final String name;
  final int count;
  final double revenue;
  final int maxCount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount > 0 ? count / maxCount : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.brand950,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$count',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.brand700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyHelper.format(revenue, currency),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondary500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.secondary100,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(AppColors.brand400),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Member row ───────────────────────────────────────────────────────────────

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.name,
    required this.count,
    required this.revenue,
    required this.maxCount,
    required this.currency,
  });
  final String name;
  final int count;
  final double revenue;
  final int maxCount;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ratio = maxCount > 0 ? count / maxCount : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          MemberAvatar(
            name: name,
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 5,
                    backgroundColor: AppColors.secondary100,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        AppColors.brand400),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count RDV',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.brand700,
                ),
              ),
              Text(
                CurrencyHelper.format(revenue, currency),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.secondary400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Client row ───────────────────────────────────────────────────────────────

class _ClientRow extends StatelessWidget {
  const _ClientRow({
    required this.name,
    required this.visits,
    required this.revenue,
    required this.currency,
  });
  final String name;
  final int visits;
  final double revenue;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          MemberAvatar(
            name: name,
            radius: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.brand950,
                  ),
                ),
                Text(
                  '$visits visite${visits > 1 ? 's' : ''}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary400,
                  ),
                ),
              ],
            ),
          ),
          Text(
            CurrencyHelper.format(revenue, currency),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.brand700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Product row ──────────────────────────────────────────────────────────────

class _ProductRow extends StatelessWidget {
  const _ProductRow({
    required this.name,
    required this.quantity,
    required this.revenue,
    required this.maxQty,
    required this.currency,
  });
  final String name;
  final int quantity;
  final double revenue;
  final int maxQty;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final ratio = maxQty > 0 ? quantity / maxQty : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: AppColors.brand950,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '$quantity vendus',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.brand700,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                CurrencyHelper.format(revenue, currency),
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.secondary500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: AppColors.secondary100,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFFD97706)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Cancellation rate ────────────────────────────────────────────────────────

class _CancellationRate extends StatelessWidget {
  const _CancellationRate({required this.total, required this.cancelled});
  final int total;
  final int cancelled;

  @override
  Widget build(BuildContext context) {
    final rate = total > 0 ? (cancelled / total * 100) : 0.0;
    final isLow = rate < 15;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular indicator
          SizedBox(
            width: 56,
            height: 56,
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: rate / 100,
                  strokeWidth: 6,
                  backgroundColor: AppColors.secondary100,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isLow ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
                  ),
                ),
                Center(
                  child: Text(
                    '${rate.toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isLow
                          ? const Color(0xFF16A34A)
                          : const Color(0xFFDC2626),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isLow
                      ? (AppLocalizations.of(context)?.tr('statistics_excellent') ?? 'Excellent !')
                      : (AppLocalizations.of(context)?.tr('statistics_watch') ?? 'À surveiller'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isLow
                        ? const Color(0xFF16A34A)
                        : const Color(0xFFDC2626),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (AppLocalizations.of(context)?.tr('statistics_cancellation_detail') ?? '{cancelled} annulation(s) sur {total} rendez-vous')
                      .replaceAll('{cancelled}', '$cancelled')
                      .replaceAll('{total}', '$total'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeMore});
  final String title;
  final VoidCallback? onSeeMore;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
        ),
        if (onSeeMore != null)
          GestureDetector(
            onTap: onSeeMore,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  AppLocalizations.of(context)?.tr('common_see_more') ?? 'Voir tout',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand600,
                  ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_forward_ios,
                    size: 11, color: AppColors.brand600),
              ],
            ),
          ),
      ],
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          color: AppColors.secondary400,
        ),
      ),
    );
  }
}
