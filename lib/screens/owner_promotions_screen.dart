import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/promotion_model.dart';
import '../models/review_reward_model.dart';
import '../models/salon_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

final _db = DatabaseService();

String _buildShareText(PromotionModel promo, String? slug, [AppLocalizations? l]) {
  final buf = StringBuffer();
  buf.writeln(promo.title);
  buf.writeln(promo.description);
  if (promo.discountPercent != null) {
    buf.writeln((l?.tr('promotions_share_discount') ?? '-{percent}% de réduction !').replaceAll('{percent}', promo.discountPercent!.toStringAsFixed(0)));
  }
  if (promo.promoCode != null) {
    buf.writeln((l?.tr('promotions_share_code') ?? 'Code promo : {code}').replaceAll('{code}', promo.promoCode!));
  }
  if (promo.expiresAt != null) {
    buf.writeln(
        (l?.tr('promotions_share_valid_until') ?? "Valable jusqu'au {date}").replaceAll('{date}', '${promo.expiresAt!.day}/${promo.expiresAt!.month}/${promo.expiresAt!.year}'));
  }
  if (slug != null && slug.isNotEmpty) {
    buf.writeln('\n${(l?.tr('promotions_share_book_now') ?? 'Réservez maintenant : {url}').replaceAll('{url}', 'https://monsalon.web.app/s/$slug')}');
  }
  return buf.toString().trimRight();
}

Future<void> _sharePromo(PromotionModel promo, String? slug, [AppLocalizations? l]) async {
  final text = _buildShareText(promo, slug, l);
  await Share.share(text);
}

Future<void> _sharePromoWhatsApp(PromotionModel promo, String? slug, [AppLocalizations? l]) async {
  final text = _buildShareText(promo, slug, l);
  final encoded = Uri.encodeComponent(text);
  final url = Uri.parse('https://wa.me/?text=$encoded');
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

void _showShareDialog(BuildContext context, PromotionModel promo, String? slug) {
  final l = AppLocalizations.of(context);
  showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
      contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      title: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF16A34A), size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Text(l?.tr('promotions_created_dialog_title') ?? 'Promotion créée !',
                style: GoogleFonts.dmSans(
                    fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          IconButton(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.close_rounded,
                size: 20, color: AppColors.secondary400),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            l?.tr('promotions_share_question') ?? 'Souhaitez-vous partager cette offre ?',
            style: const TextStyle(fontSize: 13, color: AppColors.secondary500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sharePromoWhatsApp(promo, slug, l);
                  },
                  icon: const Icon(Icons.chat_rounded, size: 18),
                  label: const Text('WhatsApp'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF25D366),
                    side: const BorderSide(color: Color(0xFF25D366)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sharePromo(promo, slug, l);
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(l?.tr('promotions_share') ?? 'Partager'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    elevation: 0,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      actionsPadding: EdgeInsets.zero,
      actions: const [],
    ),
  );
}

class OwnerPromotionsScreen extends ConsumerStatefulWidget {
  const OwnerPromotionsScreen({super.key});

  @override
  ConsumerState<OwnerPromotionsScreen> createState() =>
      _OwnerPromotionsScreenState();
}

class _OwnerPromotionsScreenState
    extends ConsumerState<OwnerPromotionsScreen> {
  // Default: both groups collapsed (show only headers + counts).
  // Drill-down = tap to expand inline.
  final Set<String> _expandedGroups = {};
  // Default: hide expired/inactive. Toggle reveals them.
  bool _showInactive = false;

  bool _isExpanded(String key) => _expandedGroups.contains(key);

  void _toggleGroup(String key) {
    setState(() {
      if (_expandedGroups.contains(key)) {
        _expandedGroups.remove(key);
      } else {
        _expandedGroups.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);
    final promosAsync = ref.watch(ownerPromotionsProvider);

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
              l?.tr('promotions_title') ?? 'Offres & Promotions',
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
                onPressed: () {
                  final salon = salonAsync.value;
                  if (salon != null) {
                    _showAddPromoSheet(context, salon.id,
                        services: salon.services, slug: salon.slug);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          promosAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e')),
            ),
            data: (promos) {
              final activeCount =
                  promos.where((p) => p.isVisibleToClient).length;

              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats row
                      Row(
                        children: [
                          Expanded(
                            child: _PromoStat(
                              icon: Icons.local_offer_outlined,
                              iconBg: AppColors.brand50,
                              iconColor: AppColors.brand600,
                              label: l?.tr('promotions_active') ?? 'Actives',
                              value: '$activeCount',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PromoStat(
                              icon: Icons.inventory_2_outlined,
                              iconBg: const Color(0xFFF0FDF4),
                              iconColor: const Color(0xFF16A34A),
                              label: l?.tr('promotions_total') ?? 'Total',
                              value: '${promos.length}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Types section (tappable shortcuts)
                      Text(
                        l?.tr('promotions_create_title') ?? 'Créer une promotion',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _PromoTypeCard(
                        icon: Icons.percent_rounded,
                        iconBg: const Color(0xFFEFF6FF),
                        iconColor: const Color(0xFF2563EB),
                        title: l?.tr('promotions_type_percent') ?? 'Réduction en %',
                        desc: l?.tr('promotions_type_percent_desc') ?? 'Ex : -20% sur les soins du visage',
                        onTap: () {
                          final salon = salonAsync.value;
                          if (salon != null) {
                            _showAddPromoSheet(context, salon.id,
                                initialType: 'percent',
                                services: salon.services,
                                slug: salon.slug);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _PromoTypeCard(
                        icon: Icons.tune_outlined,
                        iconBg: const Color(0xFFFDF4FF),
                        iconColor: const Color(0xFF9333EA),
                        title: l?.tr('promotions_type_conditional') ?? 'Offre conditionnelle',
                        desc: l?.tr('promotions_type_conditional_desc') ?? 'Réduction avec conditions (minimum, jours, heures)',
                        onTap: () {
                          final salon = salonAsync.value;
                          if (salon != null) {
                            _showAddPromoSheet(context, salon.id,
                                initialType: 'conditional',
                                services: salon.services,
                                slug: salon.slug);
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                      _PromoTypeCard(
                        icon: Icons.confirmation_number_outlined,
                        iconBg: const Color(0xFFFFF7ED),
                        iconColor: const Color(0xFFEA580C),
                        title: l?.tr('promotions_type_code') ?? 'Code promo',
                        desc: l?.tr('promotions_type_code_desc') ?? 'Créez un code réservé à vos clients fidèles',
                        onTap: () {
                          final salon = salonAsync.value;
                          if (salon != null) {
                            _showAddPromoSheet(context, salon.id,
                                initialType: 'code',
                                services: salon.services,
                                slug: salon.slug);
                          }
                        },
                      ),
                      const SizedBox(height: 28),

                      // Promotions list — grouped by source (AI vs manual)
                      // with inline drill-down (tap header to expand).
                      // Inactive/expired hidden behind a toggle.
                      Builder(builder: (_) {
                        // Apply the active-only filter unless user opted in.
                        final visible = _showInactive
                            ? promos
                            : promos
                                .where((p) => p.isActive && !p.isExpired)
                                .toList();
                        final aiPromos =
                            visible.where((p) => p.isAiGenerated).toList();
                        final manualPromos =
                            visible.where((p) => !p.isAiGenerated).toList();
                        final hiddenCount = promos.length - visible.length;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Text(
                                  l?.tr('promotions_my_promotions') ??
                                      'Mes promotions',
                                  style: GoogleFonts.dmSans(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.brand950,
                                  ),
                                ),
                                const Spacer(),
                                if (hiddenCount > 0 || _showInactive)
                                  TextButton.icon(
                                    onPressed: () => setState(() {
                                      _showInactive = !_showInactive;
                                    }),
                                    icon: Icon(
                                      _showInactive
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                      size: 16,
                                      color: AppColors.secondary500,
                                    ),
                                    label: Text(
                                      _showInactive
                                          ? (l?.tr('promotions_hide_inactive') ??
                                              'Masquer inactives')
                                          : (l?.tr('promotions_show_inactive') ??
                                                  'Voir inactives ({n})')
                                              .replaceAll(
                                                  '{n}', '$hiddenCount'),
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        color: AppColors.secondary500,
                                      ),
                                    ),
                                    style: TextButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 4),
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (visible.isEmpty)
                              _EmptyPromos(
                                onAdd: () {
                                  final salon = salonAsync.value;
                                  if (salon != null) {
                                    _showAddPromoSheet(context, salon.id,
                                        services: salon.services,
                                        slug: salon.slug);
                                  }
                                },
                              )
                            else ...[
                              // Only render the AI promos block when the
                              // master switch (`salon.aiPromosEnabled`) is
                              // ON. The 4 rule cards are children of the
                              // master toggle in the user mental model,
                              // not an independent feature.
                              if (aiPromos.isNotEmpty &&
                                  salonAsync.value?.aiPromosEnabled == true) ...[
                                _PromoGroupSection(
                                  icon: Icons.auto_awesome_rounded,
                                  iconBg: AppColors.brand50,
                                  iconColor: AppColors.brand600,
                                  label: l?.tr('promotions_group_ai') ??
                                      'Promotions IA',
                                  count: aiPromos.length,
                                  expanded: _isExpanded('ai'),
                                  onToggle: () => _toggleGroup('ai'),
                                  promos: aiPromos,
                                  slug: salonAsync.value?.slug,
                                  onPromoToggle: (id, val) =>
                                      _db.togglePromotionActive(id, val),
                                  onPromoDelete: (id) =>
                                      _confirmDelete(context, id),
                                ),
                                const SizedBox(height: 10),
                              ],
                              if (manualPromos.isNotEmpty)
                                _PromoGroupSection(
                                  icon: Icons.person_outline_rounded,
                                  iconBg: const Color(0xFFEFF6FF),
                                  iconColor: const Color(0xFF2563EB),
                                  label: l?.tr('promotions_group_manual') ??
                                      'Promotions manuelles',
                                  count: manualPromos.length,
                                  expanded: _isExpanded('manual'),
                                  onToggle: () => _toggleGroup('manual'),
                                  promos: manualPromos,
                                  slug: salonAsync.value?.slug,
                                  onPromoToggle: (id, val) =>
                                      _db.togglePromotionActive(id, val),
                                  onPromoDelete: (id) =>
                                      _confirmDelete(context, id),
                                ),
                            ],
                          ],
                        );
                      }),
                      const SizedBox(height: 28),

                      // ── Paramètres fidélité & IA ────────────────────────
                      Text(
                        l?.tr('promotions_settings') ?? 'Paramètres',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 12),
                      salonAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (salon) {
                          if (salon == null) return const SizedBox.shrink();
                          return Column(
                            children: [
                              _RewardToggle(salon: salon),
                              const SizedBox(height: 1),
                              _AiPromoToggle(salon: salon),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 20),

                      // Google Review Reward section
                      salonAsync.when(
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                        data: (salon) {
                          if (salon == null) return const SizedBox.shrink();
                          final cfg = salon.googleReviewReward;
                          final enabled = cfg['enabled'] == true;
                          return _GoogleReviewSection(
                            salonId: salon.id,
                            config: cfg,
                            enabled: enabled,
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showAddPromoSheet(BuildContext context, String salonId,
      {String initialType = 'percent',
      List<Map<String, dynamic>> services = const [],
      String? slug}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddPromoSheet(
        salonId: salonId,
        initialType: initialType,
        services: services,
        slug: slug,
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('promotions_delete_title') ?? 'Supprimer cette promotion ?'),
        content: Text(l?.tr('promotions_delete_message') ?? 'Elle ne sera plus visible par les clients.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l?.tr('common_cancel') ?? 'Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l?.tr('common_delete') ?? 'Supprimer',
                  style: const TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deletePromotion(id);
    }
  }
}

// ── Add Promo Sheet ─────────────────────────────────────────────────────────

class _AddPromoSheet extends StatefulWidget {
  const _AddPromoSheet({
    required this.salonId,
    required this.initialType,
    required this.services,
    this.slug,
  });
  final String salonId;
  final String initialType;
  final List<Map<String, dynamic>> services;
  final String? slug;

  @override
  State<_AddPromoSheet> createState() => _AddPromoSheetState();
}

class _AddPromoSheetState extends State<_AddPromoSheet> {
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _percentCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController();
  late String _type;
  DateTime? _expiresAt;
  bool _saving = false;
  bool _allServices = true;
  final Set<String> _selectedServices = {};
  // Conditional fields
  final Set<String> _validDays = {};
  String? _validHoursStart;
  String? _validHoursEnd;

  static const _daysList = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
  ];

  Map<String, String> _typeLabels(AppLocalizations? l) => {
    'percent': l?.tr('promotions_type_selector_percent') ?? 'Réduction %',
    'conditional': l?.tr('promotions_type_selector_conditional') ?? 'Conditionnelle',
    'code': l?.tr('promotions_type_selector_code') ?? 'Code promo',
  };

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _percentCtrl.dispose();
    _codeCtrl.dispose();
    _minAmountCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _expiresAt = picked);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFDC2626),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context);
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    // Title is required; description is optional. We give explicit
    // SnackBar feedback for every failure path so the "Publier" button
    // never silently no-ops (was: title.isEmpty || desc.isEmpty → return,
    // which left the user staring at an unresponsive button).
    if (title.isEmpty) {
      _showError(l?.tr('promotions_error_title_required') ??
          'Veuillez saisir un titre pour la promotion.');
      return;
    }

    double? percent;
    if (_type == 'percent' || _type == 'conditional') {
      percent = double.tryParse(
          _percentCtrl.text.replaceAll(',', '.'));
      if (percent == null || percent <= 0 || percent > 100) {
        _showError(l?.tr('promotions_error_percent_invalid') ??
            'Le pourcentage doit être un nombre entre 1 et 100.');
        return;
      }
    }

    String? code;
    if (_type == 'code') {
      code = _codeCtrl.text.trim().toUpperCase();
      if (code.isEmpty) {
        _showError(l?.tr('promotions_error_code_required') ??
            'Veuillez saisir un code promo.');
        return;
      }
    }

    if ((_type == 'percent' || _type == 'conditional') &&
        !_allServices && _selectedServices.isEmpty) {
      _showError(l?.tr('promotions_error_services_required') ??
          'Sélectionnez au moins un service ou choisissez « Tous les services ».');
      return;
    }

    setState(() => _saving = true);
    try {
      // For percent/conditional type: null = all services, otherwise selected list
      List<String>? serviceNames;
      if ((_type == 'percent' || _type == 'conditional') &&
          !_allServices && _selectedServices.isNotEmpty) {
        serviceNames = _selectedServices.toList();
      }

      // Conditional fields
      double? minAmount;
      List<String>? validDays;
      String? hoursStart;
      String? hoursEnd;
      if (_type == 'conditional') {
        final minText = _minAmountCtrl.text.trim();
        if (minText.isNotEmpty) {
          minAmount = double.tryParse(minText.replaceAll(',', '.'));
        }
        if (_validDays.isNotEmpty) validDays = _validDays.toList();
        hoursStart = _validHoursStart;
        hoursEnd = _validHoursEnd;
      }

      final promo = PromotionModel(
        id: '',
        salonId: widget.salonId,
        title: title,
        description: desc,
        type: _type,
        discountPercent: percent,
        promoCode: code,
        applicableServiceNames: serviceNames,
        expiresAt: _expiresAt,
        isActive: true,
        createdAt: DateTime.now(),
        minAmount: minAmount,
        validDays: validDays,
        validHoursStart: hoursStart,
        validHoursEnd: hoursEnd,
      );
      await _db.addPromotion(promo);
      if (mounted) {
        Navigator.pop(context);
        _showShareDialog(context, promo, widget.slug);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l?.tr('promotions_new_title') ?? 'Nouvelle promotion',
                style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950)),
            const SizedBox(height: 20),

            // Type selector
            Row(
              children: _typeLabels(l).entries.map((e) {
                final selected = _type == e.key;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _type = e.key),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.brand700
                            : AppColors.secondary50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.secondary500,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),

            _PromoField(label: l?.tr('promotions_field_title') ?? 'Titre *', controller: _titleCtrl),
            const SizedBox(height: 12),
            _PromoField(
                label: l?.tr('promotions_field_description_optional') ??
                    'Description (optionnel)',
                controller: _descCtrl,
                maxLines: 2),
            const SizedBox(height: 12),

            if (_type == 'percent' || _type == 'conditional') ...[
              _PromoField(
                label: l?.tr('promotions_field_percent') ?? 'Pourcentage de réduction (%)',
                controller: _percentCtrl,
                keyboard: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
              const SizedBox(height: 12),

              // Service selection
              Text(l?.tr('promotions_apply_on') ?? 'Appliquer sur',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ServiceToggle(
                    label: l?.tr('promotions_all_services') ?? 'Tous les services',
                    selected: _allServices,
                    onTap: () => setState(() {
                      _allServices = true;
                      _selectedServices.clear();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _ServiceToggle(
                    label: l?.tr('promotions_specific_services') ?? 'Services spécifiques',
                    selected: !_allServices,
                    onTap: () => setState(() => _allServices = false),
                  ),
                ],
              ),
              if (!_allServices && widget.services.isNotEmpty) ...[
                const SizedBox(height: 10),
                _ServicesMultiSelect(
                  l: l,
                  services: widget.services,
                  selected: _selectedServices,
                  onChanged: (next) =>
                      setState(() {
                        _selectedServices
                          ..clear()
                          ..addAll(next);
                      }),
                ),
              ],
              if (!_allServices && widget.services.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l?.tr('promotions_no_services') ?? 'Aucun service configuré dans votre salon.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.secondary400),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            // ── Conditional-specific fields ──
            if (_type == 'conditional') ...[
              // Min amount
              _PromoField(
                label: l?.tr('promotions_min_amount') ?? 'Dépense minimum (MAD) — optionnel',
                controller: _minAmountCtrl,
                keyboard: const TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),

              // Valid days
              Text(l?.tr('promotions_valid_days') ?? 'Jours valides (optionnel)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _daysList.map((day) {
                  final selected = _validDays.contains(day);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _validDays.remove(day);
                      } else {
                        _validDays.add(day);
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AppColors.brand700
                            : AppColors.secondary50,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected
                              ? AppColors.brand700
                              : AppColors.secondary200,
                        ),
                      ),
                      child: Text(
                        day.substring(0, 3),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: selected
                              ? Colors.white
                              : AppColors.secondary500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              if (_validDays.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l?.tr('promotions_all_days_hint') ?? 'Tous les jours si aucun sélectionné',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.secondary400),
                  ),
                ),
              const SizedBox(height: 12),

              // Valid hours
              Text(l?.tr('promotions_valid_hours') ?? 'Heures valides (optionnel)',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: const TimeOfDay(hour: 9, minute: 0),
                        );
                        if (time != null) {
                          setState(() => _validHoursStart =
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: AppColors.secondary400),
                            const SizedBox(width: 8),
                            Text(
                              _validHoursStart ?? (l?.tr('promotions_hours_from') ?? 'De'),
                              style: TextStyle(
                                fontSize: 13,
                                color: _validHoursStart != null
                                    ? AppColors.brand950
                                    : AppColors.secondary400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('→',
                        style: TextStyle(color: AppColors.secondary400)),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () async {
                        final time = await showTimePicker(
                          context: context,
                          initialTime: const TimeOfDay(hour: 12, minute: 0),
                        );
                        if (time != null) {
                          setState(() => _validHoursEnd =
                              '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.access_time,
                                size: 16, color: AppColors.secondary400),
                            const SizedBox(width: 8),
                            Text(
                              _validHoursEnd ?? (l?.tr('promotions_hours_to') ?? 'À'),
                              style: TextStyle(
                                fontSize: 13,
                                color: _validHoursEnd != null
                                    ? AppColors.brand950
                                    : AppColors.secondary400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (_validHoursStart != null || _validHoursEnd != null)
                    IconButton(
                      icon: const Icon(Icons.close,
                          size: 16, color: AppColors.secondary400),
                      onPressed: () => setState(() {
                        _validHoursStart = null;
                        _validHoursEnd = null;
                      }),
                    ),
                ],
              ),
              if (_validHoursStart == null && _validHoursEnd == null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    l?.tr('promotions_all_day_hint') ?? 'Toute la journée si non défini',
                    style: TextStyle(
                        fontSize: 11, color: AppColors.secondary400),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            if (_type == 'code') ...[
              _PromoField(
                label: l?.tr('promotions_code_hint') ?? 'Code promo (ex: BIENVENUE20)',
                controller: _codeCtrl,
              ),
              const SizedBox(height: 12),
            ],

            // Expiry date picker
            GestureDetector(
              onTap: _pickDate,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 13),
                decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_today_outlined,
                        size: 16, color: AppColors.secondary400),
                    const SizedBox(width: 10),
                    Text(
                      _expiresAt == null
                          ? (l?.tr('promotions_expiry_date') ?? "Date d'expiration (optionnel)")
                          : (l?.tr('promotions_expiry_label') ?? 'Expire le {date}').replaceAll('{date}', '${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}'),
                      style: TextStyle(
                        fontSize: 13,
                        color: _expiresAt == null
                            ? AppColors.secondary400
                            : AppColors.brand950,
                      ),
                    ),
                    const Spacer(),
                    if (_expiresAt != null)
                      GestureDetector(
                        onTap: () =>
                            setState(() => _expiresAt = null),
                        child: const Icon(Icons.close,
                            size: 16,
                            color: AppColors.secondary400),
                      ),
                  ],
                ),
              ),
            ),
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
                  padding:
                      const EdgeInsets.symmetric(vertical: 14),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(l?.tr('promotions_publish') ?? 'Publier',
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Promo Tile ───────────────────────────────────────────────────────────────

class _PromoGroupSection extends StatelessWidget {
  const _PromoGroupSection({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.count,
    required this.expanded,
    required this.onToggle,
    required this.promos,
    required this.slug,
    required this.onPromoToggle,
    required this.onPromoDelete,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final int count;
  final bool expanded;
  final VoidCallback onToggle;
  final List<PromotionModel> promos;
  final String? slug;
  final void Function(String id, bool value) onPromoToggle;
  final void Function(String id) onPromoDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
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
                    child: Text(
                      label,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.secondary600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.secondary400,
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1, color: AppColors.secondary100),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              child: Column(
                children: [
                  for (var i = 0; i < promos.length; i++) ...[
                    _PromoTile(
                      promo: promos[i],
                      slug: slug,
                      onToggle: (val) =>
                          onPromoToggle(promos[i].id, val),
                      onDelete: () => onPromoDelete(promos[i].id),
                    ),
                    if (i < promos.length - 1) const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PromoTile extends StatelessWidget {
  const _PromoTile({
    required this.promo,
    required this.onToggle,
    required this.onDelete,
    this.slug,
  });
  final PromotionModel promo;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  final String? slug;

  static const _typeIcon = {
    'percent': Icons.percent_rounded,
    'conditional': Icons.tune_outlined,
    'special': Icons.tune_outlined,
    'code': Icons.confirmation_number_outlined,
  };
  static const _typeBg = {
    'percent': Color(0xFFEFF6FF),
    'conditional': Color(0xFFFDF4FF),
    'special': Color(0xFFFDF4FF),
    'code': Color(0xFFFFF7ED),
  };
  static const _typeColor = {
    'percent': Color(0xFF2563EB),
    'conditional': Color(0xFF9333EA),
    'special': Color(0xFF9333EA),
    'code': Color(0xFFEA580C),
  };

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isExpired = promo.isExpired;
    final bgColor = _typeBg[promo.type] ?? AppColors.brand50;
    final iconColor = _typeColor[promo.type] ?? AppColors.brand600;
    final icon = _typeIcon[promo.type] ?? Icons.local_offer_outlined;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isExpired
                ? AppColors.secondary100
                : (promo.isActive
                    ? AppColors.brand100
                    : AppColors.secondary100)),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: isExpired ? AppColors.secondary100 : bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon,
                color:
                    isExpired ? AppColors.secondary300 : iconColor,
                size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(promo.title,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: isExpired
                                ? AppColors.secondary400
                                : AppColors.brand950,
                          )),
                    ),
                    if (promo.isAiGenerated)
                      _Badge(
                          label: l?.tr('promotions_badge_ai') ?? 'IA',
                          color: AppColors.brand500),
                    if (promo.isAiGenerated) const SizedBox(width: 4),
                    if (isExpired)
                      _Badge(
                          label: l?.tr('promotions_badge_expired') ?? 'Expirée',
                          color: AppColors.secondary300)
                    else if (promo.isActive)
                      _Badge(
                          label: l?.tr('promotions_badge_active') ?? 'Active',
                          color: const Color(0xFF16A34A)),
                  ],
                ),
                const SizedBox(height: 2),
                if (promo.isAiRuleBased)
                  // Rule-based AI promo (1 doc per aiReason, applies to
                  // every eligible client). The per-instance description
                  // / client name / expiry don't make sense here — show a
                  // redemption counter instead. Backend increments
                  // `redemptionCount` atomically at each redemption.
                  Row(
                    children: [
                      const Icon(Icons.people_outline_rounded,
                          size: 12, color: AppColors.brand500),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          () {
                            final n = promo.redemptionCount;
                            if (n == 0) {
                              return l?.tr('promotions_ai_no_redemptions') ??
                                  'Aucune utilisation pour le moment';
                            }
                            // FR/EN/ES split on n==1; AR's plural rules
                            // are richer but the _other variant is OK
                            // for 2+ in this UX (avoids dual/few/many).
                            final key = n == 1
                                ? 'promotions_ai_redemption_count_one'
                                : 'promotions_ai_redemption_count_other';
                            final fallback = n == 1
                                ? '1 personne a profité de cette offre'
                                : '$n personnes ont profité de cette offre';
                            return (l?.tr(key) ?? fallback)
                                .replaceAll('{n}', '$n');
                          }(),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.brand500,
                              fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else
                  Text(promo.description,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                // Show "Pour {name}" only when the promo actually targets
                // ONE specific client (manual targeted, or transitional
                // old per-client AI doc still in flight). Rule-based AI
                // promos have `targetedClientId == null` so they fall
                // through naturally.
                if (promo.targetedClientId != null &&
                    promo.targetedClientName != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: AppColors.brand500),
                      const SizedBox(width: 4),
                      Text(
                        (l?.tr('promotions_for_client') ?? 'Pour {name}').replaceAll('{name}', promo.targetedClientName!),
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.brand500,
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
                if (promo.promoCode != null) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(promo.promoCode!,
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                            letterSpacing: 1.2)),
                  ),
                ],
                // Rule-based AI promos have no per-instance expiry
                // (they stay live as long as the rule is enabled). Old
                // per-client AI docs still carry a +7d expiry — show it
                // for those, hide for rule-based.
                if (promo.expiresAt != null &&
                    !isExpired &&
                    !promo.isAiRuleBased) ...[
                  const SizedBox(height: 3),
                  Text(
                    (l?.tr('promotions_expiry_label') ?? 'Expire le {date}').replaceAll('{date}', '${promo.expiresAt!.day}/${promo.expiresAt!.month}/${promo.expiresAt!.year}'),
                    style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.secondary400),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isExpired)
                Switch(
                  value: promo.isActive,
                  onChanged: onToggle,
                  activeThumbColor: Colors.white,
                  activeTrackColor: AppColors.brand600,
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                ),
              // AI promos can only be enabled/disabled (the switch
              // above). The pre-Zayna cron `generateSmartPromotions`
              // already pushes a per-client notification on creation,
              // so manual share is redundant. Delete is suppressed too:
              // each AI promo expires on its own in 7 days, and removing
              // one mid-window can leave a client looking for an offer
              // they were already notified about. Owner just toggles
              // on/off — set-and-forget.
              if (!promo.isAiGenerated) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.share_rounded,
                          size: 17, color: AppColors.brand400),
                      onPressed: () => _sharePromo(promo, slug, l),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 17, color: AppColors.secondary300),
                      onPressed: onDelete,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: color)),
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _PromoStat extends StatelessWidget {
  const _PromoStat({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;

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
          Text(value,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.secondary500)),
        ],
      ),
    );
  }
}

class _PromoTypeCard extends StatelessWidget {
  const _PromoTypeCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.desc,
    required this.onTap,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String desc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
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
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.brand950)),
                  const SizedBox(height: 2),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary400)),
                ],
              ),
            ),
            const Icon(Icons.add_circle_outline_rounded,
                color: AppColors.brand400, size: 20),
          ],
        ),
      ),
    );
  }
}

class _EmptyPromos extends StatelessWidget {
  const _EmptyPromos({required this.onAdd});
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
          const Icon(Icons.local_offer_outlined,
              size: 40, color: AppColors.secondary200),
          const SizedBox(height: 12),
          Text(
            l?.tr('promotions_empty_title') ?? 'Aucune promotion créée',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l?.tr('promotions_empty_subtitle') ?? 'Créez des offres attractives pour fidéliser\nvos clients et attirer de nouvelles réservations.',
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
            label: Text(l?.tr('promotions_empty_button') ?? 'Créer une promotion'),
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

class _ServiceToggle extends StatelessWidget {
  const _ServiceToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand700 : AppColors.secondary50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? AppColors.brand700 : AppColors.secondary200,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.secondary500,
            ),
          ),
        ),
      ),
    );
  }
}

class _PromoField extends StatelessWidget {
  const _PromoField({
    required this.label,
    required this.controller,
    this.keyboard = TextInputType.text,
    this.maxLines = 1,
  });
  final String label;
  final TextEditingController controller;
  final TextInputType keyboard;
  final int maxLines;

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
          maxLines: maxLines,
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

// ── Google Review Reward Section ─────────────────────────────────────────────

class _GoogleReviewSection extends StatefulWidget {
  const _GoogleReviewSection({
    required this.salonId,
    required this.config,
    required this.enabled,
  });
  final String salonId;
  final Map<String, dynamic> config;
  final bool enabled;

  @override
  State<_GoogleReviewSection> createState() => _GoogleReviewSectionState();
}

class _GoogleReviewSectionState extends State<_GoogleReviewSection> {
  void _showInfoDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF9C3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.star_rounded,
                  color: Color(0xFFCA8A04), size: 20),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(l?.tr('promotions_google_review_title') ?? 'Récompense Avis Google',
                  style: GoogleFonts.dmSans(
                      fontSize: 15, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l?.tr('promotions_google_review_how') ?? 'Comment ça fonctionne ?',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.brand950),
            ),
            SizedBox(height: 10),
            _InfoStep(
              number: '1',
              text: l?.tr('promotions_google_review_step1') ??
                  'Après un RDV terminé, le client reçoit une invitation à laisser un avis Google.',
            ),
            SizedBox(height: 8),
            _InfoStep(
              number: '2',
              text: l?.tr('promotions_google_review_step2') ??
                  'Il tape "J\'ai laissé mon avis" dans l\'app — une demande de validation vous est envoyée.',
            ),
            SizedBox(height: 8),
            _InfoStep(
              number: '3',
              text: l?.tr('promotions_google_review_step3') ??
                  'Vous vérifiez l\'avis sur Google Maps, puis validez dans l\'app.',
            ),
            SizedBox(height: 8),
            _InfoStep(
              number: '4',
              text: l?.tr('promotions_google_review_step4') ??
                  'Le client reçoit automatiquement son code promo de réduction.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l?.tr('promotions_google_review_understood') ?? 'Compris'),
          ),
        ],
      ),
    );
  }

  void _showSettingsDialog({bool forceEnable = false}) {
    final l = AppLocalizations.of(context);
    final percentCtrl = TextEditingController(
        text: '${widget.config['discountPercent'] ?? 10}');
    final mapsUrlCtrl = TextEditingController(
        text: widget.config['googleMapsUrl'] ?? '');
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(l?.tr('promotions_google_review_settings') ?? 'Paramètres de la récompense',
              style: GoogleFonts.dmSans(
                  fontSize: 15, fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l?.tr('promotions_google_review_discount') ?? 'Réduction offerte (%)',
                  style: TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 6),
              TextField(
                controller: percentCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Ex: 10',
                  filled: true,
                  fillColor: AppColors.secondary50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Text(l?.tr('promotions_google_review_maps_url') ?? 'Lien Google Maps',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: ctx,
                        builder: (_) => AlertDialog(
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          title: Text(l?.tr('promotions_google_review_how_to_link') ?? 'Comment obtenir le lien ?'),
                          content: const Text(
                            '1. Ouvrez Google Maps\n'
                            '2. Recherchez votre salon\n'
                            '3. Appuyez sur "Partager" → copiez le lien\n\n'
                            'Le lien ressemble à :\nhttps://maps.app.goo.gl/...',
                          ),
                          actions: [
                            TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(l?.tr('common_ok') ?? 'OK')),
                          ],
                        ),
                      );
                    },
                    child: const Icon(Icons.help_outline_rounded,
                        size: 15, color: AppColors.secondary400),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: mapsUrlCtrl,
                decoration: InputDecoration(
                  hintText: 'https://maps.app.goo.gl/...',
                  filled: true,
                  fillColor: AppColors.secondary50,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(l?.tr('common_cancel') ?? 'Annuler'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final percent =
                          int.tryParse(percentCtrl.text.trim()) ?? 10;
                      final mapsUrl = mapsUrlCtrl.text.trim();
                      if (percent <= 0 || percent > 100) return;
                      if (forceEnable && mapsUrl.isEmpty) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(l?.tr('promotions_google_review_url_required') ??
                                'Merci d\'entrer votre lien Google Maps pour activer la récompense.'),
                            backgroundColor: Colors.red,
                          ),
                        );
                        return;
                      }
                      setDlgState(() => saving = true);
                      final newConfig = {
                        'enabled': forceEnable ? true : widget.enabled,
                        'discountPercent': percent,
                        'googleMapsUrl': mapsUrl,
                      };
                      await _db.updateGoogleReviewReward(
                          widget.salonId, newConfig);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand700,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(l?.tr('common_save') ?? 'Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      // Activation → ouvrir directement la popup des paramètres.
      // Le save du dialog fera enabled=true (via forceEnable).
      _showSettingsDialog(forceEnable: true);
    } else {
      // Désactivation → save direct.
      final newConfig = Map<String, dynamic>.from(widget.config);
      newConfig['enabled'] = false;
      await _db.updateGoogleReviewReward(widget.salonId, newConfig);
    }
  }

  Future<void> _validateReward(ReviewRewardModel reward) async {
    final percent = widget.config['discountPercent'] ?? 10;
    final code =
        'AVIS${reward.clientName.toUpperCase().replaceAll(' ', '').substring(0, reward.clientName.length.clamp(0, 4))}$percent';
    await _db.validateReviewReward(reward.id, code);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code "$code" envoyé à ${reward.clientName}'),
          backgroundColor: const Color(0xFF16A34A),
        ),
      );
    }
  }

  Future<void> _rejectReward(ReviewRewardModel reward) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Refuser cet avis ?'),
        content: Text(
            'La demande de ${reward.clientName} sera refusée, aucun code promo ne sera envoyé.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l?.tr('common_cancel') ?? 'Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Refuser',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.rejectReviewReward(reward.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l?.tr('promotions_google_review_title') ?? 'Récompense Avis Google',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(width: 6),
            GestureDetector(
              onTap: _showInfoDialog,
              child: const Icon(Icons.info_outline_rounded,
                  size: 17, color: AppColors.secondary400),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.secondary100),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF9C3),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.star_rounded,
                        color: Color(0xFFCA8A04), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppLocalizations.of(context)?.tr('promo_google_title') ?? 'Offrir une réduction pour un avis Google',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: AppColors.brand950,
                          ),
                        ),
                        Text(
                          widget.enabled
                              ? '${widget.config['discountPercent'] ?? 10}% ${AppLocalizations.of(context)?.tr('promo_google_active') ?? 'de réduction à la validation'}'
                              : (AppLocalizations.of(context)?.tr('promo_google_inactive') ?? 'Activez pour récompenser vos clients'),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.secondary400),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: widget.enabled,
                    onChanged: _toggleEnabled,
                    activeThumbColor: Colors.white,
                    activeTrackColor: AppColors.brand600,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              if (widget.enabled) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _showSettingsDialog,
                    icon: const Icon(Icons.tune_rounded, size: 16),
                    label: Text(l?.tr('promotions_settings') ?? 'Paramètres', style: const TextStyle(fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.brand700,
                      side: const BorderSide(color: AppColors.brand200),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),

        // Pending review rewards list
        if (widget.enabled) ...[
          const SizedBox(height: 20),
          StreamBuilder<List<ReviewRewardModel>>(
            stream: _db.getPendingReviewRewards(widget.salonId),
            builder: (context, snap) {
              final rewards = snap.data ?? [];
              if (rewards.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Avis en attente de validation',
                        style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF9C3),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${rewards.length}',
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFCA8A04)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ...rewards.map((r) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ReviewRewardTile(
                          reward: r,
                          googleMapsUrl:
                              widget.config['googleMapsUrl'] ?? '',
                          onValidate: () => _validateReward(r),
                          onReject: () => _rejectReward(r),
                        ),
                      )),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}

class _InfoStep extends StatelessWidget {
  const _InfoStep({required this.number, required this.text});
  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: const BoxDecoration(
            color: AppColors.brand700,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(number,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary600,
                  height: 1.4)),
        ),
      ],
    );
  }
}

