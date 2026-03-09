import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../models/salon_model.dart';
import '../providers/auth_providers.dart';
import '../services/database_service.dart';
import 'client_salon_profile_screen.dart';

// ── Screen ───────────────────────────────────────────────────────────────────

class ClientFavoritesScreen extends ConsumerWidget {
  const ClientFavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userStreamProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        slivers: [
          // ── App bar ────────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            centerTitle: false,
            title: Text(
              'Mes favoris',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
          ),

          // ── Content ────────────────────────────────────────────────────────
          userAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                  child: CircularProgressIndicator(color: AppColors.brand600)),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(child: Text('Erreur : $e')),
            ),
            data: (user) {
              if (user == null || user.favorites.isEmpty) {
                return const SliverFillRemaining(child: _EmptyState());
              }
              return _FavoritesList(
                favoriteIds: user.favorites,
                userId: user.id,
                onRemoved: () {}, // stream auto-updates — no invalidation needed
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Favorites list ────────────────────────────────────────────────────────────

class _FavoritesList extends StatelessWidget {
  const _FavoritesList({
    required this.favoriteIds,
    required this.userId,
    required this.onRemoved,
  });
  final List<String> favoriteIds;
  final String userId;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SalonModel>>(
      stream: DatabaseService().getSalonsByIds(favoriteIds),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SliverFillRemaining(
            child: Center(
                child: CircularProgressIndicator(color: AppColors.brand600)),
          );
        }
        final salons = snap.data ?? [];
        if (salons.isEmpty) {
          return const SliverFillRemaining(child: _EmptyState());
        }
        return SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FavoriteCard(
                  salon: salons[i],
                  userId: userId,
                  onRemoved: onRemoved,
                ),
              ),
              childCount: salons.length,
            ),
          ),
        );
      },
    );
  }
}

// ── Favorite card ─────────────────────────────────────────────────────────────

class _FavoriteCard extends StatefulWidget {
  const _FavoriteCard({
    required this.salon,
    required this.userId,
    required this.onRemoved,
  });
  final SalonModel salon;
  final String userId;
  final VoidCallback onRemoved;

  @override
  State<_FavoriteCard> createState() => _FavoriteCardState();
}

class _FavoriteCardState extends State<_FavoriteCard> {
  bool _removing = false;

  Future<void> _remove() async {
    setState(() => _removing = true);
    try {
      await DatabaseService().toggleFavorite(widget.userId, widget.salon.id, false);
      widget.onRemoved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur : $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _removing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.salon;
    final hasImage = s.images.isNotEmpty;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ClientSalonProfileScreen(salon: s),
        ),
      ),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Stack(
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16)),
                  child: hasImage
                      ? Image.network(
                          s.images.first,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _imageFallback(),
                        )
                      : _imageFallback(),
                ),

                // Rating badge
                Positioned(
                  top: 10,
                  left: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: Color(0xFFD97706)),
                        const SizedBox(width: 3),
                        Text(
                          '${s.rating.toStringAsFixed(1)} (${s.reviewCount})',
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

                // Unfavorite button
                Positioned(
                  top: 10,
                  right: 10,
                  child: GestureDetector(
                    onTap: _removing ? null : _remove,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.92),
                        shape: BoxShape.circle,
                      ),
                      child: _removing
                          ? const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.brand600),
                            )
                          : const Icon(Icons.favorite_rounded,
                              color: AppColors.brand500, size: 18),
                    ),
                  ),
                ),
              ],
            ),

            // Info
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.name,
                          style: GoogleFonts.dmSans(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on_outlined,
                                size: 12, color: AppColors.brand400),
                            const SizedBox(width: 3),
                            Expanded(
                              child: Text(
                                s.city,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.secondary500),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.brand50,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            s.category,
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.brand600,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ClientSalonProfileScreen(salon: s),
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                      textStyle: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                    child: const Text('Réserver'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _imageFallback() => Container(
        height: 150,
        width: double.infinity,
        color: AppColors.brand50,
        child: const Center(
          child: Icon(Icons.storefront_outlined,
              size: 40, color: AppColors.brand200),
        ),
      );
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppColors.brand50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.favorite_rounded,
                  size: 48, color: AppColors.brand200),
            ),
            const SizedBox(height: 24),
            Text(
              'Aucun favori pour l\'instant',
              style: GoogleFonts.dmSans(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Explorez les salons et appuyez sur ♡\npour les retrouver ici facilement.',
              style: TextStyle(color: AppColors.secondary400, fontSize: 13, height: 1.5),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
