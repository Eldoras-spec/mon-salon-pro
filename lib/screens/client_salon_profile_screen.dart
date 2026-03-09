import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../models/salon_model.dart';
import '../models/review_model.dart';
import '../models/promotion_model.dart';
import '../models/product_model.dart';
import '../services/database_service.dart';
import 'client_boutique_screen.dart';
import '../services/auth_service.dart';
import 'client_booking_flow_screen.dart';
import 'chat_screen.dart';
import '../services/message_service.dart';

class ClientSalonProfileScreen extends StatefulWidget {
  final SalonModel salon;

  const ClientSalonProfileScreen({super.key, required this.salon});

  @override
  State<ClientSalonProfileScreen> createState() =>
      _ClientSalonProfileScreenState();
}

class _ClientSalonProfileScreenState extends State<ClientSalonProfileScreen> {
  final _databaseService = DatabaseService();
  final _authService = AuthService();
  bool _isFavorite = false;
  String _selectedCategory = 'Tous';

  // French day keys (stored in Firestore by owner onboarding)
  static const _dayKeys = [
    'lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche',
  ];
  static const _dayLabels = [
    'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche',
  ];

  List<String> get _serviceCategories {
    final cats = widget.salon.services
        .map((s) => (s['category'] as String?)?.trim() ?? '')
        .where((c) => c.isNotEmpty)
        .toSet()
        .toList();
    return ['Tous', ...cats];
  }

  bool get _isOpen {
    final wh = widget.salon.workingHours;
    if (wh.isEmpty) return false;
    final now = DateTime.now();
    final dayKey = _dayKeys[now.weekday - 1];
    final dayConfig = wh[dayKey];
    if (dayConfig == null || dayConfig['isOpen'] != true) return false;
    try {
      final op = (dayConfig['open'] as String).split(':');
      final cl = (dayConfig['close'] as String).split(':');
      final nowMin = now.hour * 60 + now.minute;
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      return nowMin >= openMin && nowMin < closeMin;
    } catch (_) {
      return false;
    }
  }

  // Avoids showing "kenitra, kenitra" when address == city
  String get _displayAddress {
    final addr = widget.salon.address.trim();
    final city = widget.salon.city.trim();
    if (addr.isEmpty) return city;
    if (addr.toLowerCase().contains(city.toLowerCase())) return addr;
    return '$addr, $city';
  }

  @override
  void initState() {
    super.initState();
    _checkFavoriteStatus();
  }

