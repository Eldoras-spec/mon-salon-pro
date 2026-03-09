import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/promotion_model.dart';
import '../providers/owner_providers.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

final _db = DatabaseService();

String _buildShareText(PromotionModel promo, String? slug) {
  final buf = StringBuffer();
  buf.writeln(promo.title);
  buf.writeln(promo.description);
  if (promo.discountPercent != null) {
    buf.writeln('-${promo.discountPercent!.toStringAsFixed(0)}% de réduction !');
  }
  if (promo.promoCode != null) {
    buf.writeln('Code promo : ${promo.promoCode}');
  }
  if (promo.expiresAt != null) {
    buf.writeln(
        "Valable jusqu'au ${promo.expiresAt!.day}/${promo.expiresAt!.month}/${promo.expiresAt!.year}");
  }
  if (slug != null && slug.isNotEmpty) {
    buf.writeln('\nRéservez maintenant : https://monsalon.web.app/s/$slug');
  }
  return buf.toString().trimRight();
}

Future<void> _sharePromo(PromotionModel promo, String? slug) async {
  final text = _buildShareText(promo, slug);
  await Share.share(text);
}

Future<void> _sharePromoWhatsApp(PromotionModel promo, String? slug) async {
  final text = _buildShareText(promo, slug);
  final encoded = Uri.encodeComponent(text);
  final url = Uri.parse('https://wa.me/?text=$encoded');
  if (await canLaunchUrl(url)) {
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }
}

