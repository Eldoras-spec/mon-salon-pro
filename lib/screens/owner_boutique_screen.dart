import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

import '../models/product_model.dart';
import '../models/order_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';
import '../utils/media_compressor.dart';

final _db = DatabaseService();

class OwnerBoutiqueScreen extends ConsumerStatefulWidget {
  /// Initial tab to land on. 0 = Produits, 1 = Commandes. Used by the
  /// dashboard "X commandes à confirmer" shortcut so the owner doesn't
  /// land on Produits and have to swipe over.
  final int initialTab;
  const OwnerBoutiqueScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<OwnerBoutiqueScreen> createState() =>
      _OwnerBoutiqueScreenState();
}

class _OwnerBoutiqueScreenState extends ConsumerState<OwnerBoutiqueScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.brand950, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l?.tr('boutique_title') ?? 'Boutique',
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
            onPressed: () => _showProductForm(context),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: AppColors.brand600,
          unselectedLabelColor: AppColors.secondary400,
          indicatorColor: AppColors.brand600,
          indicatorWeight: 2.5,
          labelStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w600, fontSize: 14),
          unselectedLabelStyle:
              GoogleFonts.dmSans(fontWeight: FontWeight.w500, fontSize: 14),
          tabs: [
            Tab(text: l?.tr('boutique_products_tab') ?? 'Produits'),
            Tab(text: l?.tr('boutique_orders_tab') ?? 'Commandes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          _ProductsTab(),
          _OrdersTab(),
        ],
      ),
    );
  }

  void _showProductForm(BuildContext context, {ProductModel? product}) {
    final salon = ref.read(ownerSalonProvider).value;
    if (salon == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ProductFormSheet(
        salonId: salon.id,
        currency: salon.currency,
        product: product,
      ),
    );
  }
}

// ─── Products Tab ────────────────────────────────────────────────────────────

class _ProductsTab extends ConsumerWidget {
  const _ProductsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(ownerProductsProvider);

    final l = AppLocalizations.of(context);
    return productsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e')),
      data: (products) {
        if (products.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storefront_outlined,
                    size: 64, color: AppColors.secondary300),
                const SizedBox(height: 16),
                Text(
                  l?.tr('boutique_no_products') ?? 'Aucun produit',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary400,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l?.tr('boutique_no_products_hint') ?? 'Ajoutez des produits pour créer votre boutique',
                  style: TextStyle(
                      fontSize: 14, color: AppColors.secondary400),
                ),
              ],
            ),
          );
        }

        // Group by category
        final categories = <String>{};
        for (final p in products) {
          categories.add(p.category);
        }

        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            // Stats
            Row(
              children: [
                _StatCard(
                  icon: Icons.inventory_2_outlined,
                  label: l?.tr('boutique_products_tab') ?? 'Produits',
                  value: '${products.length}',
                  color: AppColors.brand600,
                ),
                const SizedBox(width: 12),
                _StatCard(
                  icon: Icons.warning_amber_rounded,
                  label: l?.tr('boutique_low_stock') ?? 'Stock bas',
                  value:
                      '${products.where((p) => p.isLowStock).length}',
                  color: const Color(0xFFEA580C),
                ),
              ],
            ),
            const SizedBox(height: 24),

            for (final cat in categories) ...[
              Text(
                cat,
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 12),
              ...products
                  .where((p) => p.category == cat)
                  .map((p) => _ProductCard(product: p)),
              const SizedBox(height: 16),
            ],
          ],
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  const _StatCard(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
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
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: GoogleFonts.dmSans(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950)),
                Text(label,
                    style: TextStyle(
                        fontSize: 12, color: AppColors.secondary400)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductCard extends ConsumerWidget {
  final ProductModel product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _handleAction(context, ref, 'edit'),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: product.images.isNotEmpty
                ? Image.network(product.images.first,
                    width: 60, height: 60, fit: BoxFit.cover)
                : Container(
                    width: 60,
                    height: 60,
                    color: AppColors.brand50,
                    child: const Icon(Icons.image_outlined,
                        color: AppColors.brand300),
                  ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950)),
                const SizedBox(height: 2),
                Text(CurrencyHelper.format(product.price, ref.read(ownerSalonProvider).value?.currency ?? 'MAD'),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand600)),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: product.isLowStock
                            ? const Color(0xFFFEF2F2)
                            : const Color(0xFFF0FDF4),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (l?.tr('boutique_stock') ?? 'Stock: {count}').replaceAll('{count}', '${product.stock}'),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: product.isLowStock
                              ? const Color(0xFFDC2626)
                              : const Color(0xFF16A34A),
                        ),
                      ),
                    ),
                    if (!product.isActive) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.secondary100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(l?.tr('boutique_inactive') ?? 'Inactif',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.secondary500)),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Actions
          PopupMenuButton<String>(
            // Stops the InkWell tap from racing the menu open.
            onOpened: () {},
            icon: const Icon(Icons.more_vert_rounded,
                color: AppColors.secondary400, size: 20),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            onSelected: (val) =>
                _handleAction(context, ref, val),
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'edit',
                  child: Row(children: [
                    Icon(Icons.edit_outlined, size: 18),
                    SizedBox(width: 8),
                    Text(l?.tr('boutique_edit') ?? 'Modifier')
                  ])),
              PopupMenuItem(
                  value: 'toggle',
                  child: Row(children: [
                    Icon(
                        product.isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 18),
                    const SizedBox(width: 8),
                    Text(product.isActive ? (l?.tr('boutique_deactivate') ?? 'Désactiver') : (l?.tr('boutique_activate') ?? 'Activer'))
                  ])),
              PopupMenuItem(
                  value: 'delete',
                  child: Row(children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text(l?.tr('boutique_delete') ?? 'Supprimer',
                        style: TextStyle(color: Colors.red))
                  ])),
            ],
          ),
        ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleAction(BuildContext context, WidgetRef ref, String action) {
    switch (action) {
      case 'edit':
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _ProductFormSheet(
            salonId: product.salonId,
            product: product,
          ),
        );
        break;
      case 'toggle':
        _db.updateProduct(product.id, {'isActive': !product.isActive});
        break;
      case 'delete':
        final l = AppLocalizations.of(context);
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: Text(l?.tr('boutique_delete_title') ?? 'Supprimer ce produit ?'),
            content: Text((l?.tr('boutique_delete_message') ?? '{name} sera supprimé définitivement.').replaceAll('{name}', product.name)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l?.tr('common_cancel') ?? 'Annuler'),
              ),
              TextButton(
                onPressed: () {
                  // Delete product images from Storage
                  for (final url in product.images) {
                    try { FirebaseStorage.instance.refFromURL(url).delete(); } catch (_) {}
                  }
                  _db.deleteProduct(product.id);
                  Navigator.pop(ctx);
                },
                child: Text(l?.tr('common_delete') ?? 'Supprimer',
                    style: const TextStyle(color: Colors.red)),
              ),
            ],
          ),
        );
        break;
    }
  }
}

