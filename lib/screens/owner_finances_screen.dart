import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/charge_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';

final _db = DatabaseService();

class OwnerFinancesScreen extends ConsumerStatefulWidget {
  const OwnerFinancesScreen({super.key});

  @override
  ConsumerState<OwnerFinancesScreen> createState() =>
      _OwnerFinancesScreenState();
}

class _OwnerFinancesScreenState extends ConsumerState<OwnerFinancesScreen> {
  static const _monthKeys = [
    'finances_month_january', 'finances_month_february', 'finances_month_march',
    'finances_month_april', 'finances_month_may', 'finances_month_june',
    'finances_month_july', 'finances_month_august', 'finances_month_september',
    'finances_month_october', 'finances_month_november', 'finances_month_december',
  ];

  static const _monthFallbacks = [
    'Janvier', 'Février', 'Mars', 'Avril', 'Mai', 'Juin',
    'Juillet', 'Août', 'Septembre', 'Octobre', 'Novembre', 'Décembre',
  ];

  late int _selectedMonth;
  late int _selectedYear;
  double _revenue = 0;
  bool _loadingRevenue = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = now.month;
    _selectedYear = now.year;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _fetchRevenue();
  }

  List<String> _getLocalizedMonths(AppLocalizations? l) {
    return List.generate(12, (i) =>
      l?.tr(_monthKeys[i]) ?? _monthFallbacks[i],
    );
  }

  Future<void> _fetchRevenue() async {
    final salonId = ref.read(ownerSalonProvider).value?.id;
    if (salonId == null) return;
    setState(() => _loadingRevenue = true);
    try {
      final rev = await _db.getMonthlyRevenue(
          salonId, _selectedYear, _selectedMonth);
      if (mounted) setState(() => _revenue = rev);
    } finally {
      if (mounted) setState(() => _loadingRevenue = false);
    }
  }

  void _prevMonth() {
    setState(() {
      if (_selectedMonth == 1) {
        _selectedMonth = 12;
        _selectedYear--;
      } else {
        _selectedMonth--;
      }
    });
    _fetchRevenue();
  }

  void _nextMonth() {
    setState(() {
      if (_selectedMonth == 12) {
        _selectedMonth = 1;
        _selectedYear++;
      } else {
        _selectedMonth++;
      }
    });
    _fetchRevenue();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);
    final salonId = salonAsync.value?.id;
    final months = _getLocalizedMonths(l);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.brand950, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              l?.tr('finances_title') ?? 'Finances',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.add_rounded,
                    color: AppColors.brand600, size: 24),
                onPressed: salonId == null
                    ? null
                    : () => _showAddChargeSheet(context, salonId),
                tooltip: l?.tr('finances_add_charge') ?? 'Ajouter une charge',
              ),
              const SizedBox(width: 8),
            ],
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Month selector
                  _MonthSelector(
                    months: months,
                    selectedMonth: _selectedMonth,
                    selectedYear: _selectedYear,
                    onPrev: _prevMonth,
                    onNext: _nextMonth,
                  ),
                  const SizedBox(height: 20),

                  // Summary cards
                  if (salonId != null)
                    StreamBuilder<List<ChargeModel>>(
                      stream: _db.getCharges(
                          salonId, _selectedMonth, _selectedYear),
                      builder: (context, snap) {
                        final charges = snap.data ?? [];
                        final totalCharges = charges.fold<double>(
                            0, (acc, c) => acc + c.amount);
                        final profit = _revenue - totalCharges;

                        return Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: _FinanceCard(
                                    label: l?.tr('finances_revenue') ?? 'Revenus',
                                    value: _loadingRevenue
                                        ? '...'
                                        : CurrencyHelper.format(_revenue, salonAsync.value?.currency ?? 'MAD'),
                                    icon: Icons.trending_up_rounded,
                                    iconBg: const Color(0xFFF0FDF4),
                                    iconColor: const Color(0xFF16A34A),
                                    valueColor: const Color(0xFF16A34A),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _FinanceCard(
                                    label: l?.tr('finances_charges') ?? 'Charges',
                                    value:
                                        CurrencyHelper.format(totalCharges, salonAsync.value?.currency ?? 'MAD'),
                                    icon: Icons.trending_down_rounded,
                                    iconBg: const Color(0xFFFEE2E2),
                                    iconColor: const Color(0xFFDC2626),
                                    valueColor: const Color(0xFFDC2626),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: [
                                    AppColors.brand700,
                                    AppColors.brand900
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                      Icons
                                          .account_balance_wallet_outlined,
                                      color: Colors.white70,
                                      size: 20),
                                  const SizedBox(width: 10),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(l?.tr('finances_net_profit') ?? 'Bénéfice net',
                                          style: const TextStyle(
                                              fontSize: 12,
                                              color: Colors.white70)),
                                      Text(
                                        CurrencyHelper.format(profit, salonAsync.value?.currency ?? 'MAD'),
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),

                            // Charges list
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  l?.tr('finances_monthly_charges') ?? 'Charges du mois',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.brand950,
                                  ),
                                ),
                                if (charges.isNotEmpty)
                                  TextButton.icon(
                                    onPressed: () => _showAddChargeSheet(
                                        context, salonId),
                                    icon: const Icon(Icons.add_rounded,
                                        size: 16),
                                    label: Text(l?.tr('finances_add') ?? 'Ajouter'),
                                    style: TextButton.styleFrom(
                                        foregroundColor:
                                            AppColors.brand600),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            if (charges.isEmpty)
                              _EmptyCharges(
                                  onAdd: () => _showAddChargeSheet(
                                      context, salonId))
                            else
                              ...charges.map((c) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 10),
                                    child: _ChargeTile(
                                      charge: c,
                                      onDelete: () =>
                                          _db.deleteCharge(c.id),
                                      currency: salonAsync.value?.currency ?? 'MAD',
                                    ),
                                  )),
                            const SizedBox(height: 24),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showAddChargeSheet(BuildContext context, String salonId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddChargeSheet(
        salonId: salonId,
        month: _selectedMonth,
        year: _selectedYear,
        currency: ref.read(ownerSalonProvider).value?.currency ?? 'MAD',
      ),
    );
  }
}

