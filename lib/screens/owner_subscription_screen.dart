import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/salon_model.dart';
import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/plan_config.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';
import '../widgets/bot_quota_card.dart';
import 'owner_upgrade_screen.dart';

/// "Mon abonnement" — central place for the owner to see current plan,
/// trial countdown, monthly revenue usage, and manage the subscription.
///
/// This screen is read-mostly; the upgrade/downgrade actions route to
/// `OwnerUpgradeScreen` (currently a dev bypass — real billing is wired
/// later via RevenueCat). Payment method management is handled natively
/// by the App Store / Play Store through RevenueCat, no Mon Salon UI needed.
class OwnerSubscriptionScreen extends ConsumerWidget {
  const OwnerSubscriptionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final salonAsync = ref.watch(ownerSalonProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.brand950, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          l?.tr('subscription.title') ?? 'Mon abonnement',
          style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              fontSize: 18),
        ),
      ),
      body: salonAsync.when(
        data: (salon) {
          if (salon == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _Body(salon: salon);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final SalonModel salon;
  const _Body({required this.salon});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CurrentPlanCard(salon: salon),
          const SizedBox(height: 12),
          if (salon.isEssentiel &&
              salon.trialEndsAt != null &&
              salon.trialEndsAt!.isAfter(DateTime.now()))
            _TrialCard(trialEndsAt: salon.trialEndsAt!),
          if (salon.isEssentiel &&
              salon.trialEndsAt != null &&
              salon.trialEndsAt!.isAfter(DateTime.now()))
            const SizedBox(height: 12),
          _FeaturesCard(salon: salon),
          const SizedBox(height: 16),
          // ── Upgrade / Downgrade actions ────────────────────────
          Text(
            l?.tr('subscription.change_plan') ?? 'Changer de plan',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.secondary600,
            ),
          ),
          const SizedBox(height: 8),
          // Plan navigation tiles. Order = lowest to highest, with the
          // current plan hidden. Direction-aware copy: a Business owner
          // sees "Downgrade to Essentiel", not "Upgrade to Essentiel".
          if (!salon.isFree)
            _ActionTile(
              icon: Icons.arrow_downward_rounded,
              color: AppColors.secondary500,
              title: l?.tr('subscription.downgrade_free') ??
                  'Passer au plan Free',
              subtitle: l?.tr('subscription.downgrade_free_desc') ??
                  'Gratuit, équipe limitée à 2 membres',
              onTap: () => _confirmCancelToFree(context),
            ),
          if (!salon.isEssentiel)
            _ActionTile(
              icon: salon.isBusiness
                  ? Icons.arrow_downward_rounded
                  : Icons.auto_awesome_rounded,
              color: salon.isBusiness
                  ? AppColors.secondary500
                  : AppColors.brand600,
              title: salon.isBusiness
                  ? (l?.tr('subscription.downgrade_essentiel') ??
                      'Passer au plan Essentiel')
                  : (l?.tr('subscription.upgrade_essentiel') ??
                      'Passer au plan Essentiel'),
              subtitle: salon.isBusiness
                  ? (l?.tr('subscription.downgrade_essentiel_desc') ??
                      'Équipe illimitée, sans assistante IA ni paiements en ligne')
                  : (salon.isTrialEligible
                      ? (l?.tr('subscription.upgrade_essentiel_desc') ??
                          'Équipe illimitée + 3 mois offerts')
                      : (l?.tr('subscription.upgrade_essentiel_desc_no_trial') ??
                          'Équipe illimitée')),
              trailing: _priceChip(
                context, PlanConfig.planEssentiel, salon.currency),
              onTap: () => _goToUpgrade(context, PlanConfig.planEssentiel),
            ),
          if (!salon.isBusiness)
            _ActionTile(
              icon: Icons.workspace_premium_rounded,
              color: Colors.purple,
              title: l?.tr('subscription.upgrade_business') ??
                  'Passer au plan Business',
              subtitle: l?.tr('subscription.upgrade_business_desc') ??
                  'Vidéos, vérif WhatsApp, chatbot WhatsApp IA',
              trailing:
                  _priceChip(context, PlanConfig.planBusiness, salon.currency),
              onTap: () => _goToUpgrade(context, PlanConfig.planBusiness),
            ),
          const SizedBox(height: 16),
          // ── Bot Zayna message quota (Business plan only) ──────
          if (salon.isBusiness) ...[
            Text(
              l?.tr('subscription.bot_section_title') ??
                  'Assistante WhatsApp Zayna',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.secondary600,
              ),
            ),
            const SizedBox(height: 8),
            BotQuotaCard(salonId: salon.id),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }

  Widget _priceChip(BuildContext context, String plan, String currency) {
    final price = PlanConfig.priceFor(plan, currency);
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        '${CurrencyHelper.format(price.toDouble(), currency)}${l?.tr('plan.perMonth') ?? '/mois'}',
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.brand700,
        ),
      ),
    );
  }

  void _goToUpgrade(BuildContext context, String targetPlan) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerUpgradeScreen(targetPlan: targetPlan),
      ),
    );
  }

  Future<void> _confirmCancelToFree(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final isAndroid = Platform.isAndroid;
    final bodyKey = isAndroid
        ? 'subscription.cancel_to_free_body_android'
        : 'subscription.cancel_to_free_body';
    final failedKey = isAndroid
        ? 'subscription.cancel_to_free_open_failed_android'
        : 'subscription.cancel_to_free_open_failed';
    final bodyFallback = isAndroid
        ? 'Pour passer au plan Free, résiliez votre abonnement via Play Store → Profil → Paiements et abonnements → Abonnements. Votre plan actuel reste actif jusqu\'à la fin du cycle de facturation, puis bascule automatiquement en Free.'
        : 'Pour passer au plan Free, résiliez votre abonnement via Réglages → Apple ID → Abonnements. Votre plan actuel reste actif jusqu\'à la fin du cycle de facturation, puis bascule automatiquement en Free.';
    final failedFallback = isAndroid
        ? 'Impossible d\'ouvrir Play Store. Allez manuellement dans Play Store → Profil → Paiements et abonnements → Abonnements.'
        : 'Impossible d\'ouvrir Réglages. Allez manuellement dans Réglages → Apple ID → Abonnements.';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l?.tr('subscription.cancel_to_free_title') ??
            'Passer au plan Free ?'),
        content: Text(l?.tr(bodyKey) ?? bodyFallback),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(
              l?.tr('subscription.cancel_to_free_open_settings') ??
                  'Ouvrir Réglages',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final uri = Uri.parse(
      isAndroid
          ? 'https://play.google.com/store/account/subscriptions'
          : 'https://apps.apple.com/account/subscriptions',
    );
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l?.tr(failedKey) ?? failedFallback)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
              '${l?.tr('common_error_short') ?? 'Erreur'} : $e')),
        );
      }
    }
  }
}