// ─── Product Form Sheet ──────────────────────────────────────────────────────

class _ProductFormSheet extends StatefulWidget {
  final String salonId;
  final String currency;
  final ProductModel? product;
  const _ProductFormSheet({
    required this.salonId,
    this.currency = 'MAD',
    this.product,
  });

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _priceCtrl;
  late TextEditingController _stockCtrl;
  late TextEditingController _thresholdCtrl;
  late TextEditingController _categoryCtrl;
  late TextEditingController _citiesCtrl;
  late TextEditingController _feeCtrl;
  late TextEditingController _daysCtrl;
  String _deliveryType = 'pickup';
  // 'card' | 'cod' | 'both'. Only surfaced in UI when delivery enabled AND
  // salon has Stripe Connect chargesEnabled. Persisted regardless.
  String _paymentOptions = 'both';
  bool _isActive = true;
  List<String> _imageUrls = [];
  List<File> _newImages = [];
  bool _saving = false;

  final _categories = [
    'Cheveux',
    'Visage',
    'Corps',
    'Ongles',
    'Accessoires',
    'Autre',
  ];

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _nameCtrl = TextEditingController(text: p?.name ?? '');
    _descCtrl = TextEditingController(text: p?.description ?? '');
    _priceCtrl =
        TextEditingController(text: p != null ? p.price.toStringAsFixed(0) : '');
    _stockCtrl =
        TextEditingController(text: p != null ? '${p.stock}' : '');
    _thresholdCtrl = TextEditingController(
        text: p != null ? '${p.lowStockThreshold}' : '5');
    _categoryCtrl =
        TextEditingController(text: p?.category ?? _categories.first);
    _deliveryType = p?.deliveryType ?? 'pickup';
    _paymentOptions = p?.paymentOptions ?? 'both';
    _citiesCtrl = TextEditingController(text: p?.deliveryCities.join(', ') ?? '');
    _feeCtrl = TextEditingController(
        text: p != null && p.deliveryFee > 0
            ? p.deliveryFee.toStringAsFixed(0)
            : '');
    _daysCtrl = TextEditingController(
        text: p != null && p.deliveryDays > 0 ? '${p.deliveryDays}' : '');
    _isActive = p?.isActive ?? true;
    _imageUrls = List.from(p?.images ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _priceCtrl.dispose();
    _stockCtrl.dispose();
    _thresholdCtrl.dispose();
    _categoryCtrl.dispose();
    _citiesCtrl.dispose();
    _feeCtrl.dispose();
    _daysCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_imageUrls.length + _newImages.length >= 3) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('boutique_photos_max') ?? 'Maximum 3 photos')),
      );
      return;
    }
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    // Compress
    if (!mounted) return;
    final compressOverlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
    final result = await MediaCompressor.compressImage(File(picked.path));
    compressOverlay.remove();
    if (!mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
      return;
    }
    if (result.compressedSize > MediaCompressor.maxImageSizeBytes) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: true);
      return;
    }
    setState(() => _newImages.add(result.file));
  }

  Future<List<String>> _uploadImages() async {
    final urls = <String>[];
    final storage = FirebaseStorage.instance;
    for (final file in _newImages) {
      final ref = storage.ref(
          'products/${widget.salonId}/${DateTime.now().millisecondsSinceEpoch}_${urls.length}.jpg');
      await ref.putFile(
        file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final uploadedUrls = await _uploadImages();
      final allImages = [..._imageUrls, ...uploadedUrls];

      final data = {
        'salonId': widget.salonId,
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        'price': double.parse(_priceCtrl.text.trim()),
        'images': allImages,
        'category': _categoryCtrl.text.trim(),
        'stock': int.parse(_stockCtrl.text.trim()),
        'lowStockThreshold': int.parse(_thresholdCtrl.text.trim()),
        'deliveryType': _deliveryType,
        'deliveryCities': _deliveryType == 'cities'
            ? _citiesCtrl.text.trim().split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()
            : <String>[],
        'deliveryFee': _feeCtrl.text.trim().isEmpty
            ? 0.0
            : double.parse(_feeCtrl.text.trim()),
        'deliveryDays': _daysCtrl.text.trim().isEmpty
            ? 0
            : (int.tryParse(_daysCtrl.text.trim()) ?? 0),
        // 'pickup' implies COD at the salon — payment options are irrelevant.
        // For delivery products we persist the salon's chosen options.
        'paymentOptions': _deliveryType == 'pickup' ? 'cod' : _paymentOptions,
        'isActive': _isActive,
      };

      if (widget.product != null) {
        await _db.updateProduct(widget.product!.id, data);
      } else {
        data['createdAt'] = DateTime.now();
        await _db.addProduct(ProductModel(
          id: '',
          salonId: widget.salonId,
          name: data['name'] as String,
          description: data['description'] as String,
          price: data['price'] as double,
          images: allImages,
          category: data['category'] as String,
          stock: data['stock'] as int,
          lowStockThreshold: data['lowStockThreshold'] as int,
          deliveryType: data['deliveryType'] as String,
          deliveryCities: List<String>.from(data['deliveryCities'] as List),
          deliveryFee: data['deliveryFee'] as double,
          deliveryDays: data['deliveryDays'] as int,
          paymentOptions: data['paymentOptions'] as String,
          isActive: _isActive,
          createdAt: DateTime.now(),
        ));
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final isEdit = widget.product != null;
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final sheetHeight = screenHeight * 0.92;
    // Wrap in Padding(viewInsets) so the keyboard pushes the entire sheet
    // up — keeps the save button visible. Earlier we tried shrinking the
    // sheet height (sheetHeight - viewInsets) but that only resized the
    // box without lifting it above the keyboard, so the bottom content
    // still ended up hidden.
    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets),
      child: AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2)),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isEdit ? (l?.tr('boutique_edit_product') ?? 'Modifier le produit') : (l?.tr('boutique_new_product') ?? 'Nouveau produit'),
                    style: GoogleFonts.dmSans(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded,
                      color: AppColors.secondary400),
                ),
              ],
            ),
          ),
          const Divider(),
          // Form
          Expanded(
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Images
                  Text(l?.tr('boutique_photos') ?? 'Photos (max 3)',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 90,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        // Existing images
                        ..._imageUrls.map((url) => _ImageTile(
                              imageUrl: url,
                              onRemove: () =>
                                  setState(() => _imageUrls.remove(url)),
                            )),
                        // New images
                        ..._newImages.map((file) => _ImageTile(
                              file: file,
                              onRemove: () =>
                                  setState(() => _newImages.remove(file)),
                            )),
                        // Add button
                        if (_imageUrls.length + _newImages.length < 3)
                          GestureDetector(
                            onTap: _pickImage,
                            child: Container(
                              width: 80,
                              height: 80,
                              margin: const EdgeInsets.only(right: 8),
                              decoration: BoxDecoration(
                                border: Border.all(
                                    color: AppColors.secondary200,
                                    style: BorderStyle.solid),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(Icons.add_photo_alternate_outlined,
                                  color: AppColors.secondary400),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  _buildField(l?.tr('boutique_product_name') ?? 'Nom du produit', _nameCtrl, required: true),
                  _buildField(l?.tr('boutique_description') ?? 'Description', _descCtrl, maxLines: 2),
                  _buildField(l?.tr('boutique_price') ?? 'Prix (${widget.currency})', _priceCtrl,
                      required: true, keyboard: TextInputType.number),
                  _buildField(
                      l?.tr('boutique_delivery_days') ??
                          'Délai de livraison (jours)',
                      _daysCtrl,
                      keyboard: TextInputType.number),

                  // Category dropdown
                  Text(l?.tr('inventory_category') ?? 'Catégorie',
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary500)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: _categories.contains(_categoryCtrl.text)
                        ? _categoryCtrl.text
                        : _categories.first,
                    decoration: _inputDecoration(),
                    items: _categories
                        .map((c) =>
                            DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (v) => _categoryCtrl.text = v ?? '',
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                          child: _buildField(l?.tr('boutique_stock_label') ?? 'Stock', _stockCtrl,
                              required: true,
                              keyboard: TextInputType.number)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: _buildField(
                              l?.tr('boutique_alert_threshold') ?? 'Seuil alerte', _thresholdCtrl,
                              keyboard: TextInputType.number)),
                    ],
                  ),

                  const Divider(height: 32),
                  Text(l?.tr('boutique_delivery') ?? 'Livraison',
                      style: GoogleFonts.dmSans(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950)),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: _deliveryType,
                    decoration: InputDecoration(
                      hintText: 'Mode de livraison',
                      filled: true,
                      fillColor: AppColors.brand50,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                    ),
                    items: [
                      DropdownMenuItem(
                          value: 'pickup',
                          child: Text(AppLocalizations.of(context)?.tr('boutique_delivery_pickup') ?? 'Retrait en magasin uniquement')),
                      DropdownMenuItem(
                          value: 'national',
                          child: Text(AppLocalizations.of(context)?.tr('boutique_delivery_national') ?? 'Livraison dans tout le pays')),
                      DropdownMenuItem(
                          value: 'cities',
                          child: Text(AppLocalizations.of(context)?.tr('boutique_delivery_cities') ?? 'Livraison par ville')),
                    ],
                    onChanged: (v) => setState(() => _deliveryType = v ?? 'pickup'),
                  ),
                  const SizedBox(height: 16),
                  if (_deliveryType == 'cities') ...[
                    const SizedBox(height: 12),
                    _buildField('Villes de livraison', _citiesCtrl,
                        hint: 'ex: Casablanca, Rabat, Marrakech...'),
                  ],
                  if (_deliveryType != 'pickup')
                    _buildField('Frais de livraison (${widget.currency})', _feeCtrl,
                        keyboard: TextInputType.number, hint: '0 = gratuit'),

                  // Payment method picker — only when delivery active AND
                  // the salon can actually accept card payments. For pickup
                  // products we always implicitly charge cash at the salon.
                  if (_deliveryType != 'pickup')
                    StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('salons')
                          .doc(widget.salonId)
                          .snapshots(),
                      builder: (context, snap) {
                        final data = snap.data?.data() ?? {};
                        final raw = data['stripeConnect'];
                        final connect = raw is Map
                            ? Map<String, dynamic>.from(raw)
                            : <String, dynamic>{};
                        final chargesEnabled = connect['chargesEnabled'] == true;
                        if (!chargesEnabled) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l?.tr('boutique_payment_label') ?? 'Mode de paiement accepté',
                                style: const TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              DropdownButtonFormField<String>(
                                value: _paymentOptions == 'cod'
                                    ? 'cod'
                                    : (_paymentOptions == 'card' ? 'card' : 'both'),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: AppColors.brand50,
                                  border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 14),
                                ),
                                items: [
                                  DropdownMenuItem(
                                      value: 'both',
                                      child: Text(l?.tr('boutique_payment_both') ?? 'Carte ou à la livraison')),
                                  DropdownMenuItem(
                                      value: 'card',
                                      child: Text(l?.tr('boutique_payment_card') ?? 'Carte bancaire uniquement')),
                                  DropdownMenuItem(
                                      value: 'cod',
                                      child: Text(l?.tr('boutique_payment_cod') ?? 'Paiement à la livraison uniquement')),
                                ],
                                onChanged: (v) =>
                                    setState(() => _paymentOptions = v ?? 'both'),
                              ),
                            ],
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 16),
                  SwitchListTile(
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v),
                    title: Text(l?.tr('boutique_active_product') ?? 'Produit actif',
                        style: const TextStyle(fontSize: 14)),
                    subtitle: Text(
                        l?.tr('boutique_visible_to_clients') ?? 'Visible par les clients',
                        style: const TextStyle(fontSize: 12)),
                    activeColor: AppColors.brand600,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
          // Save button — bottom padding: safe-area when keyboard closed, 12 when open
          Padding(
            padding: EdgeInsets.fromLTRB(
                20,
                8,
                20,
                viewInsets > 0
                    ? 12
                    : MediaQuery.of(context).padding.bottom + 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? (l?.tr('boutique_save') ?? 'Enregistrer') : (l?.tr('boutique_add_product') ?? 'Ajouter le produit'),
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController ctrl,
      {bool required = false,
      TextInputType? keyboard,
      int maxLines = 1,
      String? hint}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.secondary500)),
        const SizedBox(height: 6),
        TextFormField(
          controller: ctrl,
          keyboardType: keyboard,
          maxLines: maxLines,
          decoration: _inputDecoration(hint: hint),
          validator: required
              ? (v) => (v == null || v.trim().isEmpty) ? (AppLocalizations.of(context)?.tr('common_required') ?? 'Requis') : null
              : null,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  InputDecoration _inputDecoration({String? hint}) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: AppColors.secondary50,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.secondary200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.secondary200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.brand400)),
      );
}

