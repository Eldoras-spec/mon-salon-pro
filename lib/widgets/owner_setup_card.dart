import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/owner_providers.dart';
import '../providers/setup_tasks_provider.dart';
import '../screens/owner_boutique_screen.dart';
import '../screens/owner_promotions_screen.dart';
import '../screens/owner_salon_screen.dart';
import '../screens/owner_services_screen.dart';
import '../screens/owner_set_location_screen.dart';
import '../screens/owner_team_screen.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';
import '../utils/page_transitions.dart';

class OwnerSetupCard extends ConsumerStatefulWidget {
  const OwnerSetupCard({super.key});

  @override
  ConsumerState<OwnerSetupCard> createState() => _OwnerSetupCardState();
}

class _OwnerSetupCardState extends ConsumerState<OwnerSetupCard> {
  bool _collapsed = false;
  static const _prefsKey = 'ownerSetupCollapsed';

  @override
  void initState() {
    super.initState();
    _loadCollapsed();
  }

  Future<void> _loadCollapsed() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() => _collapsed = prefs.getBool(_prefsKey) ?? false);
    }
  }

  Future<void> _toggleCollapsed() async {
    setState(() => _collapsed = !_collapsed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKey, _collapsed);
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(setupTasksProvider);
    if (tasks.isEmpty) return const SizedBox.shrink();
    final l = AppLocalizations.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: _toggleCollapsed,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDBEAFE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.rocket_launch_rounded,
                        color: Color(0xFF2563EB), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l?.tr('owner_setup_title') ?? 'Configurer votre salon',
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand950),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2563EB),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _collapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: AppColors.secondary500,
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          if (!_collapsed) ...[
            ...tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final task = entry.value;
              return Column(
                children: [
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _SetupTile(task: task),
                ],
              );
            }),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

class _SetupTile extends ConsumerWidget {
  const _SetupTile({required this.task});
  final SetupTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final meta = _meta(task.key, l);

