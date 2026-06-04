import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../providers/owner_tasks_provider.dart';
import '../screens/conversations_screen.dart';
import '../screens/owner_boutique_screen.dart';
import '../screens/owner_inventory_screen.dart';
import '../screens/owner_no_show_risks_screen.dart';
import '../screens/owner_promotions_screen.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

class OwnerTasksCard extends ConsumerStatefulWidget {
  const OwnerTasksCard({super.key});

  @override
  ConsumerState<OwnerTasksCard> createState() => _OwnerTasksCardState();
}

class _OwnerTasksCardState extends ConsumerState<OwnerTasksCard> {
  bool _collapsed = false;
  static const _prefsKey = 'ownerTasksCollapsed';

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
    final tasks = ref.watch(ownerTasksProvider);
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
          // Header (tap to collapse/expand)
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
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.flash_on_rounded,
                        color: Color(0xFFD97706), size: 18),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    l?.tr('owner_tasks_title') ?? 'Tâches à faire',
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
                      color: AppColors.brand600,
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
            // Tasks list
            ...tasks.asMap().entries.map((entry) {
              final i = entry.key;
              final task = entry.value;
              return Column(
                children: [
                  if (i > 0)
                    const Divider(height: 1, indent: 16, endIndent: 16),
                  _TaskTile(task: task),
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

class _TaskTile extends ConsumerWidget {
  const _TaskTile({required this.task});
  final OwnerTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final meta = _taskMeta(task.type, task.count, l);

    return InkWell(
      onTap: () => _navigate(context, ref, task.type),
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
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: AppColors.secondary300),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, WidgetRef ref, OwnerTaskType type) {
    final salon = ref.read(ownerSalonProvider).value;
    final uid = ref.read(authStateProvider).value?.uid ?? '';
    if (salon == null) return;

    switch (type) {
      case OwnerTaskType.messages:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ConversationsScreen(
              currentUserId: uid,
              isClient: false,
              salonId: salon.id,
            ),
          ),
        );
        break;
      case OwnerTaskType.pendingOrders:
      case OwnerTaskType.ordersToDeliver:
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => const OwnerBoutiqueScreen(initialTab: 1)),
        );
        break;
      case OwnerTaskType.noShowRisk:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerNoShowRisksScreen()),
        );
        break;
      case OwnerTaskType.badReviews:
        // No dedicated reply screen yet — just surface guidance.
        _showBadReviewsInfo(context);
        break;
      case OwnerTaskType.pendingRewards:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerPromotionsScreen()),
        );
        break;
      case OwnerTaskType.lowStock:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const OwnerInventoryScreen()),
        );
        break;
    }
  }

  void _showBadReviewsInfo(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B), size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l?.tr('owner_tasks_bad_reviews_dialog_title') ?? 'Avis négatifs',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        content: Text(
          l?.tr('owner_tasks_bad_reviews_dialog_body') ??
              'Contactez directement les clients non satisfaits pour comprendre le souci et trouver une solution. Cela peut transformer un avis négatif en client fidèle.',
          style: const TextStyle(fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l?.tr('common_ok') ?? 'OK'),
          ),
        ],
      ),
    );
  }

  _TaskMeta _taskMeta(
      OwnerTaskType type, int count, AppLocalizations? l) {
    switch (type) {
      case OwnerTaskType.messages:
        return _TaskMeta(
          icon: Icons.chat_bubble_outline_rounded,
          fg: const Color(0xFF2563EB),
          bg: const Color(0xFFDBEAFE),
          title:
              (l?.tr('owner_tasks_messages_title') ?? '{count} message(s) non lu(s)')
                  .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_messages_sub') ??
              'Messages clients et demandes personnalisées',
        );
      case OwnerTaskType.pendingOrders:
        return _TaskMeta(
          icon: Icons.shopping_bag_outlined,
          fg: const Color(0xFF16A34A),
          bg: const Color(0xFFDCFCE7),
          title: (l?.tr('owner_tasks_orders_title') ??
                  '{count} commande(s) à confirmer')
              .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_orders_sub') ?? 'Boutique — attente validation',
        );
      case OwnerTaskType.ordersToDeliver:
        return _TaskMeta(
          icon: Icons.local_shipping_outlined,
          fg: const Color(0xFF0EA5E9),
          bg: const Color(0xFFE0F2FE),
          title: (l?.tr('owner_tasks_orders_to_deliver_title') ??
                  '{count} commande(s) à livrer')
              .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_orders_to_deliver_sub') ??
              'Boutique — confirmées, en attente d\'expédition',
        );
      case OwnerTaskType.noShowRisk:
        return _TaskMeta(
          icon: Icons.warning_amber_rounded,
          fg: const Color(0xFFEA580C),
          bg: const Color(0xFFFFEDD5),
          title: (l?.tr('owner_tasks_noshow_title') ??
                  '{count} RDV à risque d\'annulation')
              .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_noshow_sub') ??
              'Clients au taux d\'annulation élevé — confirmer',
        );
      case OwnerTaskType.badReviews:
        return _TaskMeta(
          icon: Icons.warning_amber_rounded,
          fg: const Color(0xFFDC2626),
          bg: const Color(0xFFFEE2E2),
          title: (l?.tr('owner_tasks_bad_reviews_title') ??
                  '{count} avis négatif(s) récent(s)')
              .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_bad_reviews_sub') ??
              'Avis ≤ 2 étoiles des 7 derniers jours',
        );
      case OwnerTaskType.pendingRewards:
        return _TaskMeta(
          icon: Icons.star_outline_rounded,
          fg: const Color(0xFFCA8A04),
          bg: const Color(0xFFFEF9C3),
          title: (l?.tr('owner_tasks_rewards_title') ??
                  '{count} avis Google à valider')
              .replaceAll('{count}', '$count'),
          subtitle: l?.tr('owner_tasks_rewards_sub') ??
              'Clients en attente de leur code promo',
        );
      case OwnerTaskType.lowStock:
        return _TaskMeta(
          icon: Icons.inventory_2_outlined,
          fg: const Color(0xFFEA580C),
          bg: const Color(0xFFFFEDD5),
          title: (l?.tr('owner_tasks_stock_title') ??
                  '{count} produit(s) en stock faible')
              .replaceAll('{count}', '$count'),
          subtitle:
              l?.tr('owner_tasks_stock_sub') ?? 'Réapprovisionnement conseillé',
        );
    }
  }
}

class _TaskMeta {
  _TaskMeta({
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