// ── Add Charge Sheet ────────────────────────────────────────────────────────

class _AddChargeSheet extends StatefulWidget {
  const _AddChargeSheet({
    required this.salonId,
    required this.month,
    required this.year,
    this.currency = 'MAD',
  });
  final String salonId;
  final int month;
  final int year;
  final String currency;

  @override
  State<_AddChargeSheet> createState() => _AddChargeSheetState();
}

class _AddChargeSheetState extends State<_AddChargeSheet> {
  final _labelCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _category = 'Fixe';
  String _type = 'Autre';
  bool _saving = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Map<String, String> _localizedChargeTypes(AppLocalizations? l) => {
    'Salaire': l?.tr('finances_charge_salary') ?? 'Salaire',
    'Loyer': l?.tr('finances_charge_rent') ?? 'Loyer',
    'Produits': l?.tr('finances_charge_products') ?? 'Produits',
    'Équipement': l?.tr('finances_charge_equipment') ?? 'Équipement',
    'Factures': l?.tr('finances_charge_bills') ?? 'Factures',
    'Marketing': l?.tr('finances_charge_marketing') ?? 'Marketing',
    'Autre': l?.tr('finances_charge_other') ?? 'Autre',
  };

  Map<String, String> _localizedCategories(AppLocalizations? l) => {
    'Fixe': l?.tr('finances_category_fixed') ?? 'Fixe',
    'Variable': l?.tr('finances_category_variable') ?? 'Variable',
  };

  static const _chargeTypeIcons = <String, (IconData, Color)>{
    'Salaire': (Icons.people_outline_rounded, AppColors.brand600),
    'Loyer': (Icons.home_outlined, Color(0xFFDC2626)),
    'Produits': (Icons.shopping_bag_outlined, Color(0xFFEA580C)),
    'Équipement': (Icons.build_outlined, Color(0xFF2563EB)),
    'Factures': (Icons.receipt_outlined, Color(0xFF0891B2)),
    'Marketing': (Icons.campaign_outlined, AppColors.brand600),
    'Autre': (Icons.more_horiz_rounded, Color(0xFF6B7280)),
  };