  Future<void> _checkFavoriteStatus() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    final user = await _authService.getUserModel(uid);
    if (mounted && user != null) {
      setState(() => _isFavorite = user.favorites.contains(widget.salon.id));
    }
  }

  Future<void> _openChat() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    final user = await _authService.getUserModel(uid);
    if (!mounted) return;
    try {
      final convId = await MessageService().getOrCreateConversation(
        clientId: uid,
        clientName: user?.fullName ?? 'Client',
        salonId: widget.salon.id,
        salonName: widget.salon.name,
        ownerId: widget.salon.ownerId,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            conversationId: convId,
            currentUserId: uid,
            isClient: true,
            otherPartyName: widget.salon.name,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;
    final newStatus = !_isFavorite;
    setState(() => _isFavorite = newStatus);
    try {
      await _databaseService.toggleFavorite(uid, widget.salon.id, newStatus);
    } catch (_) {
      if (mounted) setState(() => _isFavorite = !newStatus);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildSliverAppBar(),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildAboutSection(),
                      const SizedBox(height: 16),
                      _buildGallerySection(),
                      const SizedBox(height: 16),
                      _buildBeforeAfterSection(),
                      const SizedBox(height: 16),
                      _buildServicesMenu(),
                      const SizedBox(height: 16),
                      _buildPromotionsSection(),
                      _buildBoutiqueSection(),
                      _buildReviewsSection(),
                      const SizedBox(height: 16),
                      _buildHoursAndInfoCard(),
                      const SizedBox(height: 16),
                      _buildMapCard(),
                      const SizedBox(height: 100),
                    ],
                  ),
                ),
              ),
            ],
          ),
          // CTA buttons
          Positioned(
            bottom: 24,
            left: 24,
            right: 24,
            child: Row(
              children: [
                // Contact button
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: OutlinedButton.icon(
                      onPressed: _openChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: const Text('Contacter'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand700,
                        backgroundColor: Colors.white,
                        side: const BorderSide(color: AppColors.brand300, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Book button
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 52,
                    child: CustomButton(
                      text: 'Prendre un RDV',
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ClientBookingFlowScreen(salon: widget.salon),
                          ),
                        );
                      },
                      icon: Icons.calendar_today_rounded,
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

  // ─── Header ───────────────────────────────────────────────────────────────

  Widget _buildSliverAppBar() {
    final imageUrl = widget.salon.images.isNotEmpty
        ? widget.salon.images[0]
        : 'https://images.unsplash.com/photo-1560066984-138dadb4c035?ixlib=rb-4.0.3&auto=format&fit=crop&w=1000&q=80';
    final isOpen = _isOpen;

    return SliverAppBar(
      expandedHeight: 300.0,
      pinned: true,
      backgroundColor: AppColors.brand950,
      elevation: 0,
      // Collapsed app bar title
      title: Text(
        widget.salon.name,
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
      ),
      leading: Padding(
        padding: const EdgeInsets.all(8),
        child: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.35),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 16),
          ),
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 8, right: 4),
          child: GestureDetector(
            onTap: _toggleFavorite,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _isFavorite
                    ? AppColors.brand600.withValues(alpha: 0.9)
                    : Colors.black.withValues(alpha: 0.35),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        background: Stack(
          fit: StackFit.expand,
          children: [
            // Hero image
            Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Container(
                color: AppColors.brand100,
                child: const Center(
                  child: Icon(Icons.storefront_outlined,
                      size: 48, color: AppColors.brand300),
                ),
              ),
            ),

            // Dark gradient (top subtle, strong at bottom)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.2),
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                  stops: const [0.0, 0.38, 1.0],
                ),
              ),
            ),

            // Overlay info
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Category badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand600.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      widget.salon.category,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Salon name
                  Text(
                    widget.salon.name,
                    style: GoogleFonts.dmSans(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Address
                  Row(
                    children: [
                      const Icon(Icons.location_on_rounded,
                          size: 13, color: Colors.white70),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          _displayAddress,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Rating + open/closed
                  Row(
                    children: [
                      if (widget.salon.reviewCount > 0) ...[
                        const Icon(Icons.star_rounded,
                            size: 15, color: Colors.amber),
                        const SizedBox(width: 4),
                        Text(
                          widget.salon.rating.toStringAsFixed(1),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '  (${widget.salon.reviewCount} avis)',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 12),
                        ),
                        const SizedBox(width: 12),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.white30),
                          ),
                          child: const Text(
                            'Nouveau',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? const Color(0xFF22C55E)
                                  .withValues(alpha: 0.9)
                              : const Color(0xFFEF4444)
                                  .withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          isOpen ? 'Ouvert' : 'Fermé',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── About ────────────────────────────────────────────────────────────────

  Widget _buildAboutSection() {
    return SizedBox(
      width: double.infinity,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: _cardDecoration(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle('À propos'),
            const SizedBox(height: 10),
            Text(
              widget.salon.description.isNotEmpty
                  ? widget.salon.description
                  : 'Aucune description disponible.',
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.secondary600,
                  height: 1.6),
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  // ─── Gallery ──────────────────────────────────────────────────────────────

  Widget _buildGallerySection() {
    final images = widget.salon.images;
    final extra = images.length > 3 ? images.length - 3 : 0;
    final visible = extra > 0 ? images.sublist(0, 3) : images;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitle('Galerie'),
              if (extra > 0)
                TextButton(
                  onPressed: () {},
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text(
                    'Voir tout',
                    style: TextStyle(
                        color: AppColors.brand600,
                        fontWeight: FontWeight.w500,
                        fontSize: 13),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Container(
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_library_outlined,
                      size: 32, color: AppColors.secondary300),
                  SizedBox(height: 6),
                  Text('Aucune photo disponible',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.secondary400)),
                ],
              ),
            )
          else
          SizedBox(
            height: 110,
            child: Row(
              children: [
                ...visible.asMap().entries.map((e) {
                  final isLast = e.key == visible.length - 1 && extra == 0;
                  return Expanded(
                    child: Container(
                      margin: isLast
                          ? EdgeInsets.zero
                          : const EdgeInsets.only(right: 8),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: AppColors.secondary100,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Image.network(
                        e.value,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: double.infinity,
                        errorBuilder: (_, e, s) => Container(
                          color: AppColors.secondary100,
                          alignment: Alignment.center,
                          child: const Icon(Icons.image_not_supported_outlined,
                              size: 28, color: AppColors.secondary300),
                        ),
                      ),
                    ),
                  );
                }),
                if (extra > 0)
                  Expanded(
                    child: GestureDetector(
                      onTap: () {},
                      child: Container(
                        margin: const EdgeInsets.only(left: 0),
                        decoration: BoxDecoration(
                          color: AppColors.secondary100,
                          borderRadius: BorderRadius.circular(12),
                          border:
                              Border.all(color: AppColors.secondary200),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '+$extra',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.secondary600,
                          ),
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

  // ─── Avant / Après ────────────────────────────────────────────────────────

  Widget _buildBeforeAfterSection() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: DatabaseService().getBeforeAfterStream(widget.salon.id),
      builder: (context, snap) {
        final items = snap.data ?? [];
        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Avant / Après'),
              const SizedBox(height: 14),
              SizedBox(
                height: 180,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) {
                    final item = items[i];
                    return _BeforeAfterCard(
                      beforeUrl: item['beforeUrl'] ?? '',
                      afterUrl: item['afterUrl'] ?? '',
                      label: item['label'] ?? '',
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Services ─────────────────────────────────────────────────────────────

  Widget _buildServicesMenu() {
    final filtered = _selectedCategory == 'Tous'
        ? widget.salon.services
        : widget.salon.services
            .where((s) => s['category'] == _selectedCategory)
            .toList();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Services'),
          if (_serviceCategories.length > 1) ...[
            const SizedBox(height: 14),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _serviceCategories.map((cat) {
                  final sel = _selectedCategory == cat;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: sel,
                      onSelected: (v) {
                        if (v) setState(() => _selectedCategory = cat);
                      },
                      backgroundColor: Colors.white,
                      selectedColor: AppColors.brand600,
                      labelStyle: TextStyle(
                        color: sel ? Colors.white : AppColors.secondary600,
                        fontWeight:
                            sel ? FontWeight.bold : FontWeight.w500,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: sel
                              ? Colors.transparent
                              : AppColors.secondary200,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          const SizedBox(height: 14),
          if (filtered.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Aucun service disponible',
                    style: TextStyle(color: AppColors.secondary400)),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (_, i) => _buildServiceCard(filtered[i]),
            ),
        ],
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> service) {
    final title =
        service['title'] as String? ?? service['name'] as String? ?? 'Service';
    final price = (service['price'] ?? 0.0).toDouble();
    final duration = (service['duration'] ?? 30) as int;
    final description = service['description'] as String? ?? '';
    final professionals = service['professionals'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand950,
                    fontSize: 14,
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.secondary500),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.access_time_rounded,
                        size: 13, color: AppColors.secondary400),
                    const SizedBox(width: 4),
                    Text('$duration min',
                        style: const TextStyle(
                            fontSize: 12, color: AppColors.secondary500)),
                    if (professionals.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Text('•',
                            style: TextStyle(color: AppColors.secondary300)),
                      ),
                      const Icon(Icons.person_outline_rounded,
                          size: 13, color: AppColors.secondary400),
                      const SizedBox(width: 4),
                      Text(professionals,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.secondary500)),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '\$${price.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ClientBookingFlowScreen(
                      salon: widget.salon,
                      initialService: service,
                    ),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.brand600,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Réserver',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Boutique ────────────────────────────────────────────────────────────

  Widget _buildBoutiqueSection() {
    return StreamBuilder<List<ProductModel>>(
      stream: _databaseService.getActiveProducts(widget.salon.id),
      builder: (context, snap) {
        final products = snap.data ?? [];
        if (products.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Boutique',
                    style: GoogleFonts.dmSans(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.brand950,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ClientBoutiqueScreen(salon: widget.salon),
                    ),
                  ),
                  child: const Text(
                    'Voir tout',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.brand600,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 180,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: products.length > 6 ? 6 : products.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) {
                  final p = products[i];
                  return GestureDetector(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            ClientBoutiqueScreen(salon: widget.salon),
                      ),
                    ),
                    child: Container(
                      width: 130,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.secondary100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(14)),
                              child: p.images.isNotEmpty
                                  ? Image.network(p.images.first,
                                      width: 130, fit: BoxFit.cover)
                                  : Container(
                                      color: AppColors.brand50,
                                      child: const Center(
                                        child: Icon(Icons.image_outlined,
                                            color: AppColors.brand300,
                                            size: 28),
                                      ),
                                    ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(
                                    '${p.price.toStringAsFixed(0)} MAD',
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.brand600)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  // ─── Promotions ───────────────────────────────────────────────────────────

  Widget _buildPromotionsSection() {
    return StreamBuilder<List<PromotionModel>>(
      stream: _databaseService.getActivePromotions(widget.salon.id, clientId: AuthService().currentUserId),
      builder: (context, snap) {
        final promos = snap.data ?? [];
        if (promos.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Offres & Promotions',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 144,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.zero,
                itemCount: promos.length,
                separatorBuilder: (context, i) => const SizedBox(width: 12),
                itemBuilder: (context, i) =>
                    _PromoCard(promo: promos[i]),
              ),
            ),
            const SizedBox(height: 20),
          ],
        );
      },
    );
  }

  // ─── Reviews ──────────────────────────────────────────────────────────────

  Widget _buildReviewsSection() {
    return StreamBuilder<List<ReviewModel>>(
      stream: _databaseService.getReviews(widget.salon.id),
      builder: (context, snapshot) {
        final reviews = snapshot.data ?? [];
        final count = reviews.length;
        final avg = count > 0
            ? reviews.map((r) => r.rating).reduce((a, b) => a + b) / count
            : 0.0;

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: _cardDecoration(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('Avis clients'),
                      const SizedBox(height: 4),
                      if (count > 0)
                        Row(
                          children: [
                            ...List.generate(
                              5,
                              (i) => Icon(
                                i < avg.round()
                                    ? Icons.star_rounded
                                    : Icons.star_outline_rounded,
                                size: 13,
                                color: Colors.amber,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '${avg.toStringAsFixed(1)} · $count avis',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary500),
                            ),
                          ],
                        )
                      else
                        const Text(
                          'Aucun avis pour le moment',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.secondary400),
                        ),
                    ],
                  ),
                  OutlinedButton(
                    onPressed: _openReviewSheet,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      side: const BorderSide(color: AppColors.brand300),
                    ),
                    child: const Text(
                      'Laisser un avis',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.brand600,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),

              if (count == 0) ...[
                const SizedBox(height: 28),
                Center(
                  child: Column(
                    children: [
                      Icon(Icons.rate_review_outlined,
                          size: 52, color: AppColors.secondary200),
                      const SizedBox(height: 10),
                      const Text(
                        'Soyez le premier à laisser un avis !',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.secondary400),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                const SizedBox(height: 16),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reviews.length > 3 ? 3 : reviews.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _buildReviewCard(reviews[i]),
                ),
                if (reviews.length > 3) ...[
                  const SizedBox(height: 12),
                  Center(
                    child: TextButton(
                      onPressed: () {},
                      child: Text(
                        'Voir les ${reviews.length} avis',
                        style: const TextStyle(
                            color: AppColors.brand600,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildReviewCard(ReviewModel review) {
    final initials = review.userName.isNotEmpty
        ? review.userName[0].toUpperCase()
        : '?';
    final diff = DateTime.now().difference(review.createdAt);
    final String dateStr;
    if (diff.inMinutes < 1) {
      dateStr = 'À l\'instant';
    } else if (diff.inHours < 1) {
      dateStr = 'Il y a ${diff.inMinutes} min';
    } else if (diff.inDays < 1) {
      dateStr = 'Il y a ${diff.inHours}h';
    } else if (diff.inDays == 1) {
      dateStr = 'Hier';
    } else if (diff.inDays < 30) {
      dateStr = 'Il y a ${diff.inDays}j';
    } else {
      dateStr = DateFormat('dd/MM/yyyy').format(review.createdAt);
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.brand100,
                child: Text(
                  initials,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.userName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950,
                      ),
                    ),
                    Text(
                      dateStr,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.secondary400),
                    ),
                  ],
                ),
              ),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    i < review.rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    size: 13,
                    color: Colors.amber,
                  ),
                ),
              ),
            ],
          ),
          if (review.comment.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.secondary700,
                  height: 1.4),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openReviewSheet() async {
    final uid = _authService.currentUserId;
    if (uid == null) return;

    // Check if user already reviewed
    final already =
        await _databaseService.hasUserReviewed(widget.salon.id, uid);
    if (!mounted) return;
    if (already) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vous avez déjà laissé un avis pour ce salon.'),
          backgroundColor: AppColors.secondary700,
        ),
      );
      return;
    }

    final user = await _authService.getUserModel(uid);
    if (!mounted) return;
    final userName = user?.fullName ?? 'Client';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReviewSheet(
        salonId: widget.salon.id,
        userId: uid,
        userName: userName,
        db: _databaseService,
      ),
    );
  }

  // ─── Map ──────────────────────────────────────────────────────────────────

  Widget _buildMapCard() {
    final lat = widget.salon.latitude;
    final lon = widget.salon.longitude;
    final hasCoords = lat != null && lon != null;

    return GestureDetector(
      onTap: () => _openMap(lat, lon),
      child: Container(
        decoration: _cardDecoration(),
        clipBehavior: Clip.hardEdge,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Map preview ──────────────────────────────────────────────
            Stack(
              children: [
                if (hasCoords)
                  SizedBox(
                    height: 150,
                    width: double.infinity,
                    child: IgnorePointer(
                      child: FlutterMap(
                        options: MapOptions(
                          initialCenter: LatLng(lat, lon),
                          initialZoom: 15,
                          interactionOptions: const InteractionOptions(
                            flags: InteractiveFlag.none,
                          ),
                        ),
                        children: [
                          TileLayer(
                            urlTemplate:
                                'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.blagence.monsalon',
                          ),
                          MarkerLayer(
                            markers: [
                              Marker(
                                point: LatLng(lat, lon),
                                width: 36,
                                height: 36,
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppColors.brand600,
                                  size: 36,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  _mapPlaceholder(),

                // "Itinéraire" pill overlay
                Positioned(
                  bottom: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: const [
                        BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2))
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.navigation_rounded,
                            size: 14, color: AppColors.brand600),
                        SizedBox(width: 4),
                        Text(
                          'Itinéraire',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            // ── Address row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  const Icon(Icons.location_on_rounded,
                      color: AppColors.brand600, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _displayAddress,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondary700,
                      ),
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.secondary300, size: 18),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapPlaceholder() {
    return Container(
      height: 150,
      width: double.infinity,
      color: const Color(0xFFE5E7EB),
      child: const Center(
        child: Icon(Icons.map_rounded, size: 48, color: Color(0xFF9CA3AF)),
      ),
    );
  }

  Future<void> _openMap(double? lat, double? lon) async {
    final Uri uri;
    if (lat != null && lon != null) {
      // geo: URI → Android shows native app picker (Maps, Waze, etc.)
      // maps.apple.com → iOS opens Maps by default (user can choose another)
      uri = Platform.isIOS
          ? Uri.parse('https://maps.apple.com/?q=$lat,$lon')
          : Uri.parse('geo:$lat,$lon?q=$lat,$lon');
    } else {
      final address = Uri.encodeComponent(_displayAddress);
      uri = Platform.isIOS
          ? Uri.parse('https://maps.apple.com/?q=$address')
          : Uri.parse('geo:0,0?q=$address');
    }
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ─── Hours & Info ─────────────────────────────────────────────────────────

  Widget _buildHoursAndInfoCard() {
    final now = DateTime.now();
    final todayIdx = now.weekday - 1; // 0 = Monday

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Informations'),
          const SizedBox(height: 16),

          // Address
          _infoRow(
            icon: Icons.location_on_rounded,
            text: _displayAddress,
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: AppColors.secondary100, height: 1),
          ),

          // Working hours
          Text(
            'Horaires d\'ouverture',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 12),

          if (widget.salon.workingHours.isEmpty)
            const Text(
              'Horaires non disponibles',
              style: TextStyle(
                  fontSize: 13, color: AppColors.secondary400),
            )
          else
            ...List.generate(_dayKeys.length, (i) {
              final key = _dayKeys[i];
              final label = _dayLabels[i];
              final dayConfig = widget.salon.workingHours[key];
              final isToday = i == todayIdx;
              final dayIsOpen =
                  dayConfig != null && dayConfig['isOpen'] == true;
              final hours = dayIsOpen
                  ? '${dayConfig['open']} – ${dayConfig['close']}'
                  : 'Fermé';

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 12,
                          child: isToday
                              ? Container(
                                  width: 6,
                                  height: 6,
                                  decoration: const BoxDecoration(
                                    color: AppColors.brand500,
                                    shape: BoxShape.circle,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 13,
                            color: isToday
                                ? AppColors.brand700
                                : AppColors.secondary600,
                            fontWeight: isToday
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      hours,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isToday
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: dayIsOpen
                            ? (isToday
                                ? AppColors.brand700
                                : AppColors.secondary700)
                            : AppColors.secondary400,
                      ),
                    ),
                  ],
                ),
              );
            }),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: AppColors.secondary100, height: 1),
          ),

          // Social media
          Text(
            'Réseaux sociaux',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 12),
          _buildSocialRow(),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  BoxDecoration _cardDecoration() => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
      );

  Widget _sectionTitle(String text) => Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: AppColors.brand950,
        ),
      );

  Widget _infoRow({required IconData icon, required String text}) => Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.brand600),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 13, color: AppColors.secondary700),
            ),
          ),
        ],
      );

  Widget _buildSocialRow() {
    final links = widget.salon.socialLinks;

    final socials = [
      _SocialEntry(
        icon: FontAwesomeIcons.instagram,
        color: const Color(0xFFE1306C),
        handle: links['instagram'] ?? '',
        urlBuilder: (h) => 'https://instagram.com/$h',
      ),
      _SocialEntry(
        icon: FontAwesomeIcons.facebookF,
        color: const Color(0xFF1877F2),
        handle: links['facebook'] ?? '',
        urlBuilder: (h) => 'https://facebook.com/$h',
      ),
      _SocialEntry(
        icon: FontAwesomeIcons.tiktok,
        color: Colors.black87,
        handle: links['tiktok'] ?? '',
        urlBuilder: (h) => 'https://tiktok.com/@$h',
      ),
      _SocialEntry(
        icon: FontAwesomeIcons.whatsapp,
        color: const Color(0xFF25D366),
        handle: links['whatsapp'] ?? '',
        urlBuilder: (h) => 'https://wa.me/$h',
      ),
    ].where((s) => s.handle.isNotEmpty).toList();

    if (socials.isEmpty) {
      return const Text(
        'Aucun réseau social renseigné',
        style: TextStyle(fontSize: 12, color: AppColors.secondary400),
      );
    }

    return Row(
      children: socials.map((s) {
        return Padding(
          padding: const EdgeInsets.only(right: 10),
          child: GestureDetector(
            onTap: () async {
              final url = Uri.parse(s.urlBuilder(s.handle));
              if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: s.color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: s.color.withValues(alpha: 0.25)),
              ),
              alignment: Alignment.center,
              child: FaIcon(s.icon, size: 16, color: s.color),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _SocialEntry {
  final IconData icon;
  final Color color;
  final String handle;
  final String Function(String) urlBuilder;

  const _SocialEntry({
    required this.icon,
    required this.color,
    required this.handle,
    required this.urlBuilder,
  });
}

class _PromoCard extends StatelessWidget {
  const _PromoCard({required this.promo});
  final PromotionModel promo;

  static const _typeGradient = {
    'percent': [Color(0xFF6366F1), Color(0xFF8B5CF6)],
    'special': [Color(0xFFEC4899), Color(0xFFF43F5E)],
    'code': [Color(0xFFF59E0B), Color(0xFFEA580C)],
  };
  static const _typeIcon = {
    'percent': Icons.percent_rounded,
    'special': Icons.auto_awesome,
    'code': Icons.confirmation_number_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final gradient = _typeGradient[promo.type] ?? [AppColors.brand600, AppColors.brand400];
    final icon = _typeIcon[promo.type] ?? Icons.local_offer_outlined;
    final hasDiscount = promo.discountPercent != null && promo.discountPercent! > 0;

    return SizedBox(
      width: 220,
      height: 136,
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          children: [
            // Background pattern
            Positioned(
              right: -15,
              top: -15,
              child: Icon(icon, size: 80, color: Colors.white.withValues(alpha: 0.1)),
            ),
            // Content
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top row: icon + discount badge
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon, color: Colors.white, size: 16),
                      ),
                      const Spacer(),
                      if (hasDiscount)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '-${promo.discountPercent!.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: gradient[0],
                            ),
                          ),
                        ),
                    ],
                  ),
                  const Spacer(),
                  // Title
                  Text(
                    promo.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.white,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // Description
                  Text(
                    promo.description,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // Promo code
                  if (promo.promoCode != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'Code : ${promo.promoCode!}',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Review bottom sheet ───────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final String salonId;
  final String userId;
  final String userName;
  final DatabaseService db;

  const _ReviewSheet({
    required this.salonId,
    required this.userId,
    required this.userName,
    required this.db,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 0;
  final _commentController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Veuillez sélectionner une note.')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      await widget.db.submitReview(
        salonId: widget.salonId,
        userId: widget.userId,
        userName: widget.userName,
        rating: _rating,
        comment: _commentController.text.trim(),
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Merci pour votre avis !'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur, veuillez réessayer.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              'Laisser un avis',
              style: GoogleFonts.dmSans(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Partagez votre expérience avec ce salon.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary500),
            ),
            const SizedBox(height: 24),

            // Star rating
            const Text(
              'Note',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand950),
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: () => setState(() => _rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      size: 38,
                      color: filled ? Colors.amber : AppColors.secondary300,
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 20),

            // Comment field
            const Text(
              'Commentaire (optionnel)',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand950),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _commentController,
              maxLines: 3,
              maxLength: 300,
              decoration: InputDecoration(
                hintText: 'Décrivez votre expérience...',
                hintStyle: const TextStyle(
                    color: AppColors.secondary400, fontSize: 13),
                filled: true,
                fillColor: AppColors.secondary50,
                contentPadding: const EdgeInsets.all(14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.secondary200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.secondary200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.brand400),
                ),
                counterStyle: const TextStyle(
                    fontSize: 11, color: AppColors.secondary400),
              ),
            ),
            const SizedBox(height: 20),

            // Submit button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _submitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2),
                      )
                    : const Text(
                        'Publier l\'avis',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Before/After card ───────────────────────────────────────────────────────

class _BeforeAfterCard extends StatefulWidget {
  const _BeforeAfterCard({
    required this.beforeUrl,
    required this.afterUrl,
    required this.label,
  });
  final String beforeUrl;
  final String afterUrl;
  final String label;

  @override
  State<_BeforeAfterCard> createState() => _BeforeAfterCardState();
}

class _BeforeAfterCardState extends State<_BeforeAfterCard> {
  double _sliderValue = 0.5;

  @override
  Widget build(BuildContext context) {
    const cardWidth = 220.0;
    const imageHeight = 150.0;

    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary200),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Slider comparison
          SizedBox(
            width: cardWidth,
            height: imageHeight,
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(11)),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final w = constraints.maxWidth;
                  final h = constraints.maxHeight;
                  final split = w * _sliderValue;

                  return GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _sliderValue =
                            (details.localPosition.dx / w).clamp(0.0, 1.0);
                      });
                    },
                    child: Stack(
                      children: [
                        // After image (full width behind)
                        Positioned.fill(
                          child: Image.network(
                            widget.afterUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Container(color: AppColors.secondary100),
                          ),
                        ),
                        // Before image (clipped)
                        Positioned.fill(
                          child: ClipRect(
                            clipper: _LeftClipper(split),
                            child: Image.network(
                              widget.beforeUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  Container(color: AppColors.secondary100),
                            ),
                          ),
                        ),
                        // Divider line
                        Positioned(
                          left: split - 1,
                          top: 0,
                          bottom: 0,
                          child: Container(
                            width: 2,
                            color: Colors.white,
                          ),
                        ),
                        // Handle
                        Positioned(
                          left: split - 12,
                          top: h / 2 - 12,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.drag_handle,
                              size: 14,
                              color: AppColors.brand600,
                            ),
                          ),
                        ),
                        // Labels
                        Positioned(
                          left: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Avant',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 9)),
                          ),
                        ),
                        Positioned(
                          right: 6,
                          bottom: 6,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text('Après',
                                style: TextStyle(
                                    color: Colors.white, fontSize: 9)),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          // Label
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Text(
              widget.label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brand950,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeftClipper extends CustomClipper<Rect> {
  _LeftClipper(this.width);
  final double width;

  @override
  Rect getClip(Size size) => Rect.fromLTWH(0, 0, width, size.height);

  @override
  bool shouldReclip(covariant _LeftClipper old) => old.width != width;
}
