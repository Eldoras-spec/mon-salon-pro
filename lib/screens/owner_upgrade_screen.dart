import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../services/plan_config.dart';
import '../services/revenue_cat_service.dart';
import '../theme/app_colors.dart';

/// TEMPORARY dev bypass — set to false ONCE RevenueCat is live in App
/// Store + Google Play and we don't want to allow Firestore-only plan
/// flips anymore. Tracked in
/// `project_revenuecat_integration.md` (memory).
const bool _kAllowDevBypass = false;

/// Upgrade flow screen — launched from OwnerSubscriptionScreen when the
/// owner picks Essentiel or Business. Fetches the matching RevenueCat
/// package, shows Apple-localized pricing, and triggers the native App
/// Store purchase sheet. The server-side webhook (`onRevenueCatEvent`)
/// updates `salons/{uid}.plan` after Apple confirms the transaction —
/// the client only needs to react to `CustomerInfo` changes for UX.
class OwnerUpgradeScreen extends ConsumerStatefulWidget {
  final String targetPlan;
  const OwnerUpgradeScreen({super.key, required this.targetPlan});

  @override
  ConsumerState<OwnerUpgradeScreen> createState() =>
      _OwnerUpgradeScreenState();
}

class _OwnerUpgradeScreenState extends ConsumerState<OwnerUpgradeScreen> {
  bool _loadingOffering = true;
  bool _purchasing = false;
  bool _restoring = false;
  Package? _package;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _loadPackage();
  }

  Future<void> _loadPackage() async {
    try {
      final offerings = await Purchases.getOfferings();
      if (!mounted) return;
      final current = offerings.current ??
          offerings.all[RevenueCatService.defaultOfferingId];
      if (current == null) {
        setState(() {
          _loadingOffering = false;
          _loadError = 'offerings_empty';
        });
        return;
      }
      final targetPackageId =
          widget.targetPlan == PlanConfig.planBusiness
              ? RevenueCatService.packageBusinessMonthly
              : RevenueCatService.packageEssentielMonthly;
      final pkg = current.availablePackages.firstWhere(
        (p) => p.identifier == targetPackageId,
        orElse: () => current.availablePackages.first,
      );
      setState(() {
        _package = pkg;
        _loadingOffering = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOffering = false;
        _loadError = e.toString();
      });
    }
  }

  Future<void> _purchase() async {
    final pkg = _package;
    if (pkg == null) return;
    final l = AppLocalizations.of(context);
    setState(() => _purchasing = true);
    try {
      final customerInfo = await Purchases.purchasePackage(pkg);
      final entitlementKey =
          widget.targetPlan == PlanConfig.planBusiness
              ? RevenueCatService.entitlementBusiness
              : RevenueCatService.entitlementEssentiel;
      final active =
          customerInfo.entitlements.active.containsKey(entitlementKey);
      if (!mounted) return;
      if (active) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l?.tr('upgrade.success') ?? 'Plan activé 🎉'),
          backgroundColor: Colors.green.shade600,
        ));
        Navigator.pop(context);
      } else {
        // Purchase accepted by Apple but entitlement not yet present in
        // CustomerInfo (rare — webhook race). Tell the owner the plan
        // will activate shortly.
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l?.tr('upgrade.pending') ??
              'Achat en cours de validation — votre plan sera actif dans quelques instants.'),
        ));
        Navigator.pop(context);
      }
    } on PlatformException catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) {
        return; // user tapped Cancel on the Apple sheet — silent
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : ${e.message ?? errorCode.name}'),
        backgroundColor: Colors.red.shade600,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e'),
        backgroundColor: Colors.red.shade600,
      ));
    }
  }

  /// TEMPORARY — flips `salons/{uid}.plan` directly via Firestore so
  /// internal testers can exercise Business / Essentiel features without
  /// triggering an actual Apple / Google purchase. Server-side
  /// `onSalonPlanChange` then propagates the plan to derived flags
  /// (`isPremium`, grace period, etc.). To be removed when RevenueCat is
  /// live in prod (toggle `_kAllowDevBypass` to false).
  Future<void> _devBypassSubmit() async {
    final l = AppLocalizations.of(context);
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _purchasing = true);
    try {
      await FirebaseFirestore.instance.collection('salons').doc(uid).set({
        'plan': widget.targetPlan,
        'planUpdatedAt': FieldValue.serverTimestamp(),
        'planSource': 'dev_bypass',
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('upgrade.success') ?? 'Plan activé 🎉'),
        backgroundColor: Colors.green.shade600,
      ));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _purchasing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e'),
        backgroundColor: Colors.red.shade600,
      ));
    }
  }

  Future<void> _restorePurchases() async {
    final l = AppLocalizations.of(context);
    setState(() => _restoring = true);
    try {
      final info = await Purchases.restorePurchases();
      if (!mounted) return;
      final hasActive = info.entitlements.active.isNotEmpty;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(hasActive
            ? (l?.tr('upgrade.restore_success') ??
                'Achats restaurés avec succès')
            : (l?.tr('upgrade.restore_empty') ??
                'Aucun achat à restaurer sur ce compte')),
      ));
      if (hasActive) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'} : $e'),
        backgroundColor: Colors.red.shade600,
      ));
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final salon = ref.watch(ownerSalonProvider).value;
    final planLabel = widget.targetPlan == PlanConfig.planBusiness
        ? (l?.tr('plan.business') ?? 'Business')
        : (l?.tr('plan.essential') ?? 'Essentiel');
    final accentColor = widget.targetPlan == PlanConfig.planBusiness
        ? Colors.purple
        : AppColors.brand600;
    // Trial banner shows only when the salon would actually get a trial
    // on this upgrade — mirrors the server-side guard in onSalonPlanChange.
    final isEssentielWithTrial =
        widget.targetPlan == PlanConfig.planEssentiel &&
            salon != null &&
            salon.isTrialEligible;

    // Apple-localized price (e.g. "22,99 €" in FR, "$19.99" in US).
    final localizedPrice =
        _package?.storeProduct.priceString ?? '—';

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
          l?.tr('upgrade.title') ?? 'Finaliser l\'upgrade',
          style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              fontSize: 18),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Plan summary ────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [accentColor, accentColor.withValues(alpha: 0.8)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l?.tr('upgrade.plan_summary_label') ?? 'Plan choisi',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    planLabel,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        localizedPrice,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          l?.tr('plan.perMonth') ?? '/mois',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (isEssentielWithTrial) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        (l?.tr('upgrade.trial_banner') ??
                                '3 mois offerts — aucun prélèvement avant {date}')
                            .replaceAll(
                          '{date}',
                          _formatDate(DateTime.now().add(
                              Duration(days: PlanConfig.essentielTrialDays))),
                        ),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Secure-checkout note ────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_rounded,
                      size: 16, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l?.tr('upgrade.secure_note') ??
                          'Paiement sécurisé géré par Apple. Vous confirmerez avec Face ID / Touch ID.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.blue.shade900,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Primary action ──────────────────────────────────
            if (_loadingOffering)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (_loadError != null || _package == null)
              _ErrorState(
                message: l?.tr('upgrade.offering_load_failed') ??
                    'Impossible de charger l\'offre. Vérifiez votre connexion.',
                onRetry: () {
                  setState(() {
                    _loadingOffering = true;
                    _loadError = null;
                  });
                  _loadPackage();
                },
              )
            else
              ElevatedButton(
                onPressed: _purchasing ? null : _purchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.secondary200,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: _purchasing
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        isEssentielWithTrial
                            ? (l?.tr('upgrade.start_trial') ??
                                'Démarrer le trial gratuit')
                            : (l?.tr('upgrade.confirm') ??
                                'Confirmer l\'upgrade'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                l?.tr('upgrade.cancel_anytime') ??
                    'Résiliable à tout moment depuis Mon abonnement.',
                style: const TextStyle(
                    fontSize: 11, color: AppColors.secondary400),
              ),
            ),
            const SizedBox(height: 24),

            // ── DEV BYPASS — flips `salons/{uid}.plan` directly via Firestore.
            //   Removed automatically when `_kAllowDevBypass = false` (set to
            //   false once RevenueCat is live so this can NEVER ship to prod).
            //   See memory `project_revenuecat_integration.md`.
            if (_kAllowDevBypass) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.science_rounded,
                            size: 16, color: Color(0xFFB45309)),
                        const SizedBox(width: 6),
                        Text(
                          'DEV — Test bypass',
                          style: GoogleFonts.dmSans(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Active le plan instantanément via Firestore (sans paiement). À supprimer dès que RevenueCat est en prod.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF78350F), height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _purchasing ? null : _devBypassSubmit,
                        icon: const Icon(Icons.bolt_rounded, size: 16),
                        label: Text('Activer ${widget.targetPlan} sans payer'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFB45309),
                          side: const BorderSide(color: Color(0xFFB45309)),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

            // ── Restore purchases (Apple requirement) ───────────
            Center(
              child: TextButton.icon(
                onPressed: _restoring ? null : _restorePurchases,
                icon: _restoring
                    ? const SizedBox(
                        width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.restore_rounded,
                        size: 16, color: AppColors.secondary500),
                label: Text(
                  l?.tr('upgrade.restore') ?? 'Restaurer mes achats',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade100),
      ),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.red.shade900,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: onRetry,
            child: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }
}