    return InkWell(
      onTap: () => _navigate(context, ref, task.key),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: meta.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(meta.icon, color: meta.fg, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    meta.title,
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.brand950),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta.subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.secondary400),
                  ),
                ],
              ),
            ),
            // Location is required (a salon must be findable) → not dismissible.
            if (task.key != SetupTaskKey.location)
              IconButton(
                icon: const Icon(Icons.close_rounded,
                    size: 16, color: AppColors.secondary300),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: 32, minHeight: 32),
                tooltip: l?.tr('owner_setup_dismiss') ?? 'Masquer',
                onPressed: () async {
                  final salon = ref.read(ownerSalonProvider).value;
                  if (salon == null) return;
                  await dismissSetupTask(salon.id, task.key);
                },
              ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 12, color: AppColors.secondary300),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, WidgetRef ref, SetupTaskKey key) {
    switch (key) {
      case SetupTaskKey.location:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => OwnerSetLocationScreen(
                salon: ref.read(ownerSalonProvider).value),
          ),
        );
        break;
      case SetupTaskKey.googleReview:
      case SetupTaskKey.firstPromo:
      case SetupTaskKey.loyalty:
      case SetupTaskKey.smartPromotions:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerPromotionsScreen()),
        );
        break;
      case SetupTaskKey.firstProduct:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerBoutiqueScreen()),
        );
        break;
      case SetupTaskKey.firstPack:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const OwnerServicesScreen(initialTab: 1)),
        );
        break;
      case SetupTaskKey.salonImages:
      case SetupTaskKey.beforeAfter:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerSalonScreen()),
        );
        break;
      case SetupTaskKey.team:
        Navigator.of(context).pushSlide(const OwnerTeamScreen());
        break;
      case SetupTaskKey.classifyEmployees:
        Navigator.of(context)
            .pushSlide(const OwnerTeamScreen(initialShowByService: true));
        break;
    }
  }

  _TileMeta _meta(SetupTaskKey key, AppLocalizations? l) {
    switch (key) {
      case SetupTaskKey.location:
        return _TileMeta(
          icon: Icons.location_on_outlined,
          fg: const Color(0xFFDC2626),
          bg: const Color(0xFFFEE2E2),
          title: l?.tr('owner_setup_location_title') ??
              'Ajoutez la localisation de votre salon',
          subtitle: l?.tr('owner_setup_location_sub') ??
              'Indispensable pour que vos clients vous trouvent',
        );
      case SetupTaskKey.googleReview:
        return _TileMeta(
          icon: Icons.star_outline_rounded,
          fg: const Color(0xFFCA8A04),
          bg: const Color(0xFFFEF9C3),
          title: l?.tr('owner_setup_google_title') ??
              'Activer les récompenses avis Google',
          subtitle: l?.tr('owner_setup_google_sub') ??
              'Obtenez plus d\'avis en offrant une réduction',
        );
      case SetupTaskKey.firstPromo:
        return _TileMeta(
          icon: Icons.local_offer_outlined,
          fg: const Color(0xFFDB2777),
          bg: const Color(0xFFFCE7F3),
          title:
              l?.tr('owner_setup_promo_title') ?? 'Créer votre première promo',
          subtitle: l?.tr('owner_setup_promo_sub') ??
              'Attirez de nouveaux clients avec une offre',
        );
      case SetupTaskKey.firstProduct:
        return _TileMeta(
          icon: Icons.shopping_bag_outlined,
          fg: const Color(0xFF16A34A),
          bg: const Color(0xFFDCFCE7),
          title: l?.tr('owner_setup_product_title') ??
              'Ajouter vos premiers produits',
          subtitle:
              l?.tr('owner_setup_product_sub') ?? 'Vendez via votre boutique',
        );
      case SetupTaskKey.firstPack:
        return _TileMeta(
          icon: Icons.inventory_2_outlined,
          fg: const Color(0xFF0D9488),
          bg: const Color(0xFFCCFBF1),
          title: l?.tr('owner_setup_pack_title') ??
              'Créer votre premier pack',
          subtitle: l?.tr('owner_setup_pack_sub') ??
              'Regroupez des prestations à prix réduit',
        );
      case SetupTaskKey.salonImages:
        return _TileMeta(
          icon: Icons.photo_library_outlined,
          fg: const Color(0xFF7C3AED),
          bg: const Color(0xFFEDE9FE),
          title: l?.tr('owner_setup_images_title') ??
              'Ajouter des photos de votre salon',
          subtitle: l?.tr('owner_setup_images_sub') ??
              'Au moins 3 photos recommandées',
        );
      case SetupTaskKey.team:
        return _TileMeta(
          icon: Icons.groups_outlined,
          fg: const Color(0xFF0891B2),
          bg: const Color(0xFFCFFAFE),
          title: l?.tr('owner_setup_team_title') ??
              'Ajouter des membres à votre équipe',
          subtitle: l?.tr('owner_setup_team_sub') ??
              'Permettez à vos collaborateurs d\'accéder à l\'app',
        );
      case SetupTaskKey.loyalty:
        return _TileMeta(
          icon: Icons.card_giftcard_rounded,
          fg: const Color(0xFFEA580C),
          bg: const Color(0xFFFFEDD5),
          title: l?.tr('owner_setup_loyalty_title') ??
              'Activer la fidélité',
          subtitle: l?.tr('owner_setup_loyalty_sub') ??
              'Fidélisez vos clients avec des points',
        );
      case SetupTaskKey.smartPromotions:
        return _TileMeta(
          icon: Icons.auto_awesome_rounded,
          fg: const Color(0xFF6366F1),
          bg: const Color(0xFFE0E7FF),
          title: l?.tr('owner_setup_smart_title') ??
              'Activer les Réductions intelligentes',
          subtitle: l?.tr('owner_setup_smart_sub') ??
              'L\'IA crée des promos ciblées automatiquement',
        );
      case SetupTaskKey.classifyEmployees:
        return _TileMeta(
          icon: Icons.leaderboard_outlined,
          fg: const Color(0xFF0EA5E9),
          bg: const Color(0xFFE0F2FE),
          title: l?.tr('owner_setup_classify_title') ??
              'Classez vos employés par prestation',
          subtitle: l?.tr('owner_setup_classify_sub') ??
              'Définissez l\'ordre de priorité pour l\'attribution auto',
        );
      case SetupTaskKey.beforeAfter:
        return _TileMeta(
          icon: Icons.compare_rounded,
          fg: const Color(0xFFEC4899),
          bg: const Color(0xFFFCE7F3),
          title: l?.tr('owner_setup_before_after_title') ??
              'Ajoutez des photos Avant/Après',
          subtitle: l?.tr('owner_setup_before_after_sub') ??
              'Mettez en avant vos meilleurs résultats',
        );
    }
  }
}

class _TileMeta {
  _TileMeta({
    required this.icon,
    required this.fg,
    required this.bg,
    required this.title,
    required this.subtitle,
  });
  final IconData icon;
  final Color fg;
  final Color bg;
  final String title;
  final String subtitle;
}