class _ReviewRewardTile extends StatelessWidget {
  const _ReviewRewardTile({
    required this.reward,
    required this.googleMapsUrl,
    required this.onValidate,
    required this.onReject,
  });
  final ReviewRewardModel reward;
  final String googleMapsUrl;
  final VoidCallback onValidate;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    final date =
        '${reward.createdAt.day}/${reward.createdAt.month}/${reward.createdAt.year}';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFFEF9C3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline_rounded,
                  size: 16, color: AppColors.brand400),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  reward.clientName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppColors.brand950),
                ),
              ),
              Text(date,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.secondary400)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${reward.discountPercent}% de réduction à offrir',
            style: const TextStyle(
                fontSize: 12, color: AppColors.secondary500),
          ),
          if (googleMapsUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () async {
                final url = Uri.parse(googleMapsUrl);
                if (await canLaunchUrl(url)) {
                  await launchUrl(url,
                      mode: LaunchMode.externalApplication);
                }
              },
              child: const Row(
                children: [
                  Icon(Icons.open_in_new_rounded,
                      size: 13, color: AppColors.brand600),
                  SizedBox(width: 4),
                  Text(
                    'Voir les avis Google',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.brand600,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFDC2626),
                    side:
                        const BorderSide(color: Color(0xFFFECACA)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Refuser',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: onValidate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Valider ✓',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Reward Points Toggle ─────────────────────────────────────────────────────

class _RewardToggle extends StatefulWidget {
  const _RewardToggle({required this.salon});
  final SalonModel salon;

  @override
  State<_RewardToggle> createState() => _RewardToggleState();
}

class _RewardToggleState extends State<_RewardToggle> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.salon.rewardPointsEnabled;
  }

  Future<void> _toggle(bool value) async {
    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await DatabaseService().updateSalonField(
        widget.salon.id,
        'rewardPointsEnabled',
        value,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _enabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.stars_rounded,
                size: 20, color: AppColors.brand600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppLocalizations.of(context)?.tr('promo_loyalty_title') ?? 'Points de fidélité',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand950,
                  ),
                ),
                Text(
                  _enabled
                      ? (AppLocalizations.of(context)?.tr('promo_loyalty_active') ?? 'Les clients cumulent des points')
                      : (AppLocalizations.of(context)?.tr('promo_loyalty_inactive') ?? 'Système désactivé'),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary400,
                  ),
                ),
              ],
            ),
          ),
          if (_saving)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.brand600),
            )
          else
            Switch(
              value: _enabled,
              onChanged: _toggle,
              activeTrackColor: AppColors.brand600,
            ),
        ],
      ),
    );
  }
}

