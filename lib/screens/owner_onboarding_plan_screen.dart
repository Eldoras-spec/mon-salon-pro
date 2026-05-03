import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_localizations.dart';
import '../services/plan_config.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';
import '../widgets/custom_button.dart';
import 'owner_onboarding_step2_screen.dart';

/// Plan selection screen — shown between step 1 and step 2.
///
/// The currency picked at step 1 is used to display localized prices.
/// The selected plan is saved into `salonData['plan']` and consumed by
/// step 4 when the salon doc is created. Business is the only plan that
/// would normally require immediate payment; for now we bypass real
/// billing (TODO: wire RevenueCat when integration starts).
class OwnerOnboardingPlanScreen extends StatefulWidget {
  final Map<String, dynamic> salonData;
  const OwnerOnboardingPlanScreen({super.key, required this.salonData});

  @override
  State<OwnerOnboardingPlanScreen> createState() =>
      _OwnerOnboardingPlanScreenState();
}

class _OwnerOnboardingPlanScreenState extends State<OwnerOnboardingPlanScreen> {
  String _selectedPlan = PlanConfig.planEssentiel;

  String get _currency => widget.salonData['currency'] as String? ?? 'MAD';

  void _next() {
    final updated = Map<String, dynamic>.from(widget.salonData);
    updated['plan'] = _selectedPlan;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerOnboardingStep2Screen(salonData: updated),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Nav row ─────────────────────────────────────────────
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          border: Border.all(color: AppColors.secondary100),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_back,
                            size: 12, color: AppColors.secondary500),
                      ),
                      label: Text(
                        l?.tr('onboarding_back') ?? 'Retour',
                        style: const TextStyle(
                            color: AppColors.secondary500,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Step header ─────────────────────────────────────────
                Text(
                  l?.tr('onboarding_plan_step') ?? 'Étape 2 sur 6',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand600),
                ),
                const SizedBox(height: 6),
                Text(
                  l?.tr('onboarding_plan_title') ?? 'Choisissez votre plan',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l?.tr('onboarding_plan_subtitle') ??
                      'Vous pourrez changer de plan à tout moment depuis votre espace.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondary500,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 24),

                // ── Plan cards ──────────────────────────────────────────
                _PlanCard(
                  plan: PlanConfig.planFree,
                  currency: _currency,
                  selected: _selectedPlan == PlanConfig.planFree,
                  onTap: () => setState(() => _selectedPlan = PlanConfig.planFree),
                  title: l?.tr('plan.free') ?? 'Free',
                  subtitle: l?.tr('plan.freeDesc') ??
                      'Toutes les fonctionnalités essentielles, équipe limitée à 2 membres.',
                  features: [
                    l?.tr('plan.free_f1') ?? 'Réservations en ligne illimitées',
                    l?.tr('plan.free_f2') ?? 'Calendrier et gestion des rendez-vous',
                    l?.tr('plan.free_f3') ?? "Gestion d'équipe (gérant + membres)",
                    l?.tr('plan.free_f4') ?? 'Gestion des congés et créneaux bloqués',
                    l?.tr('plan.free_f5') ?? 'Notifications push (rappels, nouveaux RDV)',
                    l?.tr('plan.free_f6') ?? 'Récompense avis Google automatique',
                    l?.tr('plan.free_f7') ?? 'Promotions et codes promo',
                    l?.tr('plan.free_f8') ?? 'Suivi des revenus et charges',
                    l?.tr('plan.free_f9') ?? 'Boutique en ligne',
                    l?.tr('plan.free_f10') ?? 'Assistant IA (résumé, suggestions, insights)',
                    l?.tr('plan.free_f11') ?? 'Prédiction IA des no-show',
                    l?.tr('plan.free_f12') ?? "Réductions intelligentes générées par l'IA",
                    l?.tr('plan.free_f13') ?? 'Confirmation de RDV par WhatsApp',
                    l?.tr('plan.free_f14') ??
                        'Paiements par carte (5 % de commission)',
                  ],
                  collapsedFeatureCount: 6,
                  showMoreLabel: l?.tr('plan.show_more') ?? 'Afficher plus',
                  showLessLabel: l?.tr('plan.show_less') ?? 'Afficher moins',
                  restrictions: [
                    l?.tr('plan.free_team_cap') ??
                        'Équipe limitée à 2 membres',
                  ],
                ),
                const SizedBox(height: 12),
                _PlanCard(
                  plan: PlanConfig.planEssentiel,
                  currency: _currency,
                  selected: _selectedPlan == PlanConfig.planEssentiel,
                  onTap: () => setState(
                      () => _selectedPlan = PlanConfig.planEssentiel),
                  badge: l?.tr('plan.recommended') ?? 'RECOMMANDÉ',
                  trial: l?.tr('plan.essentielTrial') ?? '3 mois offerts',
                  title: l?.tr('plan.essential') ?? 'Essentiel',
                  subtitle: l?.tr('plan.essentialDesc') ??
                      'Tout le Free + équipe illimitée.',
                  features: [
                    l?.tr('plan.ess_f1') ?? 'Tout le plan Free',
                    l?.tr('plan.ess_f2') ?? 'Employés illimités',
                    l?.tr('plan.ess_f3') ?? 'Support prioritaire',
                    l?.tr('plan.ess_f4') ??
                        'Rappels automatiques de RDV par WhatsApp',
                    l?.tr('plan.ess_f5') ??
                        'Paiements par carte (3 % de commission)',
                  ],
                ),
                const SizedBox(height: 12),
                _PlanCard(
                  plan: PlanConfig.planBusiness,
                  currency: _currency,
                  selected: _selectedPlan == PlanConfig.planBusiness,
                  onTap: () => setState(
                      () => _selectedPlan = PlanConfig.planBusiness),
                  highlight: true,
                  title: l?.tr('plan.business') ?? 'Business',
                  subtitle: l?.tr('plan.businessDesc') ??
                      'Tout l\'Essentiel + outils avancés pro.',
                  features: [
                    l?.tr('plan.biz_f1') ?? 'Tout le plan Essentiel',
                    l?.tr('plan.biz_f2') ?? 'Vidéos dans galerie + services',
                    l?.tr('plan.biz_f3') ??
                        'Vérification par WhatsApp des réservations',
                    l?.tr('plan.biz_f4') ??
                        'Assistant WhatsApp IA (1000 messages/mois inclus)',
                    l?.tr('plan.biz_f5') ??
                        'Paiements par carte (1 % de commission)',
                    l?.tr('plan.biz_f6') ??
                        'Badge Business + priorité dans les résultats',
                  ],
                ),
                const SizedBox(height: 24),

                // ── Continue ────────────────────────────────────────────
                CustomButton(
                  text: l?.tr('onboarding_plan_continue') ??
                      'Continuer avec ce plan',
                  onPressed: _next,
                  icon: Icons.arrow_forward,
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    l?.tr('onboarding_plan_change_later') ??
                        'Vous pourrez changer de plan plus tard.',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.secondary400),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlanCard extends StatefulWidget {
  final String plan;
  final String currency;
  final bool selected;
  final VoidCallback onTap;
  final String? badge;
  final String? trial;
  final bool highlight;
  final String title;
  final String subtitle;
  final List<String> features;
  // If set, only the first N features are shown and the rest are hidden
  // behind a "Show more" toggle.
  final int? collapsedFeatureCount;
  final String? showMoreLabel;
  final String? showLessLabel;
  final List<String> restrictions;

  const _PlanCard({
    required this.plan,
    required this.currency,
    required this.selected,
    required this.onTap,
    this.badge,
    this.trial,
    this.highlight = false,
    required this.title,
    required this.subtitle,
    required this.features,
    this.collapsedFeatureCount,
    this.showMoreLabel,
    this.showLessLabel,
    this.restrictions = const [],
  });

  @override
  State<_PlanCard> createState() => _PlanCardState();
}

class _PlanCardState extends State<_PlanCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final plan = widget.plan;
    final currency = widget.currency;
    final selected = widget.selected;
    final badge = widget.badge;
    final trial = widget.trial;
    final highlight = widget.highlight;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final restrictions = widget.restrictions;
    final cap = widget.collapsedFeatureCount;
    final visibleFeatures = (cap != null && !_expanded)
        ? widget.features.take(cap).toList()
        : widget.features;
    final hasHiddenFeatures =
        cap != null && widget.features.length > cap;
    final price = PlanConfig.priceFor(plan, currency);
    final isFree = price == 0;
    final borderColor = selected
        ? AppColors.brand600
        : (highlight ? AppColors.brand200 : AppColors.secondary200);
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: highlight ? AppColors.brand50.withValues(alpha: 0.35) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: selected ? 2 : 1),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.brand600.withValues(alpha: 0.10),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Badge row ──────────────────────────────────────────────
            if (badge != null || trial != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (badge != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.brand600,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    if (trial != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          trial,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            // ── Title + radio ──────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.playfairDisplay(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppColors.brand600
                          : AppColors.secondary300,
                      width: 2,
                    ),
                    color: selected ? AppColors.brand600 : Colors.transparent,
                  ),
                  child: selected
                      ? const Icon(Icons.check, color: Colors.white, size: 14)
                      : null,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Price ──────────────────────────────────────────────────
            if (isFree)
              Text(
                l?.tr('plan.freePrice') ?? 'Gratuit',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand950,
                ),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    CurrencyHelper.format(price.toDouble(), currency),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand950,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      l?.tr('plan.perMonth') ?? '/mois',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 14),

            // ── Restrictions (shown first, right under the price) ──────
            ...restrictions.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          r,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),

            // ── Features ───────────────────────────────────────────────
            ...visibleFeatures.map((f) {
              // The Business "Assistant WhatsApp IA …" line gets a tappable
              // info icon that opens the Zayna features page in the browser.
              // Keyed off the Business-plan label since that's the only
              // feature wired to the marketing page today.
              final isZaynaLine = f.contains('WhatsApp IA');
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 16, color: AppColors.brand600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        f,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.brand950,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (isZaynaLine) ...[
                      const SizedBox(width: 6),
                      InkWell(
                        onTap: () => _showZaynaFeaturesSheet(context),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: AppColors.brand50,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: AppColors.brand200, width: 1),
                          ),
                          child: const Icon(Icons.info_outline_rounded,
                              size: 13, color: AppColors.brand600),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            }),
            if (hasHiddenFeatures)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => setState(() => _expanded = !_expanded),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          _expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: AppColors.brand600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _expanded
                              ? (widget.showLessLabel ?? 'Afficher moins')
                              : (widget.showMoreLabel ?? 'Afficher plus'),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.brand600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Bottom sheet shown when the user taps the (i) button next to the
