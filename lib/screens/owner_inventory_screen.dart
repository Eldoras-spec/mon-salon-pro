import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/inventory_model.dart';
import '../models/product_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import 'owner_boutique_screen.dart';
import '../utils/currency_helper.dart';

final _db = DatabaseService();

class OwnerInventoryScreen extends ConsumerWidget {
  const OwnerInventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);
    final inventoryAsync = ref.watch(ownerInventoryProvider);

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
              l?.tr('inventory_title') ?? 'Stock & Produits',
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
                  final salonId = salonAsync.value?.id;
                  if (salonId != null) {
                    _showAddItemSheet(context, salonId);
                  }
                },
              ),
              const SizedBox(width: 8),
            ],
          ),

          inventoryAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e')),
            ),
            data: (items) {
              final lowCount = items.where((i) => i.isLow).length;
              return SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Summary cards
                      Row(
                        children: [
                          Expanded(
                            child: _SummaryCard(
                              icon: Icons.inventory_2_outlined,
                              iconBg: AppColors.brand50,
                              iconColor: AppColors.brand600,
                              label: l?.tr('inventory_products_tab') ?? 'Produits',
                              value: '${items.length}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SummaryCard(
                              icon: Icons.warning_amber_rounded,
                              iconBg: const Color(0xFFFEF3C7),
                              iconColor: const Color(0xFFD97706),
                              label: l?.tr('inventory_low_stock_tab') ?? 'Stock faible',
                              value: '$lowCount',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      if (items.isEmpty)
                        _EmptySection(
                          icon: Icons.inventory_2_outlined,
                          title: l?.tr('inventory_empty_title') ?? 'Aucun produit ajouté',
                          subtitle: l?.tr('inventory_empty_subtitle') ??
                              'Gérez vos produits et consommables en ajoutant des articles à votre inventaire.',
                          actionLabel: l?.tr('inventory_add_product') ?? 'Ajouter un produit',
                          onAction: () {
                            final salonId = salonAsync.value?.id;
                            if (salonId != null) {
                              _showAddItemSheet(context, salonId);
                            }
                          },
                        )
                      else ...[
                        Text(
                          l?.tr('inventory_section_title') ?? 'Inventaire',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                          ),
                        ),
                        const SizedBox(height: 12),
                        ...items.map((item) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _InventoryTile(
                                item: item,
                                onEdit: () =>
                                    _showEditQuantitySheet(context, item),
                                onDelete: () =>
                                    _confirmDelete(context, item.id),
                              ),
                            )),
                        const SizedBox(height: 24),
                      ],

                      // Boutique products section
                      _BoutiqueStockSection(),
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

  void _showAddItemSheet(BuildContext context, String salonId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddItemSheet(salonId: salonId),
    );
  }

  void _showEditQuantitySheet(BuildContext context, InventoryModel item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _EditQuantitySheet(item: item),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String id) async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('inventory_delete_title') ?? 'Supprimer ce produit ?'),
        content: Text(l?.tr('inventory_delete_message') ?? 'Cette action est irréversible.'),
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
      await _db.deleteInventoryItem(id);
    }
  }
}

// ── Add Item Sheet ─────────────────────────────────────────────────────────

class _AddItemSheet extends StatefulWidget {
  const _AddItemSheet({required this.salonId});
  final String salonId;

  @override
  State<_AddItemSheet> createState() => _AddItemSheetState();
}

class _AddItemSheetState extends State<_AddItemSheet> {
  final _nameCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _minCtrl = TextEditingController(text: '2');
  final _priceCtrl = TextEditingController();
  String _category = 'Produit';
  String _unit = 'unité';
  bool _saving = false;

  final _categories = ['Produit', 'Consommable', 'Équipement'];
  final _units = ['unité', 'ml', 'L', 'g', 'kg'];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _qtyCtrl.dispose();
    _minCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final min = int.tryParse(_minCtrl.text) ?? 2;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.'));