// ── AI Auto-Promotions Toggle ────────────────────────────────────────────────

class _AiPromoToggle extends StatefulWidget {
  const _AiPromoToggle({required this.salon});
  final SalonModel salon;

  @override
  State<_AiPromoToggle> createState() => _AiPromoToggleState();
}

class _AiPromoToggleState extends State<_AiPromoToggle> {
  late bool _enabled;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.salon.aiPromosEnabled;
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child:
                    Text(AppLocalizations.of(context)?.tr('promo_ai_title') ?? 'Promotions IA', style: const TextStyle(fontSize: 17)),
              ),
            ],
          ),
          content: Text(
            AppLocalizations.of(context)?.tr('promo_ai_dialog_body') ??
            'L\'IA analysera vos clients chaque jour et créera des promotions ciblées :\n\n'
            '• Meilleur client du mois\n'
            '• Client absent depuis longtemps\n'
            '• Client fidèle\n\n'
            'Les promotions sont envoyées par notification push. '
            'Vous pouvez personnaliser les pourcentages depuis les paramètres.',
            style: const TextStyle(
                fontSize: 13.5, height: 1.5, color: AppColors.secondary600),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)?.tr('common_cancel') ?? 'Annuler'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Activer',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    setState(() {
      _enabled = value;
      _saving = true;
    });
    try {
      await DatabaseService().updateSalonField(
        widget.salon.id,
        'aiPromosEnabled',
        value,
      );
      // Cascade isActive on existing AI rule docs so the section above
      // (Promotions IA cards) reflects the master state immediately.
      // Without this, flipping the master OFF leaves the 4 rule cards
      // showing "Active" until the next sync cron pass.
      await DatabaseService().setAiPromotionsActive(widget.salon.id, value);
      // When flipping ON, also trigger the on-demand sync — covers the
      // first-time-enable case where no AI rule docs exist yet (cascade
      // alone wouldn't create them; we'd have to wait for the daily
      // 08:00 Paris cron).
      if (value) {
        try {
          await FirebaseFunctions.instance
              .httpsCallable('syncAiPromosNow')
              .call();
        } catch (_) {
          // Non-fatal — daily cron will catch up.
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enabled = !value);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showConfigDialog() async {
    final config = Map<String, dynamic>.from(widget.salon.aiPromoConfig);
    int topPercent = config['topClientPercent'] ?? 30;
    int winBackPercent = config['winBackPercent'] ?? 20;
    int winBackWeeks = config['winBackWeeks'] ?? 3;
    int loyalPercent = config['loyalPercent'] ?? 15;
    int loyalMinVisits = config['loyalMinVisits'] ?? 10;
    bool birthdayEnabled = config['birthdayEnabled'] ?? true;
    int birthdayPercent = config['birthdayPercent'] ?? 20;

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.tune_rounded,
                    size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Configurer les promos IA',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SizedBox(
            width: MediaQuery.of(ctx).size.width,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _configRow(
                    AppLocalizations.of(context)?.tr('promo_ai_best_client') ?? 'Meilleur client',
                    'Réduction pour le top client du mois',
                    '$topPercent%',
                    topPercent,
                    5,
                    50,
                    (v) => setDialogState(() => topPercent = v),
                  ),
                  const Divider(height: 24),
                  _configRow(
                    AppLocalizations.of(context)?.tr('promo_ai_absent_client') ?? 'Client absent',
                    'Réduction pour récupérer un client',
                    '$winBackPercent%',
                    winBackPercent,
                    5,
                    50,
                    (v) => setDialogState(() => winBackPercent = v),
                  ),
                  const SizedBox(height: 8),
                  _configRow(
                    'Semaines d\'absence',
                    'Après combien de semaines ?',
                    '$winBackWeeks sem.',
                    winBackWeeks,
                    2,
                    8,
                    (v) => setDialogState(() => winBackWeeks = v),
                  ),
                  const Divider(height: 24),
                  _configRow(
                    AppLocalizations.of(context)?.tr('promo_ai_loyal_client') ?? 'Client fidèle',
                    'Réduction de remerciement',
                    '$loyalPercent%',
                    loyalPercent,
                    5,
                    50,
                    (v) => setDialogState(() => loyalPercent = v),
                  ),
                  const SizedBox(height: 8),
                  _configRow(
                    'Visites minimum',
                    'Nombre de visites pour être fidèle',
                    '$loyalMinVisits',
                    loyalMinVisits,
                    5,
                    30,
                    (v) => setDialogState(() => loyalMinVisits = v),
                  ),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Promo anniversaire',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.brand950)),
                            Text(
                                'Envoyer un message + offrir une réduction le jour J',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: AppColors.secondary400)),
                          ],
                        ),
                      ),
                      Switch(
                        value: birthdayEnabled,
                        activeTrackColor: AppColors.brand600,
                        onChanged: (v) =>
                            setDialogState(() => birthdayEnabled = v),
                      ),
                    ],
                  ),
                  if (birthdayEnabled) ...[
                    const SizedBox(height: 8),
                    _configRow(
                      'Réduction anniversaire',
                      'Offre envoyée le jour de l\'anniversaire',
                      '$birthdayPercent%',
                      birthdayPercent,
                      5,
                      50,
                      (v) => setDialogState(() => birthdayPercent = v),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(AppLocalizations.of(context)?.tr('common_cancel') ?? 'Annuler'),
            ),
            ElevatedButton(
              onPressed: () {
                config['topClientPercent'] = topPercent;
                config['winBackPercent'] = winBackPercent;
                config['winBackWeeks'] = winBackWeeks;
                config['loyalPercent'] = loyalPercent;
                config['loyalMinVisits'] = loyalMinVisits;
                config['birthdayEnabled'] = birthdayEnabled;
                config['birthdayPercent'] = birthdayPercent;
                Navigator.pop(ctx, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Enregistrer',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (saved == true) {
      try {
        await DatabaseService().updateSalonField(
          widget.salon.id,
          'aiPromoConfig',
          config,
        );
        // Trigger immediate sync of the AI rule promo docs so the new
        // percentages land before the next 08:00 Paris cron pass. CF is
        // a no-op when the master switch is OFF — safe to call always.
        try {
          await FirebaseFunctions.instance
              .httpsCallable('syncAiPromosNow')
              .call();
        } catch (_) {
          // Non-fatal — daily cron will catch up. Don't block the UX.
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Configuration IA enregistrée'),
              backgroundColor: Color(0xFF16A34A),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${AppLocalizations.of(context)?.tr('common_error_short') ?? 'Erreur'} : $e')),
          );
        }
      }
    }
  }

  Widget _configRow(String title, String subtitle, String valueLabel,
      int value, int min, int max, ValueChanged<int> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950)),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.secondary400)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(valueLabel,
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand600)),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.brand600,
            inactiveTrackColor: AppColors.brand100,
            thumbColor: AppColors.brand600,
            overlayColor: AppColors.brand600.withValues(alpha: 0.1),
            trackHeight: 3,
          ),
          child: Slider(
            value: value.toDouble(),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) => onChanged(v.round()),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome,
                    size: 20, color: AppColors.brand600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Promotions IA',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950,
                      ),
                    ),
                    Text(
                      _enabled
                          ? 'Promotions ciblées automatiques'
                          : 'Désactivé',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
              ),
              if (_saving)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.brand600),
                )
              else
                Switch(
                  value: _enabled,
                  onChanged: _toggle,
                  activeTrackColor: AppColors.brand600,
                ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _showConfigDialog,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 14),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.brand100),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 16, color: AppColors.brand600),
                    SizedBox(width: 8),
                    Text(
                      'Configurer les pourcentages',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Multi-select for "Services spécifiques" on the promotion form.
/// Shows a dropdown-style button with the current count + a list expander.
/// Was previously a Wrap of chips that took the full screen width when
/// the salon had many services — moved to an explicit pop-out list per
/// owner request.
class _ServicesMultiSelect extends StatefulWidget {
  final AppLocalizations? l;
  final List<Map<String, dynamic>> services;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  const _ServicesMultiSelect({
    required this.l,
    required this.services,
    required this.selected,
    required this.onChanged,
  });

  @override
  State<_ServicesMultiSelect> createState() => _ServicesMultiSelectState();
}

class _ServicesMultiSelectState extends State<_ServicesMultiSelect> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final count = widget.selected.length;
    final label = count == 0
        ? (widget.l?.tr('promotions_select_services') ??
            'Sélectionner les services')
        : (widget.l?.tr('promotions_selected_services_count') ??
                '{count} service(s) sélectionné(s)')
            .replaceAll('{count}', '$count');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _open = !_open),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.secondary50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary200),
            ),
            child: Row(
              children: [
                const Icon(Icons.checklist_rounded,
                    size: 18, color: AppColors.brand700),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: count > 0 ? FontWeight.w600 : FontWeight.w400,
                      color: count > 0
                          ? AppColors.brand950
                          : AppColors.secondary500,
                    ),
                  ),
                ),
                Icon(
                  _open
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  size: 22,
                  color: AppColors.secondary500,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.secondary200),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              itemCount: widget.services.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: AppColors.secondary100,
              ),
              itemBuilder: (_, i) {
                final s = widget.services[i];
                final name = (s['name'] ?? s['title'] ?? '') as String;
                final isSelected = widget.selected.contains(name);
                return InkWell(
                  onTap: () {
                    final next = Set<String>.from(widget.selected);
                    if (isSelected) {
                      next.remove(name);
                    } else {
                      next.add(name);
                    }
                    widget.onChanged(next);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 20,
                          color: isSelected
                              ? AppColors.brand600
                              : AppColors.secondary400,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            name,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.brand950,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