class _ImageTile extends StatelessWidget {
  final String? imageUrl;
  final File? file;
  final VoidCallback onRemove;
  const _ImageTile({this.imageUrl, this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 80,
          height: 80,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            image: DecorationImage(
              image: imageUrl != null
                  ? NetworkImage(imageUrl!) as ImageProvider
                  : FileImage(file!),
              fit: BoxFit.cover,
            ),
          ),
        ),
        Positioned(
          top: 2,
          right: 10,
          child: GestureDetector(
            onTap: onRemove,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: const BoxDecoration(
                  color: Colors.red, shape: BoxShape.circle),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
      ],
    );
  }
}

// ─── Orders Tab ──────────────────────────────────────────────────────────────

enum _OrdersFilter { twoWeeks, month, threeMonths, all }

DateTime? _filterCutoff(_OrdersFilter f) {
  final now = DateTime.now();
  switch (f) {
    case _OrdersFilter.twoWeeks:
      return now.subtract(const Duration(days: 14));
    case _OrdersFilter.month:
      return now.subtract(const Duration(days: 30));
    case _OrdersFilter.threeMonths:
      return now.subtract(const Duration(days: 90));
    case _OrdersFilter.all:
      return null;
  }
}

class _OrdersTab extends ConsumerStatefulWidget {
  const _OrdersTab();

