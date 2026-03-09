import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/product_model.dart';
import '../models/order_model.dart';
import '../models/salon_model.dart';
import '../providers/auth_providers.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';
import 'client_product_detail_screen.dart';

final _db = DatabaseService();

class ClientBoutiqueScreen extends ConsumerStatefulWidget {
  final SalonModel salon;
  const ClientBoutiqueScreen({super.key, required this.salon});

  @override
  ConsumerState<ClientBoutiqueScreen> createState() =>
      _ClientBoutiqueScreenState();
}

class _ClientBoutiqueScreenState extends ConsumerState<ClientBoutiqueScreen> {
  final Map<String, int> _cart = {}; // productId -> quantity
  String? _activeCategory;
  String _search = '';

  @override
  Widget build(BuildContext context) {
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
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Boutique',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                    fontSize: 18)),
            Text(widget.salon.name,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.secondary400)),
          ],
        ),
        actions: [
          if (_cart.isNotEmpty)
            Stack(
              alignment: Alignment.topRight,
              children: [
                IconButton(
                  icon: const Icon(Icons.shopping_bag_outlined,
                      color: AppColors.brand600),
                  onPressed: _openCart,
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Color(0xFFDC2626),
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      '${_cart.values.fold(0, (a, b) => a + b)}',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: StreamBuilder<List<ProductModel>>(
        stream: _db.getActiveProducts(widget.salon.id),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final products = snap.data ?? [];
          if (products.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 64, color: AppColors.secondary300),
                  const SizedBox(height: 16),
                  Text('Aucun produit disponible',
                      style: GoogleFonts.dmSans(
                          fontSize: 16, color: AppColors.secondary400)),
                ],
              ),
            );
          }

          // Categories
          final categories =
              products.map((p) => p.category).toSet().toList();

          var filtered = _activeCategory != null
              ? products.where((p) => p.category == _activeCategory).toList()
              : products.toList();
          if (_search.isNotEmpty) {
            final q = _search.toLowerCase();
            filtered = filtered
                .where((p) => p.name.toLowerCase().contains(q))
                .toList();
          }

          return Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'Rechercher un produit…',
                    hintStyle: const TextStyle(
                        color: AppColors.secondary400, fontSize: 13),
                    prefixIcon: const Icon(Icons.search,
                        color: AppColors.secondary400, size: 20),
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              // Category chips
              if (categories.length > 1)
                SizedBox(
                  height: 50,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 8),
                    children: [
                      _CategoryChip(
                        label: 'Tous',
                        active: _activeCategory == null,
                        onTap: () =>
                            setState(() => _activeCategory = null),
                      ),
                      ...categories.map((c) => _CategoryChip(
                            label: c,
                            active: _activeCategory == c,
                            onTap: () =>
                                setState(() => _activeCategory = c),
                          )),
                    ],
                  ),
                ),
              // Products grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(20),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    childAspectRatio: 0.72,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 14,
                  ),
                  itemCount: filtered.length,
                  itemBuilder: (_, i) {
                    final prod = filtered[i];
                    return GestureDetector(
                      onTap: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ClientProductDetailScreen(
                              product: prod,
                              cartQty: _cart[prod.id] ?? 0,
                              onCartChanged: (qty) {
                                setState(() {
                                  if (qty <= 0) {
                                    _cart.remove(prod.id);
                                  } else {
                                    _cart[prod.id] = qty;
                                  }
                                });
                              },
                            ),
                          ),
                        );
                      },
                      child: _ProductTile(
                        product: prod,
                        cartQty: _cart[prod.id] ?? 0,
                        onAdd: () => setState(() {
                          _cart[prod.id] =
                              (_cart[prod.id] ?? 0) + 1;
                        }),
                        onRemove: () => setState(() {
                          final qty = (_cart[prod.id] ?? 0) - 1;
                          if (qty <= 0) {
                            _cart.remove(prod.id);
                          } else {
                            _cart[prod.id] = qty;
                          }
                        }),
                      ),
                    );
                  },
                ),
              ),
              // Cart bar
              if (_cart.isNotEmpty)
                _CartBar(
                  itemCount: _cart.values.fold(0, (a, b) => a + b),
                  onTap: _openCart,
                ),
            ],
          );
        },
      ),
    );
  }

  void _openCart() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CartSheet(
        salon: widget.salon,
        cart: Map.from(_cart),
        onClearCart: () => setState(() => _cart.clear()),
      ),
    );
  }
}