    setState(() => _saving = true);
    try {
      await _db.addInventoryItem(InventoryModel(
        id: '',
        salonId: widget.salonId,
        name: name,
        category: _category,
        quantity: qty,
        minQuantity: min,
        unit: _unit,
        price: price,
        createdAt: DateTime.now(),
      ));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('❌ addInventoryItem error: $e');
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e'), backgroundColor: Colors.redAccent),
        );
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l?.tr('inventory_add_product') ?? 'Ajouter un produit',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 20),
          _Field(label: l?.tr('inventory_product_name') ?? 'Nom du produit', controller: _nameCtrl),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l?.tr('inventory_category') ?? 'Catégorie',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary500,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    _DropdownField<String>(
                      value: _category,
                      items: _categories,
                      onChanged: (v) => setState(() => _category = v!),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l?.tr('inventory_unit') ?? 'Unité',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary500,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 6),
                    _DropdownField<String>(
                      value: _unit,
                      items: _units,
                      onChanged: (v) => setState(() => _unit = v!),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _Field(
                    label: l?.tr('inventory_quantity') ?? 'Quantité',
                    controller: _qtyCtrl,
                    keyboard: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
            const SizedBox(width: 12),
            Expanded(
                child: _Field(
                    label: l?.tr('inventory_alert_threshold') ?? 'Alerte stock (min)',
                    controller: _minCtrl,
                    keyboard: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
          ]),
          const SizedBox(height: 14),
          _Field(
              label: l?.tr('inventory_unit_price') ?? 'Prix unitaire (MAD, optionnel)',
              controller: _priceCtrl,
              keyboard:
                  const TextInputType.numberWithOptions(decimal: true)),
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
                      child:
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text(l?.tr('common_add') ?? 'Ajouter',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Edit Quantity Sheet ────────────────────────────────────────────────────

class _EditQuantitySheet extends StatefulWidget {
  const _EditQuantitySheet({required this.item});
  final InventoryModel item;

  @override
  State<_EditQuantitySheet> createState() => _EditQuantitySheetState();
}

class _EditQuantitySheetState extends State<_EditQuantitySheet> {
  late final TextEditingController _qtyCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl =
        TextEditingController(text: widget.item.quantity.toString());
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = int.tryParse(_qtyCtrl.text);
    if (qty == null) return;
    setState(() => _saving = true);
    try {
      await _db.updateInventoryItem(widget.item.id, {'quantity': qty});
      if (mounted) Navigator.pop(context);
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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l?.tr('inventory_edit_stock') ?? 'Modifier le stock',
              style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 4),
          Text(widget.item.name,
              style: const TextStyle(
                  color: AppColors.secondary500, fontSize: 13)),
          const SizedBox(height: 20),
          _Field(
            label: '${l?.tr('inventory_new_quantity') ?? 'Nouvelle quantité'} (${widget.item.unit})',
            controller: _qtyCtrl,
            keyboard: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
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
                padding: const EdgeInsets.symmetric(vertical: 14),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(l?.tr('common_save') ?? 'Enregistrer',
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Inventory Tile ─────────────────────────────────────────────────────────

class _InventoryTile extends StatelessWidget {
  const _InventoryTile({
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });
  final InventoryModel item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isLow = item.isLow;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isLow
                ? const Color(0xFFFEF3C7)
                : AppColors.secondary100),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isLow
                  ? const Color(0xFFFEF3C7)
                  : AppColors.brand50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.inventory_2_outlined,
              color: isLow
                  ? const Color(0xFFD97706)
                  : AppColors.brand600,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: AppColors.brand950,
                    )),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text('${item.quantity} ${item.unit}',
                        style: TextStyle(
                            fontSize: 12,
                            color: isLow
                                ? const Color(0xFFD97706)
                                : AppColors.secondary500,
                            fontWeight: isLow
                                ? FontWeight.w600
                                : FontWeight.normal)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.secondary100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(item.category,
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary500)),
                    ),
                    if (isLow) ...[
                      const SizedBox(width: 6),
                      const Icon(Icons.warning_amber_rounded,
                          size: 14, color: Color(0xFFD97706)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 18, color: AppColors.secondary400),
            onPressed: onEdit,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
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

// ── Shared Widgets ─────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
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
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.secondary500),
          ),
        ],
      ),
    );
  }
}

class _EmptySection extends StatelessWidget {
  const _EmptySection({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.secondary50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 30, color: AppColors.secondary300),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondary400,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand700,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 12),
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

class _Field extends StatelessWidget {
  const _Field({
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
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.value,
    required this.items,
    required this.onChanged,
  });
  final T value;
  final List<T> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          style: const TextStyle(
              fontSize: 14, color: AppColors.brand950),
          items: items
              .map((e) => DropdownMenuItem<T>(
                    value: e,
                    child: Text(e.toString()),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─── Boutique Products in Stock View ─────────────────────────────────────────

class _BoutiqueStockSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final productsAsync = ref.watch(ownerProductsProvider);

    return productsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (products) {
        if (products.isEmpty) return const SizedBox.shrink();

        final lowStock = products.where((p) => p.isLowStock).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l?.tr('inventory_boutique_products') ?? 'Produits Boutique',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const OwnerBoutiqueScreen()),
                  ),
                  child: Text(l?.tr('inventory_see_all') ?? 'Voir tout',
                      style: const TextStyle(fontSize: 13)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (lowStock.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFECACA)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFDC2626), size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${lowStock.length} produit${lowStock.length > 1 ? 's' : ''} en stock bas',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFDC2626)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            ...products.take(5).map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondary100),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: p.images.isNotEmpty
                            ? Image.network(p.images.first,
                                width: 44, height: 44, fit: BoxFit.cover)
                            : Container(
                                width: 44,
                                height: 44,
                                color: AppColors.brand50,
                                child: const Icon(Icons.image_outlined,
                                    color: AppColors.brand300, size: 20),
                              ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            Text(CurrencyHelper.format(p.price),
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.brand600)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: p.isLowStock
                              ? const Color(0xFFFEF2F2)
                              : const Color(0xFFF0FDF4),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${p.stock}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: p.isLowStock
                                ? const Color(0xFFDC2626)
                                : const Color(0xFF16A34A),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }
}
