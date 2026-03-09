import 'dart:math' show cos, sqrt, asin, pi;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:geolocator/geolocator.dart';

import '../theme/app_colors.dart';
import '../models/salon_model.dart';
import '../models/user_model.dart';
import '../models/appointment_model.dart';
import '../services/database_service.dart';
import 'client_salon_profile_screen.dart';

class ClientAllRecommendedScreen extends StatefulWidget {
  const ClientAllRecommendedScreen({
    super.key,
    this.user,
    this.pastAppointments = const [],
    this.userPosition,
  });

  final UserModel? user;
  final List<AppointmentModel> pastAppointments;
  final Position? userPosition;

  @override
  State<ClientAllRecommendedScreen> createState() =>
      _ClientAllRecommendedScreenState();
}

class _ClientAllRecommendedScreenState
    extends State<ClientAllRecommendedScreen> {
  final _db = DatabaseService();

  // ── Scoring helpers ─────────────────────────────────────────────────────────

  double _distance(double lat2, double lon2) {
    if (widget.userPosition == null) return 0.0;
    const p = pi / 180;
    final a = 0.5 -
        cos((lat2 - widget.userPosition!.latitude) * p) / 2 +
        cos(widget.userPosition!.latitude * p) *
            cos(lat2 * p) *
            (1 - cos((lon2 - widget.userPosition!.longitude) * p)) /
            2;
    return 12742 * asin(sqrt(a));
  }

  double _baseScore(SalonModel salon) {
    final ratingScore = salon.rating / 5.0;
    if (widget.userPosition == null ||
        salon.latitude == null ||
        salon.longitude == null) {
      return ratingScore;
    }
    const double maxKm = 50.0;
    final proximity =
        (1 - (_distance(salon.latitude!, salon.longitude!) / maxKm))
            .clamp(0.0, 1.0);
    return 0.6 * ratingScore + 0.4 * proximity;
  }

  double _score(SalonModel salon, Map<String, dynamic> service) {
    double score = _baseScore(salon);

    if (widget.user?.favorites.contains(salon.id) ?? false) score += 0.15;

    final visitedIds =
        widget.pastAppointments.map((a) => a.salonId).toSet();
    if (visitedIds.contains(salon.id)) score += 0.25;

    if (widget.pastAppointments.isNotEmpty) {
      final keywords = widget.pastAppointments
          .map((a) => a.serviceName.toLowerCase())
          .expand((n) => n.split(' ').where((w) => w.length > 3))
          .toSet();
      final title =
          (service['title'] ?? service['name'] ?? '').toLowerCase();
      final cat = (service['category'] ?? '').toLowerCase();
      for (final kw in keywords) {
        if (title.contains(kw) || cat.contains(kw)) {
          score += 0.15;
          break;
        }
      }
    }
    return score;
  }

  List<Map<String, dynamic>> _buildSorted(List<SalonModel> salons) {
    final all = <Map<String, dynamic>>[];
    for (final salon in salons) {
      for (final service in salon.services) {
        all.add({'salon': salon, 'service': service});
      }
    }
    all.sort((a, b) =>
        _score(b['salon'], b['service'])
            .compareTo(_score(a['salon'], a['service'])));
    return all;
  }

  // ── UI ───────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            pinned: true,
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
                Text(
                  'Recommandé pour vous',
                  style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),

          // Content
          StreamBuilder<List<SalonModel>>(
            stream: _db.salons,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const SliverFillRemaining(
                  child: Center(
                    child: CircularProgressIndicator(
                        color: AppColors.brand600),
                  ),
                );
              }

              final salons = snap.data ?? [];
              final items = _buildSorted(salons);

              if (items.isEmpty) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.auto_awesome_outlined,
                            size: 52, color: AppColors.secondary200),
                        const SizedBox(height: 16),
                        Text(
                          'Aucune recommandation pour l\'instant',
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            color: AppColors.secondary400,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, i) {
                      final SalonModel salon = items[i]['salon'];
                      final Map<String, dynamic> service =
                          items[i]['service'];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _ServiceCard(
                            salon: salon, service: service),
                      );
                    },
                    childCount: items.length,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Service card ──────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.salon, required this.service});
  final SalonModel salon;
  final Map<String, dynamic> service;

  @override
  Widget build(BuildContext context) {
    final name = service['name'] ?? service['title'] ?? 'Service';
    final price = service['price'] ?? 0;
    final duration = service['duration'] ?? 0;
    final imageUrl = salon.images.isNotEmpty
        ? salon.images[0]
        : 'https://images.unsplash.com/photo-1560066984-138dadb4c035?ixlib=rb-4.0.3&auto=format&fit=crop&w=300&q=80';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ClientSalonProfileScreen(salon: salon)),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.secondary100),
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
            // Image
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16)),
              child: Image.network(
                imageUrl,
                width: 90,
                height: 90,
                fit: BoxFit.cover,
                errorBuilder: (_, e, s) => Container(
                  width: 90,
                  height: 90,
                  color: AppColors.secondary100,
                  child: const Icon(Icons.storefront_outlined,
                      color: AppColors.secondary300, size: 28),
                ),
              ),
            ),

            // Info
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Service name
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppColors.brand950,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Salon name
                    Text(
                      salon.name,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Rating
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFF59E0B)),
                        const SizedBox(width: 3),
                        Text(
                          salon.rating.toStringAsFixed(1),
                          style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.secondary700),
                        ),
                        const SizedBox(width: 8),
                        // Duration
                        const Icon(Icons.schedule_outlined,
                            size: 12, color: AppColors.secondary400),
                        const SizedBox(width: 3),
                        Text(
                          '$duration min',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary500),
                        ),
                        const Spacer(),
                        // Price
                        Text(
                          '$price MAD',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