  @override
  ConsumerState<_OrdersTab> createState() => _OrdersTabState();
}

class _OrdersTabState extends ConsumerState<_OrdersTab> {
  _OrdersFilter _filter = _OrdersFilter.twoWeeks;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Strip every non-digit then drop a single leading 0 so the local
  /// format ("0625111667") matches the stored E.164 form ("+212625111667").
  /// Country codes longer than 1 digit aren't stripped here — the
  /// `endsWith` check below absorbs them by matching the trailing digits.
  String _normalizeDigits(String s) {
    final digits = s.replaceAll(RegExp(r'\D'), '');
    return digits.startsWith('0') ? digits.substring(1) : digits;
  }

  /// Lowercased substring match on client name, phone (digits-only), and
  /// item names. Returns true when the query is empty so the search field
  /// doesn't gate the list when idle.
  bool _matchesSearch(OrderModel o) {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    if (o.clientName.toLowerCase().contains(q)) return true;
    final qDigits = _normalizeDigits(q);
    if (qDigits.isNotEmpty) {
      final phoneDigits = _normalizeDigits(o.clientPhone);
      if (phoneDigits.endsWith(qDigits) || phoneDigits.contains(qDigits)) {
        return true;
      }
    }
    for (final item in o.items) {
      if (item.name.toLowerCase().contains(q)) return true;
    }
    return false;
  }