void _showShareDialog(BuildContext context, PromotionModel promo, String? slug) {
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
            child: Text('Promotion créée !',
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
          const Text(
            'Souhaitez-vous partager cette offre ?',
            style: TextStyle(fontSize: 13, color: AppColors.secondary500),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _sharePromoWhatsApp(promo, slug);
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
                    _sharePromo(promo, slug);
                  },
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Partager'),
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

class OwnerPromotionsScreen extends ConsumerWidget {
  const OwnerPromotionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              'Offres & Promotions',
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
              child: Center(child: Text('Erreur: $e')),
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
                              label: 'Actives',
                              value: '$activeCount',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _PromoStat(
                              icon: Icons.inventory_2_outlined,
                              iconBg: const Color(0xFFF0FDF4),
                              iconColor: const Color(0xFF16A34A),
                              label: 'Total',
                              value: '${promos.length}',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Types section (tappable shortcuts)
                      Text(
                        'Créer une promotion',
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
                        title: 'Réduction en %',
                        desc: 'Ex : -20% sur les soins du visage',
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
                        icon: Icons.redeem_outlined,
                        iconBg: const Color(0xFFFDF4FF),
                        iconColor: const Color(0xFF9333EA),
                        title: 'Offre spéciale',
                        desc: 'Ex : 1 service acheté = 1 offert',
                        onTap: () {
                          final salon = salonAsync.value;
                          if (salon != null) {
                            _showAddPromoSheet(context, salon.id,
                                initialType: 'special',
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
                        title: 'Code promo',
                        desc: 'Créez un code réservé à vos clients fidèles',
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

                      // Promotions list
                      Text(
                        'Mes promotions',
                        style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 16),

                      if (promos.isEmpty)
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
                      else
                        ...promos.map((p) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 10),
                              child: _PromoTile(
                                promo: p,
                                slug: salonAsync.value?.slug,
                                onToggle: (val) =>
                                    _db.togglePromotionActive(p.id, val),
                                onDelete: () =>
                                    _confirmDelete(context, p.id),
                              ),
                            )),
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
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Supprimer cette promotion ?'),
        content: const Text('Elle ne sera plus visible par les clients.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Annuler')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Supprimer',
                  style: TextStyle(color: Colors.red))),
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
  late String _type;
  DateTime? _expiresAt;
  bool _saving = false;
  bool _allServices = true;
  final Set<String> _selectedServices = {};

  static const _typeLabels = {
    'percent': 'Réduction %',
    'special': 'Offre spéciale',
    'code': 'Code promo',
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

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    final desc = _descCtrl.text.trim();
    if (title.isEmpty || desc.isEmpty) return;

    double? percent;
    if (_type == 'percent') {
      percent = double.tryParse(
          _percentCtrl.text.replaceAll(',', '.'));
      if (percent == null || percent <= 0 || percent > 100) return;
    }

    String? code;
    if (_type == 'code') {
      code = _codeCtrl.text.trim().toUpperCase();
      if (code.isEmpty) return;
    }

    setState(() => _saving = true);
    try {
      // For percent type: null = all services, otherwise selected list
      List<String>? serviceNames;
      if (_type == 'percent' && !_allServices && _selectedServices.isNotEmpty) {
        serviceNames = _selectedServices.toList();
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
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 24, 20, 24 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nouvelle promotion',
                style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950)),
            const SizedBox(height: 20),

            // Type selector
            Row(
              children: _typeLabels.entries.map((e) {
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

            _PromoField(label: 'Titre', controller: _titleCtrl),
            const SizedBox(height: 12),
            _PromoField(
                label: 'Description',
                controller: _descCtrl,
                maxLines: 2),
            const SizedBox(height: 12),

            if (_type == 'percent') ...[
              _PromoField(
                label: 'Pourcentage de réduction (%)',
                controller: _percentCtrl,
                keyboard: const TextInputType.numberWithOptions(
                    decimal: true),
              ),
              const SizedBox(height: 12),

              // Service selection
              Text('Appliquer sur',
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary500,
                      fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  _ServiceToggle(
                    label: 'Tous les services',
                    selected: _allServices,
                    onTap: () => setState(() {
                      _allServices = true;
                      _selectedServices.clear();
                    }),
                  ),
                  const SizedBox(width: 8),
                  _ServiceToggle(
                    label: 'Services spécifiques',
                    selected: !_allServices,
                    onTap: () => setState(() => _allServices = false),
                  ),
                ],
              ),
              if (!_allServices && widget.services.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.services.map((s) {
                    final name = (s['name'] ?? s['title'] ?? '') as String;
                    final isSelected = _selectedServices.contains(name);
                    return GestureDetector(
                      onTap: () => setState(() {
                        if (isSelected) {
                          _selectedServices.remove(name);
                        } else {
                          _selectedServices.add(name);
                        }
                      }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.brand700
                              : AppColors.secondary50,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.brand700
                                : AppColors.secondary200,
                          ),
                        ),
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : AppColors.brand950,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              if (!_allServices && widget.services.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Aucun service configuré dans votre salon.',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.secondary400),
                  ),
                ),
              const SizedBox(height: 12),
            ],

            if (_type == 'code') ...[
              _PromoField(
                label: 'Code promo (ex: BIENVENUE20)',
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
                          ? "Date d'expiration (optionnel)"
                          : 'Expire le ${_expiresAt!.day}/${_expiresAt!.month}/${_expiresAt!.year}',
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
                    : const Text('Publier',
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
    'special': Icons.redeem_outlined,
    'code': Icons.confirmation_number_outlined,
  };
  static const _typeBg = {
    'percent': Color(0xFFEFF6FF),
    'special': Color(0xFFFDF4FF),
    'code': Color(0xFFFFF7ED),
  };
  static const _typeColor = {
    'percent': Color(0xFF2563EB),
    'special': Color(0xFF9333EA),
    'code': Color(0xFFEA580C),
  };

  @override
  Widget build(BuildContext context) {
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
                      const _Badge(
                          label: 'IA',
                          color: Color(0xFF8B5CF6)),
                    if (promo.isAiGenerated) const SizedBox(width: 4),
                    if (isExpired)
                      _Badge(
                          label: 'Expirée',
                          color: AppColors.secondary300)
                    else if (promo.isActive)
                      _Badge(
                          label: 'Active',
                          color: const Color(0xFF16A34A)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(promo.description,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary400),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                if (promo.targetedClientName != null) ...[
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded,
                          size: 12, color: Color(0xFF8B5CF6)),
                      const SizedBox(width: 4),
                      Text(
                        'Pour ${promo.targetedClientName}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8B5CF6),
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
                if (promo.expiresAt != null && !isExpired) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Expire le ${promo.expiresAt!.day}/${promo.expiresAt!.month}/${promo.expiresAt!.year}',
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
              const SizedBox(height: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.share_rounded,
                        size: 17, color: AppColors.brand400),
                    onPressed: () => _sharePromo(promo, slug),
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
            'Aucune promotion créée',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Créez des offres attractives pour fidéliser\nvos clients et attirer de nouvelles réservations.',
            style: TextStyle(
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
            label: const Text('Créer une promotion'),
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