  Future<void> _save() async {
    final label = _labelCtrl.text.trim();
    final amount =
        double.tryParse(_amountCtrl.text.replaceAll(',', '.'));
    if (label.isEmpty || amount == null || amount <= 0) return;

    setState(() => _saving = true);
    try {
      await _db.addCharge(ChargeModel(
        id: '',
        salonId: widget.salonId,
        label: label,
        category: _category,
        type: _type,
        amount: amount,
        month: widget.month,
        year: widget.year,
        createdAt: DateTime.now(),
      ));
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final chargeTypeLabels = _localizedChargeTypes(l);
    final categoryLabels = _localizedCategories(l);

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l?.tr('finances_add_charge') ?? 'Ajouter une charge',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 20),
          // Type selector (chips)
          Text(l?.tr('finances_type_label') ?? 'Type de charge',
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary500,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _chargeTypeIcons.entries.map((entry) {
              final selected = _type == entry.key;
              final (icon, color) = entry.value;
              return GestureDetector(
                onTap: () => setState(() => _type = entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected
                        ? color.withValues(alpha: 0.12)
                        : AppColors.secondary50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: selected ? color : AppColors.secondary200,
                      width: selected ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          size: 16,
                          color: selected
                              ? color
                              : AppColors.secondary400),
                      const SizedBox(width: 6),
                      Text(
                        chargeTypeLabels[entry.key] ?? entry.key,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: selected
                              ? color
                              : AppColors.secondary600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          _FinanceField(
              label: l?.tr('finances_label_hint') ?? 'Libellé (ex: Loyer local, Salaire Ahmed…)',
              controller: _labelCtrl),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: _FinanceField(
                label: l?.tr('finances_amount_hint') ?? 'Montant (${widget.currency})',
                controller: _amountCtrl,
                keyboard: const TextInputType.numberWithOptions(
                    decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(
                      RegExp(r'[\d,\.]'))
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l?.tr('finances_category_label') ?? 'Catégorie',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _category,
                        isExpanded: true,
                        style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.brand950),
                        items: ['Fixe', 'Variable']
                            .map((e) => DropdownMenuItem(
                                value: e, child: Text(categoryLabels[e] ?? e)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _category = v!),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(l?.tr('finances_save') ?? 'Enregistrer',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Charge Tile ─────────────────────────────────────────────────────────────

class _ChargeTile extends StatelessWidget {
  const _ChargeTile({required this.charge, required this.onDelete, this.currency = 'MAD'});
  final ChargeModel charge;
  final VoidCallback onDelete;
  final String currency;

  static const _typeConfig = <String, (IconData, Color)>{
    'Salaire': (Icons.people_outline_rounded, AppColors.brand600),
    'Loyer': (Icons.home_outlined, Color(0xFFDC2626)),
    'Produits': (Icons.shopping_bag_outlined, Color(0xFFEA580C)),
    'Équipement': (Icons.build_outlined, Color(0xFF2563EB)),
    'Factures': (Icons.receipt_outlined, Color(0xFF0891B2)),
    'Marketing': (Icons.campaign_outlined, AppColors.brand600),
    'Autre': (Icons.more_horiz_rounded, Color(0xFF6B7280)),
  };

  @override
  Widget build(BuildContext context) {
    final (icon, color) =
        _typeConfig[charge.type] ?? _typeConfig['Autre']!;

    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(charge.label,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.brand950,
                    )),
                Text(
                    '${charge.type} · ${charge.category}',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400)),
              ],
            ),
          ),
          Text(
            CurrencyHelper.format(charge.amount, currency),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: Color(0xFFDC2626),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.delete_outline,
                size: 18, color: AppColors.secondary400),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _MonthSelector extends StatelessWidget {
  const _MonthSelector({
    required this.months,
    required this.selectedMonth,
    required this.selectedYear,
    required this.onPrev,
    required this.onNext,
  });
  final List<String> months;
  final int selectedMonth;
  final int selectedYear;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left_rounded,
                color: AppColors.secondary500),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          Expanded(
            child: Text(
              '${months[selectedMonth - 1]} $selectedYear',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppColors.brand950,
              ),
            ),
          ),
          IconButton(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right_rounded,
                color: AppColors.secondary500),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

class _FinanceCard extends StatelessWidget {
  const _FinanceCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.valueColor,
  });
  final String label;
  final String value;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.secondary500)),
        ],
      ),
    );
  }
}

class _EmptyCharges extends StatelessWidget {
  const _EmptyCharges({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 40, color: AppColors.secondary200),
          const SizedBox(height: 12),
          Text(
            l?.tr('finances_no_charges') ?? 'Aucune charge enregistrée',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l?.tr('finances_no_charges_hint') ?? 'Loyer, fournitures, salaires...\nEnregistrez vos dépenses pour suivre la rentabilité.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondary400,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(l?.tr('finances_add_charge') ?? 'Ajouter une charge'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 12),
              textStyle: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 13),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceField extends StatelessWidget {
  const _FinanceField({
    required this.label,
    required this.controller,
    this.keyboard = TextInputType.text,
    this.inputFormatters,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType keyboard;
  final List<TextInputFormatter>? inputFormatters;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondary500,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboard,
          inputFormatters: inputFormatters,
          style: const TextStyle(
              fontSize: 14, color: AppColors.brand950),
          decoration: InputDecoration(
            contentPadding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            filled: true,
            fillColor: AppColors.secondary50,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }
}