class _CurrentPlanCard extends StatelessWidget {
  final SalonModel salon;
  const _CurrentPlanCard({required this.salon});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = salon.isBusiness
        ? Colors.purple
        : salon.isEssentiel
            ? AppColors.brand600
            : AppColors.secondary500;
    final label = salon.isBusiness
        ? l?.tr('plan.business') ?? 'Business'
        : salon.isEssentiel
            ? l?.tr('plan.essential') ?? 'Essentiel'
            : l?.tr('plan.free') ?? 'Free';
    final price = PlanConfig.priceFor(salon.plan, salon.currency);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('subscription.current_plan_label') ?? 'Plan actuel',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                label,
                style: GoogleFonts.playfairDisplay(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              if (price > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    '${CurrencyHelper.format(price.toDouble(), salon.currency)}${l?.tr('plan.perMonth') ?? '/mois'}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrialCard extends StatelessWidget {
  final DateTime trialEndsAt;
  const _TrialCard({required this.trialEndsAt});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final now = DateTime.now();
    final remaining = trialEndsAt.difference(now);
    final daysLeft = remaining.inDays;
    final progress = (1 -
            (remaining.inSeconds /
                (PlanConfig.essentielTrialDays * 24 * 3600)))
        .clamp(0.0, 1.0);
    final isUrgent = daysLeft <= 7;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isUrgent ? Colors.amber.shade50 : AppColors.brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isUrgent ? Colors.amber.shade200 : AppColors.brand200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isUrgent ? Icons.warning_amber_rounded : Icons.timer_outlined,
                size: 18,
                color: isUrgent ? Colors.amber.shade800 : AppColors.brand700,
              ),
              const SizedBox(width: 8),
              Text(
                (l?.tr('subscription.trial_days_left') ??
                        'Plus que {days} jours d\'essai gratuit')
                    .replaceAll('{days}', daysLeft.toString()),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: isUrgent
                      ? Colors.amber.shade900
                      : AppColors.brand950,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.white,
              valueColor: AlwaysStoppedAnimation(
                isUrgent ? Colors.amber.shade700 : AppColors.brand600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            (l?.tr('subscription.trial_ends_on') ?? 'Expire le {date}')
                .replaceAll(
              '{date}',
              '${trialEndsAt.day.toString().padLeft(2, '0')}/${trialEndsAt.month.toString().padLeft(2, '0')}/${trialEndsAt.year}',
            ),
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.secondary500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeaturesCard extends StatelessWidget {
  final SalonModel salon;
  const _FeaturesCard({required this.salon});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final features = <_FeatureRow>[
      _FeatureRow(
        label: l?.tr('subscription.feat_bookings') ??
            'Réservations en ligne illimitées',
        enabled: true,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_team') ??
            'Gestion d\'équipe + agenda',
        enabled: true,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_ai') ??
            'Assistant IA + Réductions intelligentes',
        enabled: true,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_unlimited_team') ??
            'Équipe illimitée',
        enabled: !salon.isFree,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_videos') ??
            'Vidéos dans la galerie et les services',
        enabled: salon.isBusiness,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_sms') ??
            'Vérification par WhatsApp des réservations',
        enabled: salon.isBusiness,
      ),
      _FeatureRow(
        label: l?.tr('subscription.feat_chatbot') ??
            'Chatbot WhatsApp IA',
        enabled: salon.isBusiness,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('subscription.features_label') ??
                'Fonctionnalités incluses',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 10),
          ...features.map((f) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      f.enabled
                          ? Icons.check_circle_rounded
                          : Icons.cancel_outlined,
                      size: 16,
                      color: f.enabled
                          ? AppColors.brand600
                          : AppColors.secondary300,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f.label,
                        style: TextStyle(
                          fontSize: 12,
                          color: f.enabled
                              ? AppColors.brand950
                              : AppColors.secondary400,
                          decoration: f.enabled
                              ? null
                              : TextDecoration.lineThrough,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _FeatureRow {
  final String label;
  final bool enabled;
  _FeatureRow({required this.label, required this.enabled});
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: AppColors.brand950),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: AppColors.secondary500),
        ),
        trailing: trailing ??
            const Icon(Icons.chevron_right_rounded,
                color: AppColors.secondary300, size: 20),
      ),
    );
  }
}

