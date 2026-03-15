import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/order_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';

class OwnerStatisticsScreen extends ConsumerWidget {
  const OwnerStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final appointmentsAsync = ref.watch(ownerAppointmentsProvider);
    final ordersAsync = ref.watch(ownerOrdersProvider);

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
              appointments: appointments, orders: orders);
        },
      ),
    );
  }
}

class _StatisticsBody extends StatefulWidget {
  const _StatisticsBody({required this.appointments, required this.orders});
  final List<AppointmentModel> appointments;
  final List<OrderModel> orders;

  @override
  State<_StatisticsBody> createState() => _StatisticsBodyState();
}

class _StatisticsBodyState extends State<_StatisticsBody> {
  int _selectedPeriod = 0; // 0=week, 1=month, 2=all

  List<String> _periodLabels(AppLocalizations? l) => [
    l?.tr('statistics_period_week') ?? 'Semaine',
    l?.tr('statistics_period_month') ?? 'Mois',
    l?.tr('statistics_period_all') ?? 'Tout',
  ];

  List<AppointmentModel> get _filtered {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0: // week
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
        return widget.appointments
            .where((a) => !a.dateTime.isBefore(start))
            .toList();
      case 1: // month
        final start = DateTime(now.year, now.month, 1);
        return widget.appointments
            .where((a) => !a.dateTime.isBefore(start))
            .toList();
      default:
        return widget.appointments;
    }
  }

  List<OrderModel> get _filteredOrders {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 0:
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
        return widget.orders
            .where((o) => !o.createdAt.isBefore(start))
            .toList();
      case 1:
        final start = DateTime(now.year, now.month, 1);
        return widget.orders
            .where((o) => !o.createdAt.isBefore(start))
            .toList();
      default:
        return widget.orders;
    }
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

    // Daily breakdown for chart
    final now = DateTime.now();
    final int dayCount = _selectedPeriod == 0 ? 7 : (_selectedPeriod == 1 ? 30 : 30);
    final dayCounts = List.filled(dayCount, 0);
    final dayRevenues = List.filled(dayCount, 0.0);
    final startDate = DateTime(now.year, now.month, now.day)
        .subtract(Duration(days: dayCount - 1));

    for (final a in items) {
      final diff = a.dateTime
          .difference(DateTime(startDate.year, startDate.month, startDate.day))
          .inDays;
      if (diff >= 0 && diff < dayCount) {
        dayCounts[diff]++;
        if (a.status == 'completed') dayRevenues[diff] += a.price;
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
          // Period selector
          _PeriodSelector(
            selected: _selectedPeriod,
            labels: _periodLabels(l),
            onSelect: (i) => setState(() => _selectedPeriod = i),
          ),

          const SizedBox(height: 20),

          // KPI cards
          Row(
            children: [
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_revenue') ?? 'Revenus',
                  value: '${totalRevenue.toStringAsFixed(0)} MAD',
                  icon: Icons.payments_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFD1FAE5),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _KpiCard(
                  label: l?.tr('statistics_avg_price') ?? 'Panier moyen',
                  value: '${avgPrice.toStringAsFixed(0)} MAD',
                  icon: Icons.shopping_bag_outlined,
                  iconColor: const Color(0xFF7C3AED),
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
            isWeek: _selectedPeriod == 0,
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
            iconColor: const Color(0xFF7C3AED),
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
                  value: '${boutiqueRevenue.toStringAsFixed(0)} MAD',
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
                )),
          ],

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

class _PeriodSelector extends StatelessWidget {
  const _PeriodSelector({
    required this.selected,
    required this.labels,
    required this.onSelect,
  });
  final int selected;
  final List<String> labels;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.secondary100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: active
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  labels[i],
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: active ? FontWeight.bold : FontWeight.w500,
                    color: active ? AppColors.brand950 : AppColors.secondary500,
                  ),
                ),
              ),
            ),
          );
        }),
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
  });
  final List<int> dayCounts;
  final List<double> dayRevenues;
  final DateTime startDate;
  final bool isWeek;

  static const _shortDays = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final maxCount = dayCounts.fold<int>(0, (a, b) => a > b ? a : b);
    final todayIndex = DateTime.now()
        .difference(DateTime(startDate.year, startDate.month, startDate.day))
        .inDays;

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
          // Heatmap-style grid
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: List.generate(dayCounts.length, (i) {
              final ratio = maxCount > 0 ? dayCounts[i] / maxCount : 0.0;
              final date = startDate.add(Duration(days: i));
              final isToday = i == todayIndex;

              return Tooltip(
                message:
                    '${DateFormat('d MMM', 'fr_FR').format(date)}: ${dayCounts[i]} RDV',
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dayCounts[i] == 0
                        ? AppColors.secondary50
                        : AppColors.brand500.withValues(alpha: 0.2 + ratio * 0.8),
                    borderRadius: BorderRadius.circular(6),
                    border: isToday
                        ? Border.all(color: AppColors.brand600, width: 2)
                        : null,
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight:
                            isToday ? FontWeight.bold : FontWeight.w500,
                        color: dayCounts[i] > 0
                            ? Colors.white
                            : AppColors.secondary400,
                      ),
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
  });
  final String name;
  final int count;
  final double revenue;
  final int maxCount;

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
                '${revenue.toStringAsFixed(0)} MAD',
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
  });
  final String name;
  final int count;
  final double revenue;
  final int maxCount;

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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.brand600,
                ),
              ),
            ),
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
                '${revenue.toStringAsFixed(0)} MAD',
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
  });
  final String name;
  final int visits;
  final double revenue;

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
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.brand600,
                ),
              ),
            ),
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
            '${revenue.toStringAsFixed(0)} MAD',
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
  });
  final String name;
  final int quantity;
  final double revenue;
  final int maxQty;

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
                '${revenue.toStringAsFixed(0)} MAD',
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
                  isLow ? 'Excellent !' : 'À surveiller',
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
                  '$cancelled annulation${cancelled > 1 ? 's' : ''} sur $total rendez-vous',
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