// ─── Category Chip ───────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _CategoryChip(
      {required this.label, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: active ? AppColors.brand600 : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? AppColors.brand600 : AppColors.secondary200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: active ? Colors.white : AppColors.secondary500,
          ),
        ),
      ),
    );
  }
}

// ─── Product Tile ────────────────────────────────────────────────────────────

class _ProductTile extends StatelessWidget {
  final ProductModel product;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  const _ProductTile(
      {required this.product,
      required this.cartQty,
      required this.onAdd,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          Expanded(
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
              child: product.images.isNotEmpty
                  ? Image.network(product.images.first,
                      width: double.infinity, fit: BoxFit.cover)
                  : Container(
                      color: AppColors.brand50,
                      child: const Center(
                          child: Icon(Icons.image_outlined,
                              color: AppColors.brand300, size: 36)),
                    ),
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text('${product.price.toStringAsFixed(0)} MAD',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand600)),
                const SizedBox(height: 6),
                // Add to cart
                if (cartQty == 0)
                  SizedBox(
                    width: double.infinity,
                    height: 32,
                    child: ElevatedButton(
                      onPressed: onAdd,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand600,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: const Text('Ajouter',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  )
                else
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _QtyButton(
                          icon: Icons.remove, onTap: onRemove),
                      Padding(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 12),
                        child: Text('$cartQty',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold)),
                      ),
                      _QtyButton(icon: Icons.add, onTap: onAdd),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QtyButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.brand600),
      ),
    );
  }
}

// ─── Cart Bar ────────────────────────────────────────────────────────────────

class _CartBar extends StatelessWidget {
  final int itemCount;
  final VoidCallback onTap;
  const _CartBar({required this.itemCount, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: EdgeInsets.fromLTRB(
            20, 0, 20, MediaQuery.of(context).padding.bottom + 12),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: AppColors.brand600,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$itemCount',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Voir le panier',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600)),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Colors.white, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Cart Sheet (Checkout) ───────────────────────────────────────────────────

class _CartSheet extends ConsumerStatefulWidget {
  final SalonModel salon;
  final Map<String, int> cart;
  final VoidCallback onClearCart;
  const _CartSheet(
      {required this.salon, required this.cart, required this.onClearCart});

  @override
  ConsumerState<_CartSheet> createState() => _CartSheetState();
}

class _CartSheetState extends ConsumerState<_CartSheet> {
  String _deliveryMethod = 'pickup';
  final _addressCtrl = TextEditingController();
  bool _placing = false;
  List<ProductModel> _products = [];

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    final snap = await _db.getActiveProducts(widget.salon.id).first;
    if (mounted) setState(() => _products = snap);
  }

  @override
  void dispose() {
    _addressCtrl.dispose();
    super.dispose();
  }

  double get _subtotal {
    double total = 0;
    for (final entry in widget.cart.entries) {
      final product =
          _products.where((p) => p.id == entry.key).firstOrNull;
      if (product != null) total += product.price * entry.value;
    }
    return total;
  }

  double get _deliveryFee {
    if (_deliveryMethod == 'pickup') return 0;
    // Use max delivery fee from cart products
    double maxFee = 0;
    for (final entry in widget.cart.entries) {
      final product =
          _products.where((p) => p.id == entry.key).firstOrNull;
      if (product != null && product.deliveryFee > maxFee) {
        maxFee = product.deliveryFee;
      }
    }
    return maxFee;
  }

  Future<void> _placeOrder() async {
    if (_deliveryMethod == 'delivery' && _addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez entrer votre adresse')),
      );
      return;
    }

    setState(() => _placing = true);