  String _filterLabel(AppLocalizations? l, _OrdersFilter f) {
    switch (f) {
      case _OrdersFilter.twoWeeks:
        return l?.tr('boutique_filter_2weeks') ?? '2 dernières semaines';
      case _OrdersFilter.month:
        return l?.tr('boutique_filter_month') ?? 'Ce mois';
      case _OrdersFilter.threeMonths:
        return l?.tr('boutique_filter_3months') ?? '3 derniers mois';
      case _OrdersFilter.all:
        return l?.tr('boutique_filter_all') ?? 'Toutes les commandes';
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final ordersAsync = ref.watch(ownerOrdersProvider);

    return ordersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e')),
      data: (orders) {
        // Server-side filter via ownerOrdersCutoffProvider — the stream
        // already only returns docs within the window. The search query
        // is the only client-side narrowing on top.
        final filtered = _searchQuery.trim().isEmpty
            ? orders
            : orders.where(_matchesSearch).toList();

        return Column(
          children: [
            // Search row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: TextField(
                controller: _searchCtrl,
                onChanged: (v) => setState(() => _searchQuery = v),
                decoration: InputDecoration(
                  hintText: l?.tr('boutique_orders_search_hint') ??
                      'Rechercher : client, téléphone, produit…',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true,
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.secondary200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.secondary200),
                  ),
                  suffixIcon: _searchQuery.isEmpty
                      ? null
                      : IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _searchQuery = '');
                          },
                        ),
                ),
              ),
            ),
            // Filter row
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<_OrdersFilter>(
                      value: _filter,
                      isDense: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.secondary200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: AppColors.secondary200),
                        ),
                      ),
                      items: _OrdersFilter.values
                          .map((f) => DropdownMenuItem(
                                value: f,
                                child: Text(_filterLabel(l, f),
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        setState(() => _filter = v);
                        // Re-subscribe the Firestore stream to the new window.
                        ref.read(ownerOrdersCutoffProvider.notifier).state =
                            _filterCutoff(v);
                      },
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 64, color: AppColors.secondary300),
                          const SizedBox(height: 16),
                          Text(
                            l?.tr('boutique_no_orders') ?? 'Aucune commande',
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary400,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _OrderCard(
                          order: filtered[i],
                          currency: ref
                                  .read(ownerSalonProvider)
                                  .value
                                  ?.currency ??
                              'MAD'),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _OrderCard extends StatelessWidget {
  final OrderModel order;
  final String currency;
  const _OrderCard({required this.order, this.currency = 'MAD'});

  /// Effective status for display: legacy paid-pending orders (created
  /// before the webhook auto-confirms paid card orders) are presented as
  /// "Confirmée" so the owner doesn't see a misleading "En attente" badge.
  String get _effectiveStatus {
    if (order.status == 'pending' && order.paymentStatus == 'paid') {
      return 'confirmed';
    }
    return order.status;
  }

  Color get _statusColor {
    switch (_effectiveStatus) {
      case 'pending':
        return const Color(0xFFF59E0B);
      case 'confirmed':
        return AppColors.brand600;
      case 'delivered':
        return const Color(0xFF16A34A);
      case 'cancelled':
        return const Color(0xFFDC2626);
      default:
        return AppColors.secondary400;
    }
  }

  String _statusLabelLocalized(AppLocalizations? l) {
    switch (_effectiveStatus) {
      case 'pending':
        return l?.tr('boutique_status_pending') ?? 'En attente';
      case 'confirmed':
        return l?.tr('boutique_status_confirmed') ?? 'Confirmée';
      case 'delivered':
        // Pickup orders are "récupérées" by the client, not "livrées".
        return order.deliveryMethod == 'pickup'
            ? (l?.tr('boutique_status_picked_up') ?? 'Récupérée')
            : (l?.tr('boutique_status_delivered') ?? 'Livrée');
      case 'cancelled':
        return l?.tr('boutique_status_cancelled') ?? 'Annulée';
      default:
        return order.statusLabel;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(order.clientName,
                        style: GoogleFonts.dmSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand950)),
                    const SizedBox(height: 2),
                    Text(
                      '${order.createdAt.day}/${order.createdAt.month}/${order.createdAt.year}',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.secondary400),
                    ),
                    const SizedBox(height: 6),
                    // Delivery + payment pills. Two pills side by side so the
                    // owner gets the answer to both "where" and "how he pays"
                    // at a glance, without parsing a long subtitle string.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _OrderPill(
                          icon: order.deliveryMethod == 'delivery'
                              ? Icons.delivery_dining_outlined
                              : Icons.store_outlined,
                          label: order.deliveryMethod == 'delivery'
                              ? (l?.tr('boutique_delivery_short') ?? 'Livraison')
                              : (l?.tr('boutique_pickup_short') ?? 'Retrait'),
                          bg: const Color(0xFFE0F2FE),
                          fg: const Color(0xFF0369A1),
                        ),
                        Builder(builder: (_) {
                          final isCard = order.paymentMethod == 'card';
                          final isPaid = order.paymentStatus == 'paid' ||
                              order.paymentStatus == 'deposit_paid';
                          if (isCard && isPaid) {
                            return _OrderPill(
                              icon: Icons.check_circle,
                              label: l?.tr('order_pay_card_paid') ?? 'Payé par carte',
                              bg: const Color(0xFFDCFCE7),
                              fg: const Color(0xFF16A34A),
                            );
                          }
                          if (isCard) {
                            return _OrderPill(
                              icon: Icons.credit_card,
                              label: l?.tr('order_pay_card_pending') ?? 'Carte — en attente',
                              bg: const Color(0xFFFEF3C7),
                              fg: const Color(0xFFB45309),
                            );
                          }
                          if (order.deliveryMethod == 'delivery') {
                            return _OrderPill(
                              icon: Icons.payments_outlined,
                              label: l?.tr('order_pay_cod_delivery') ?? 'Paiement à la livraison',
                              bg: AppColors.secondary100,
                              fg: AppColors.secondary500,
                            );
                          }
                          return _OrderPill(
                            icon: Icons.payments_outlined,
                            label: l?.tr('order_pay_at_salon') ?? 'Paiement au salon',
                            bg: AppColors.secondary100,
                            fg: AppColors.secondary500,
                          );
                        }),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabelLocalized(l),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _statusColor),
                ),
              ),
            ],
          ),
          const Divider(height: 20),
          // Items
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Text('${item.quantity}x ',
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.secondary500)),
                    Expanded(
                        child: Text(item.name,
                            style: const TextStyle(fontSize: 13))),
                    Text(CurrencyHelper.format(item.total, currency),
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              )),
          if (order.deliveryFee > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Expanded(
                      child: Text(l?.tr('boutique_delivery') ?? 'Livraison',
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.secondary400))),
                  Text(CurrencyHelper.format(order.deliveryFee, currency),
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.secondary400)),
                ],
              ),
            ),
          const Divider(height: 16),
          // Total + actions
          Row(
            children: [
              Text('${l?.tr('boutique_total') ?? 'Total:'} ${CurrencyHelper.format(order.grandTotal, currency)}',
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950)),
              const Spacer(),
              // "Confirmer" is only shown for COD/pickup pending orders.
              // - Card unpaid: hidden (owner can't validate an order whose
              //   payment hasn't landed yet — they only get Annuler).
              // - Card already paid: hidden too (auto-confirmed by webhook;
              //   legacy paid-pending docs flow straight to "Livrée").
              if (order.status == 'pending' &&
                  order.paymentMethod != 'card')
                _ActionBtn(
                  label: l?.tr('boutique_confirm') ?? 'Confirmer',
                  color: AppColors.brand600,
                  onTap: () =>
                      _db.updateOrderStatus(order.id, 'confirmed'),
                ),
              if (order.status == 'confirmed' ||
                  (order.status == 'pending' && order.paymentStatus == 'paid'))
                _ActionBtn(
                  // Label adapts to the delivery method: "Livrée" only
                  // makes sense when the salon actually delivers. For
                  // in-store pickup the action is the client coming to
                  // collect it → "Récupérée".
                  label: order.deliveryMethod == 'pickup'
                      ? (l?.tr('boutique_picked_up') ?? 'Récupérée')
                      : (l?.tr('boutique_delivered') ?? 'Livrée'),
                  color: const Color(0xFF16A34A),
                  onTap: () =>
                      _db.updateOrderStatus(order.id, 'delivered'),
                ),
              if (order.status == 'pending' || order.status == 'confirmed') ...[
                const SizedBox(width: 8),
                _ActionBtn(
                  label: l?.tr('boutique_cancel') ?? 'Annuler',
                  color: const Color(0xFFDC2626),
                  outlined: true,
                  onTap: () =>
                      _db.updateOrderStatus(order.id, 'cancelled'),
                ),
              ],
              // Failed-delivery return: only delivered + delivery method
              // orders get this. Owner ticks which items came back in good
              // shape → those get +stock, the rest stay deducted as lost.
              if (order.status == 'delivered' &&
                  order.deliveryMethod == 'delivery')
                _ActionBtn(
                  label: l?.tr('boutique_mark_returned_short') ?? 'Retourné',
                  color: const Color(0xFFB45309),
                  outlined: true,
                  onTap: () => _showReturnDialog(context, order),
                ),
            ],
          ),
          // Address if delivery
          if (order.deliveryMethod == 'delivery' &&
              order.clientAddress != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.location_on_outlined,
                    size: 14, color: AppColors.secondary400),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(order.clientAddress!,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.secondary500)),
                ),
              ],
            ),
          ],
          // Phone
          Row(
            children: [
              const Icon(Icons.phone_outlined,
                  size: 14, color: AppColors.secondary400),
              const SizedBox(width: 4),
              Text(order.clientPhone,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary500)),
            ],
          ),
        ],
      ),
    );
  }

  void _showReturnDialog(BuildContext context, OrderModel o) {
    showDialog<void>(
      context: context,
      builder: (_) => _ReturnOrderDialog(order: o),
    );
  }
}