// "Assistant WhatsApp IA" line. Lists Zayna's main capabilities so the
// owner can decide whether the Business plan is worth it before continuing.
void _showZaynaFeaturesSheet(BuildContext context) {
  final l = AppLocalizations.of(context);
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (_, scrollController) {
          return Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.brand50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.smart_toy_outlined,
                          color: AppColors.brand700, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l?.tr('zayna_sheet.title') ?? 'Zayna — assistante IA',
                            style: GoogleFonts.dmSans(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.brand950,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l?.tr('zayna_sheet.subtitle') ??
                                'Incluse dans le plan Business · 1000 messages/mois',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.secondary500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 22),
                      color: AppColors.secondary500,
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                  children: [
                    _ZaynaSection(
                      l: l,
                      eyebrowKey: 'zayna_sheet.s1.eyebrow',
                      eyebrowFallback: 'POUR VOS CLIENTS',
                      titleKey: 'zayna_sheet.s1.title',
                      titleFallback: 'Une expérience de réservation premium',
                      features: [
                        _ZaynaFeat(
                          Icons.history_rounded,
                          l?.tr('zayna_sheet.f.memory') ?? 'Mémoire client',
                          l?.tr('zayna_sheet.f.memory.d') ??
                              'Se souvient des RDV passés et préférences.',
                        ),
                        _ZaynaFeat(
                          Icons.mic_outlined,
                          l?.tr('zayna_sheet.f.voice') ??
                              'Compréhension des vocaux',
                          l?.tr('zayna_sheet.f.voice.d') ??
                              'Transcrit les audios WhatsApp et y répond.',
                        ),
                        _ZaynaFeat(
                          Icons.tune_rounded,
                          l?.tr('zayna_sheet.f.upsell') ??
                              'Upsell intelligent',
                          l?.tr('zayna_sheet.f.upsell.d') ??
                              'Propose un service complémentaire au bon moment.',
                        ),
                        _ZaynaFeat(
                          Icons.event_available_outlined,
                          l?.tr('zayna_sheet.f.slots') ??
                              'Suggestion de créneaux smart',
                          l?.tr('zayna_sheet.f.slots.d') ??
                              "Propose 3 créneaux qui matchent l'habitude du client.",
                        ),
                        _ZaynaFeat(
                          Icons.group_outlined,
                          l?.tr('zayna_sheet.f.group') ??
                              'Réservation de groupe',
                          l?.tr('zayna_sheet.f.group.d') ??
                              '"Je viens avec ma sœur" → 2 RDV chaînés.',
                        ),
                      ],
                    ),
                    _ZaynaSection(
                      l: l,
                      eyebrowKey: 'zayna_sheet.s2.eyebrow',
                      eyebrowFallback: 'POUR VOUS ET VOTRE ÉQUIPE',
                      titleKey: 'zayna_sheet.s2.title',
                      titleFallback: 'Demandez tout en langage naturel',
                      features: [
                        _ZaynaFeat(
                          Icons.wb_sunny_outlined,
                          l?.tr('zayna_sheet.f.morning') ??
                              'Résumé du matin',
                          l?.tr('zayna_sheet.f.morning.d') ??
                              '"5 RDV, 400 DH potentiel, 1 RDV à risque no-show."',
                        ),
                        _ZaynaFeat(
                          Icons.bar_chart_rounded,
                          l?.tr('zayna_sheet.f.report') ??
                              'Rapport de fin de journée',
                          l?.tr('zayna_sheet.f.report.d') ??
                              '"4 honorés, 1 no-show, 250 DH encaissés."',
                        ),
                        _ZaynaFeat(
                          Icons.inventory_2_outlined,
                          l?.tr('zayna_sheet.f.stock') ??
                              'Stock instantané',
                          l?.tr('zayna_sheet.f.stock.d') ??
                              '"Il reste combien de coloration X ?" — réponse directe.',
                        ),
                        _ZaynaFeat(
                          Icons.calendar_today_outlined,
                          l?.tr('zayna_sheet.f.team') ??
                              'Plannings équipe',
                          l?.tr('zayna_sheet.f.team.d') ??
                              '"Sarah travaille demain ?" / "Qui est dispo jeudi ?"',
                        ),
                        _ZaynaFeat(
                          Icons.handshake_outlined,
                          l?.tr('zayna_sheet.f.teammode') ??
                              'Mode équipe',
                          l?.tr('zayna_sheet.f.teammode.d') ??
                              'Vos employés consultent leur planning via Zayna.',
                        ),
                      ],
                    ),
                    _ZaynaSection(
                      l: l,
                      eyebrowKey: 'zayna_sheet.s3.eyebrow',
                      eyebrowFallback: 'INTELLIGENCE & SÉCURITÉ',
                      titleKey: 'zayna_sheet.s3.title',
                      titleFallback: 'Sait quand passer la main',
                      features: [
                        _ZaynaFeat(
                          Icons.sentiment_dissatisfied_outlined,
                          l?.tr('zayna_sheet.f.sentiment') ??
                              'Détection sentiment',
                          l?.tr('zayna_sheet.f.sentiment.d') ??
                              "Client énervé/triste → escalade vers vous.",
                        ),
                        _ZaynaFeat(
                          Icons.star_outline,
                          l?.tr('zayna_sheet.f.vip') ?? 'Reconnaissance VIP',
                          l?.tr('zayna_sheet.f.vip.d') ??
                              'Vos clients VIP escaladent directement.',
                        ),
                        _ZaynaFeat(
                          Icons.shield_outlined,
                          l?.tr('zayna_sheet.f.confidence') ??
                              'Seuil de confiance',
                          l?.tr('zayna_sheet.f.confidence.d') ??
                              "Pas sûre → escalade plutôt qu'halluciner.",
                        ),
                        _ZaynaFeat(
                          Icons.warning_amber_outlined,
                          l?.tr('zayna_sheet.f.allergens') ??
                              'Alerte allergènes',
                          l?.tr('zayna_sheet.f.allergens.d') ??
                              'Refuse les services contenant des allergènes déclarés.',
                        ),
                      ],
                    ),
                    _ZaynaSection(
                      l: l,
                      eyebrowKey: 'zayna_sheet.s4.eyebrow',
                      eyebrowFallback: 'FAQ APPRENANTE',
                      titleKey: 'zayna_sheet.s4.title',
                      titleFallback: 'Plus elle travaille, plus elle apprend',
                      features: [
                        _ZaynaFeat(
                          Icons.menu_book_outlined,
                          l?.tr('zayna_sheet.f.kb_auto') ??
                              'Connaissance auto',
                          l?.tr('zayna_sheet.f.kb_auto.d') ??
                              'Accès direct à vos services + options dès l\'activation.',
                        ),
                        _ZaynaFeat(
                          Icons.bolt_outlined,
                          l?.tr('zayna_sheet.f.kb_learn') ??
                              'Apprentissage incrémental',
                          l?.tr('zayna_sheet.f.kb_learn.d') ??
                              'Vous répondez une fois → elle stocke pour toujours.',
                        ),
                      ],
                    ),
                    _ZaynaSection(
                      l: l,
                      eyebrowKey: 'zayna_sheet.s5.eyebrow',
                      eyebrowFallback: 'ENGAGEMENT PROACTIF',
                      titleKey: 'zayna_sheet.s5.title',
                      titleFallback: 'Garde le lien avec vos clients',
                      features: [
                        _ZaynaFeat(
                          Icons.refresh_rounded,
                          l?.tr('zayna_sheet.f.dormant') ??
                              'Réactivation clients dormants',
                          l?.tr('zayna_sheet.f.dormant.d') ??
                              '3 mois sans RDV → relance avec offre. Cap 1×/3 mois.',
                        ),
                        _ZaynaFeat(
                          Icons.cake_outlined,
                          l?.tr('zayna_sheet.f.birthday') ??
                              'Push anniversaire',
                          l?.tr('zayna_sheet.f.birthday.d') ??
                              'Le jour J, message + offre. Cap 1×/an.',
                        ),
                        _ZaynaFeat(
                          Icons.reviews_outlined,
                          l?.tr('zayna_sheet.f.review') ??
                              "Demande d'avis Google",
                          l?.tr('zayna_sheet.f.review.d') ??
                              'J+1 après un RDV honoré → boost SEO + réputation.',
                        ),
                        _ZaynaFeat(
                          Icons.queue_outlined,
                          l?.tr('zayna_sheet.f.waitlist') ??
                              "Liste d'attente intelligente",
                          l?.tr('zayna_sheet.f.waitlist.d') ??
                              'Slot plein → mise en liste → ping si annulation.',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _ZaynaFeat {
  final IconData icon;
  final String title;
  final String description;
  const _ZaynaFeat(this.icon, this.title, this.description);
}

class _ZaynaSection extends StatelessWidget {
  final AppLocalizations? l;
  final String eyebrowKey;
  final String eyebrowFallback;
  final String titleKey;
  final String titleFallback;
  final List<_ZaynaFeat> features;
  const _ZaynaSection({
    required this.l,
    required this.eyebrowKey,
    required this.eyebrowFallback,
    required this.titleKey,
    required this.titleFallback,
    required this.features,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            l?.tr(eyebrowKey) ?? eyebrowFallback,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: AppColors.brand700,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l?.tr(titleKey) ?? titleFallback,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: AppColors.brand950,
            height: 1.25,
          ),
        ),
        const SizedBox(height: 12),
        ...features.map((f) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.brand50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(f.icon, size: 18, color: AppColors.brand700),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          f.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.brand950,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          f.description,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.secondary500,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )),
        const SizedBox(height: 16),
      ],
    );
  }
}
