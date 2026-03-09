import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/product_model.dart';
import '../theme/app_colors.dart';

class ClientProductDetailScreen extends StatefulWidget {
  final ProductModel product;
  final int cartQty;
  final ValueChanged<int> onCartChanged;

  const ClientProductDetailScreen({
    super.key,
    required this.product,
    required this.cartQty,
    required this.onCartChanged,
  });

  @override
  State<ClientProductDetailScreen> createState() =>
      _ClientProductDetailScreenState();
}

class _ClientProductDetailScreenState
    extends State<ClientProductDetailScreen> {
  late int _qty;
  int _currentImage = 0;
  late final PageController _pageCtrl;

  @override
  void initState() {
    super.initState();
    _qty = widget.cartQty;
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final hasImages = p.images.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.brand950, size: 18),
          onPressed: () {
            widget.onCartChanged(_qty);
            Navigator.pop(context);
          },
        ),
        title: Text(
          'Détail produit',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 18,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Images carousel ──
                  if (hasImages)
                    SizedBox(
                      height: 300,
                      child: Stack(
                        children: [
                          PageView.builder(
                            controller: _pageCtrl,
                            itemCount: p.images.length,
                            onPageChanged: (i) =>
                                setState(() => _currentImage = i),
                            itemBuilder: (_, i) => Image.network(
                              p.images[i],
                              width: double.infinity,
                              fit: BoxFit.cover,
                            ),
                          ),
                          if (p.images.length > 1)
                            Positioned(
                              bottom: 12,
                              left: 0,
                              right: 0,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(
                                  p.images.length,
                                  (i) => Container(
                                    width: _currentImage == i ? 20 : 8,
                                    height: 8,
                                    margin: const EdgeInsets.symmetric(
                                        horizontal: 3),
                                    decoration: BoxDecoration(
                                      color: _currentImage == i
                                          ? AppColors.brand600
                                          : Colors.white.withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    )
                  else
                    Container(
                      height: 200,
                      width: double.infinity,
                      color: AppColors.brand50,
                      child: const Center(
                        child: Icon(Icons.image_outlined,
                            color: AppColors.brand300, size: 64),
                      ),
                    ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Category badge ──
                        if (p.category.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.brand50,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              p.category,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.brand600,
                              ),
                            ),
                          ),
                        if (p.category.isNotEmpty) const SizedBox(height: 10),

                        // ── Name ──
                        Text(
                          p.name,
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ── Price ──
                        Text(
                          '${p.price.toStringAsFixed(0)} MAD',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.brand600,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Stock badge ──
                        _StockBadge(product: p),
                        const SizedBox(height: 20),

                        // ── Description ──
                        if (p.description.isNotEmpty) ...[
                          Text(
                            'Description',
                            style: GoogleFonts.dmSans(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brand950,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            p.description,
                            style: const TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: AppColors.secondary600,
                            ),
                          ),
                          const SizedBox(height: 20),
                        ],

                        // ── Details list ──
                        _DetailRow(
                          icon: Icons.category_outlined,
                          label: 'Catégorie',
                          value: p.category.isNotEmpty ? p.category : '—',
                        ),
                        _DetailRow(
                          icon: Icons.local_shipping_outlined,
                          label: 'Livraison',
                          value: p.deliveryType == 'pickup'
                              ? 'Retrait en magasin'
                              : p.deliveryType == 'national'
                                  ? 'Tout le pays'
                                  : 'Par ville',
                        ),
                        if (p.deliveryType != 'pickup' && p.deliveryFee > 0)
                          _DetailRow(
                            icon: Icons.payments_outlined,
                            label: 'Frais de livraison',
                            value: '${p.deliveryFee.toStringAsFixed(0)} MAD',
                          ),
                        if (p.deliveryType == 'cities' && p.deliveryCities.isNotEmpty)
                          _DetailRow(
                            icon: Icons.location_on_outlined,
                            label: 'Villes',
                            value: p.deliveryCities.join(', '),
                          ),
                        _DetailRow(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stock disponible',
                          value: '${p.stock} unités',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Bottom bar ──
          Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 10,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: p.isOutOfStock
                ? SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: null,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Rupture de stock'),
                    ),
                  )
                : _qty == 0
                    ? SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: () => setState(() => _qty = 1),
                          icon: const Icon(Icons.add_shopping_cart, size: 18),
                          label: const Text('Ajouter au panier',
                              style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.brand600,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          // Qty controls
                          Container(
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.secondary200),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      if (_qty > 1) {
                                        _qty--;
                                      } else {
                                        _qty = 0;
                                      }
                                    });
                                  },
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8),
                                  child: Text(
                                    '$_qty',
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.brand950,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.add, size: 18),
                                  onPressed: _qty < p.stock
                                      ? () => setState(() => _qty++)
                                      : null,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          // Confirm button
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton(
                                onPressed: () {
                                  widget.onCartChanged(_qty);
                                  Navigator.pop(context);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.brand600,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: Text(
                                  'Confirmer · ${(p.price * _qty).toStringAsFixed(0)} MAD',
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700),
                                ),
                              ),
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

// ── Stock badge ──────────────────────────────────────────────────────────────

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.product});
  final ProductModel product;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final String text;
    final IconData icon;

    if (product.isOutOfStock) {
      bg = const Color(0xFFFEE2E2);
      fg = const Color(0xFFDC2626);
      text = 'Rupture de stock';
      icon = Icons.error_outline;
    } else if (product.isLowStock) {
      bg = const Color(0xFFFFF7ED);
      fg = const Color(0xFFEA580C);
      text = 'Stock limité (${product.stock})';
      icon = Icons.warning_amber_rounded;
    } else {
      bg = const Color(0xFFF0FDF4);
      fg = const Color(0xFF16A34A);
      text = 'En stock (${product.stock})';
      icon = Icons.check_circle_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const SizedBox(width: 6),
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }
}

// ── Detail row ───────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  const _DetailRow(
      {required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.secondary400),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.secondary500)),
          const Spacer(),
          Text(value,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand950)),
        ],
      ),
    );
  }
}