class _ReturnOrderDialog extends StatefulWidget {
  const _ReturnOrderDialog({required this.order});
  final OrderModel order;

  @override
  State<_ReturnOrderDialog> createState() => _ReturnOrderDialogState();
}

class _ReturnOrderDialogState extends State<_ReturnOrderDialog> {
  // Default everything to "returned in good condition" so the common case
  // (full successful return) takes one tap. Owner unchecks lost/damaged.
  late final Set<String> _returnedIds = widget.order.items
      .map((i) => i.productId)
      .where((id) => id.isNotEmpty)
      .toSet();
  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await _db.markOrderReturned(widget.order.id, _returnedIds.toList());
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e'),
        ));
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(
                    color: Color(0xFFFEF3C7),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.assignment_return_outlined,
                      size: 18, color: Color(0xFFB45309)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l?.tr('boutique_return_dialog_title') ??
                        'Retour de livraison',
                    style: GoogleFonts.dmSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              l?.tr('boutique_return_dialog_body') ??
                  'Cochez les produits revenus en bon état — leur stock sera restauré.',
              style: const TextStyle(
                  fontSize: 13, color: AppColors.secondary500, height: 1.4),
            ),
            const SizedBox(height: 16),
            // Item checkboxes — capped height for many-item carts.
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView(
                shrinkWrap: true,
                children: widget.order.items
                    .where((i) => i.productId.isNotEmpty)
                    .map((item) {
                  final checked = _returnedIds.contains(item.productId);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (checked) {
                          _returnedIds.remove(item.productId);
                        } else {
                          _returnedIds.add(item.productId);
                        }
                      });
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: checked
                            ? const Color(0xFFF0FDF4)
                            : AppColors.secondary50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: checked
                              ? const Color(0xFF16A34A)
                              : AppColors.secondary100,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            checked
                                ? Icons.check_box_rounded
                                : Icons.check_box_outline_blank_rounded,
                            size: 20,
                            color: checked
                                ? const Color(0xFF16A34A)
                                : AppColors.secondary400,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${item.quantity}× ${item.name}',
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _returnedIds.isEmpty
                  ? (l?.tr('boutique_return_dialog_none') ??
                      'Aucun produit ne sera ré-attribué au stock.')
                  : (l?.tr('boutique_return_dialog_some') ??
                          '{count} produit(s) seront ré-attribué(s) au stock.')
                      .replaceAll('{count}', '${_returnedIds.length}'),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.secondary500),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context),
                  child: Text(l?.tr('common_cancel') ?? 'Annuler'),
                ),
                const SizedBox(width: 6),
                ElevatedButton(
                  onPressed: _saving ? null : _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB45309),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          l?.tr('boutique_return_dialog_confirm') ??
                              'Confirmer le retour',
                          style: const TextStyle(fontSize: 13),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color bg;
  final Color fg;
  const _OrderPill({
    required this.icon,
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool outlined;
  const _ActionBtn(
      {required this.label,
      required this.color,
      required this.onTap,
      this.outlined = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(8),
          border: outlined ? Border.all(color: color) : null,
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: outlined ? color : Colors.white),
        ),
      ),
    );
  }
}