    try {
      final user = ref.read(userModelProvider).value;
      final items = <OrderItem>[];

      for (final entry in widget.cart.entries) {
        final product =
            _products.where((p) => p.id == entry.key).firstOrNull;
        if (product != null) {
          items.add(OrderItem(
            productId: product.id,
            name: product.name,
            price: product.price,
            quantity: entry.value,
            imageUrl: product.images.isNotEmpty ? product.images.first : null,
          ));
        }
      }

      final order = OrderModel(
        id: '',
        salonId: widget.salon.id,
        clientId: user?.id ?? 'anonymous',
        clientName: user?.fullName ?? 'Client',
        clientPhone: user?.phone ?? '',
        clientAddress: _deliveryMethod == 'delivery'
            ? _addressCtrl.text.trim()
            : null,
        items: items,
        totalPrice: _subtotal,
        deliveryFee: _deliveryFee,
        deliveryMethod: _deliveryMethod,
        createdAt: DateTime.now(),
      );

      await _db.createOrder(order);

      if (mounted) {
        widget.onClearCart();
        Navigator.pop(context);
        Navigator.pop(context); // Go back to salon profile
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Commande passée avec succès !'),
            backgroundColor: Color(0xFF16A34A),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erreur: $e')));
      }
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(userModelProvider).value;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text('Mon Panier',
                      style: GoogleFonts.dmSans(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950)),
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
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                // Cart items
                ...widget.cart.entries.map((entry) {
                  final product = _products
                      .where((p) => p.id == entry.key)
                      .firstOrNull;
                  if (product == null) return const SizedBox.shrink();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: product.images.isNotEmpty
                              ? Image.network(product.images.first,
                                  width: 50, height: 50, fit: BoxFit.cover)
                              : Container(
                                  width: 50,
                                  height: 50,
                                  color: AppColors.brand50,
                                  child: const Icon(Icons.image_outlined,
                                      color: AppColors.brand300)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(product.name,
                                  style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600)),
                              Text(
                                  '${product.price.toStringAsFixed(0)} MAD x ${entry.value}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.secondary500)),
                            ],
                          ),
                        ),
                        Text(
                          '${(product.price * entry.value).toStringAsFixed(0)} MAD',
                          style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  );
                }),

                const SizedBox(height: 20),

                // Delivery method
                Text('Mode de récupération',
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _DeliveryOption(
                        icon: Icons.store_outlined,
                        label: 'Retrait au salon',
                        active: _deliveryMethod == 'pickup',
                        onTap: () =>
                            setState(() => _deliveryMethod = 'pickup'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _DeliveryOption(
                        icon: Icons.delivery_dining_outlined,
                        label: 'Livraison',
                        active: _deliveryMethod == 'delivery',
                        onTap: () =>
                            setState(() => _deliveryMethod = 'delivery'),
                      ),
                    ),
                  ],
                ),

                // Address field for delivery
                if (_deliveryMethod == 'delivery') ...[
                  const SizedBox(height: 16),
                  Text('Adresse de livraison',
                      style: GoogleFonts.dmSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.secondary500)),
                  const SizedBox(height: 6),
                  TextFormField(
                    controller: _addressCtrl,
                    decoration: InputDecoration(
                      hintText: user?.city ?? 'Votre adresse complète',
                      filled: true,
                      fillColor: AppColors.secondary50,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.secondary200)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide:
                              BorderSide(color: AppColors.secondary200)),
                    ),
                    maxLines: 2,
                  ),
                ],

                const SizedBox(height: 24),

                // Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: [
                      _SummaryRow(
                          label: 'Sous-total',
                          value: '${_subtotal.toStringAsFixed(0)} MAD'),
                      if (_deliveryFee > 0)
                        _SummaryRow(
                            label: 'Livraison',
                            value:
                                '${_deliveryFee.toStringAsFixed(0)} MAD'),
                      const Divider(),
                      _SummaryRow(
                        label: 'Total',
                        value:
                            '${(_subtotal + _deliveryFee).toStringAsFixed(0)} MAD',
                        bold: true,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),
                const Text(
                  'Paiement à la livraison / au retrait',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 12, color: AppColors.secondary400),
                ),
              ],
            ),
          ),
          // Place order button
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 8, 20, MediaQuery.of(context).padding.bottom + 12),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _placing ? null : _placeOrder,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: _placing
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Passer la commande',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _DeliveryOption(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? AppColors.brand50 : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: active ? AppColors.brand600 : AppColors.secondary200,
              width: active ? 2 : 1),
        ),
        child: Column(
          children: [
            Icon(icon,
                color: active ? AppColors.brand600 : AppColors.secondary400,
                size: 24),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: active
                        ? AppColors.brand600
                        : AppColors.secondary500)),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _SummaryRow(
      {required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal,
                  color:
                      bold ? AppColors.brand950 : AppColors.secondary500)),
          Text(value,
              style: TextStyle(
                  fontSize: bold ? 15 : 13,
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: AppColors.brand950)),
        ],
      ),
    );
  }
}
