import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';
import '../utils/currency_helper.dart';

// Stripe Connect API codes (snake.dot.case) → human-readable i18n keys.
// Falls back to the raw code if no translation exists, so unknown new
// Stripe codes surface as the raw string instead of being silently dropped.
String _translateDisabledReason(String code, AppLocalizations? l) {
  final key = 'stripe_connect.disabled_reason.${code.replaceAll('.', '_')}';
  final tr = l?.tr(key);
  return (tr == null || tr == key)
      ? 'Stripe : $code'
      : tr;
}

String _translateRequirement(String code, AppLocalizations? l) {
  final key = 'stripe_connect.requirement.${code.replaceAll('.', '_')}';
  final tr = l?.tr(key);
  return (tr == null || tr == key) ? code : tr;
}

const String _kSupportWhatsapp = '212663322420';
const String _kSupportMessage =
    'Bonjour, je souhaite recevoir de l\'aide pour configurer les paiements '
    'par carte sur mon salon.';

/// Stripe Connect Express management screen for owners.
///
/// Streams `salons/{uid}.stripeConnect.*` from Firestore (no model coupling
/// — Connect data is billing-only and stays local to this screen). Calls
/// callable CFs `createConnectOnboardingLink` / `getConnectAccountStatus`.
class OwnerStripeConnectScreen extends ConsumerWidget {
  const OwnerStripeConnectScreen({super.key});

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
          l?.tr('stripe_connect.title') ?? 'Paiements par carte',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 18,
          ),
        ),
      ),
      body: salonAsync.when(
        data: (salon) {
          if (salon == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _Body(
            salonId: salon.id,
            plan: salon.plan,
            currency: salon.currency,
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _Body extends StatefulWidget {
  final String salonId;
  final String plan;
  final String currency;
  const _Body({
    required this.salonId,
    required this.plan,
    required this.currency,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // Verify the Connect status against Stripe on open so a cached "Active"
    // flag that is stale (e.g. a test account after the live switch) is
    // self-corrected: getConnectAccountStatus clears the flags server-side on
    // resource_missing, and the Firestore stream then flips the UI to
    // "not connected". Silent + best-effort — the cached flags stay if it fails.
    _syncStatusSilently();
  }

  Future<void> _syncStatusSilently() async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('getConnectAccountStatus')
          .call();
    } catch (_) {
      // Non-fatal: the streamed cached flags remain on transient errors.
    }
  }

  Future<void> _onboard() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('createConnectOnboardingLink')
          .call();
      final url = (res.data as Map?)?['url'] as String?;
      if (url == null || url.isEmpty) throw Exception('No URL returned');
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(
            l?.tr('stripe_connect.launch_failed') ??
                'Impossible d\'ouvrir Stripe.',
          )),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.message ?? 'Erreur Stripe.'),
        backgroundColor: Colors.redAccent,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final l = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('getConnectAccountStatus')
          .call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l?.tr('stripe_connect.refreshed') ?? 'Statut actualisé.'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _contactSupport() async {
    final url = Uri.parse(
        'https://wa.me/$_kSupportWhatsapp?text=${Uri.encodeComponent(_kSupportMessage)}');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Intro(l: l),
          const SizedBox(height: 14),
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('salons')
                .doc(widget.salonId)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snap.data?.data() ?? {};
              final raw = data['stripeConnect'];
              final connect = raw is Map
                  ? Map<String, dynamic>.from(raw)
                  : <String, dynamic>{};
              final accountId = connect['accountId'] as String?;
              final detailsSubmitted =
                  connect['detailsSubmitted'] == true;
              final chargesEnabled = connect['chargesEnabled'] == true;
              final payoutsEnabled = connect['payoutsEnabled'] == true;
              final disabledReason =
                  connect['disabledReason'] as String?;
              final dueRaw = connect['requirementsCurrentlyDue'];
              final due = dueRaw is List
                  ? dueRaw.map((e) => e.toString()).toList()
                  : <String>[];
              final cartThreshold =
                  (data['cartDepositThreshold'] as num?)?.toDouble() ?? 0;
              final cartAmount =
                  (data['cartDepositAmount'] as num?)?.toDouble() ?? 0;
              final noShowRate =
                  (data['noShowDepositRate'] as num?)?.toDouble() ?? 0;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _StatusCard(
                    l: l,
                    accountId: accountId,
                    detailsSubmitted: detailsSubmitted,
                    chargesEnabled: chargesEnabled,
                    payoutsEnabled: payoutsEnabled,
                    disabledReason: disabledReason,
                    requirementsDue: due,
                    busy: _busy,
                    onOnboard: _onboard,
                    onRefresh: _refresh,
                  ),
                  if (!chargesEnabled) ...[
                    const SizedBox(height: 14),
                    _SupportHelpCard(l: l, onContact: _contactSupport),
                  ],
                  if (chargesEnabled) ...[
                    const SizedBox(height: 14),
                    _CartDepositCard(
                      l: l,
                      salonId: widget.salonId,
                      currency: widget.currency,
                      initialThreshold: cartThreshold,
                      initialAmount: cartAmount,
                    ),
                    const SizedBox(height: 14),
                    _NoShowDepositCard(
                      l: l,
                      salonId: widget.salonId,
                      initialRate: noShowRate,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 14),
          _FeesNote(l: l, plan: widget.plan),
        ],
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  final AppLocalizations? l;
  const _Intro({required this.l});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brand600, AppColors.brand500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.credit_card_rounded,
                  color: Colors.white, size: 22),
              const SizedBox(width: 8),
              Text(
                l?.tr('stripe_connect.intro_title') ??
                    'Paiements par carte (Stripe)',
                style: GoogleFonts.dmSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l?.tr('stripe_connect.intro_body') ??
                'Connectez Stripe Express pour accepter les paiements par carte '
                    '(acomptes ou paiement total) lors des réservations et sur '
                    'la boutique. Les fonds sont versés directement sur votre '
                    'compte bancaire.',
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportHelpCard extends StatelessWidget {
  final AppLocalizations? l;
  final VoidCallback onContact;
  const _SupportHelpCard({required this.l, required this.onContact});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.support_agent_rounded,
                  color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l?.tr('stripe_connect.support_title') ??
                      'Besoin d\'aide pour la configuration ?',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand950,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            l?.tr('stripe_connect.support_body') ??
                'Si vous souhaitez de l\'aide pour configurer les paiements '
                    'par carte sur votre salon, notre équipe vous accompagne sur '
                    'WhatsApp.',
            style: const TextStyle(
                fontSize: 12,
                color: AppColors.secondary600,
                height: 1.45),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onContact,
              icon: const Icon(Icons.chat_bubble_outline, size: 18),
              label: Text(
                l?.tr('stripe_connect.support_cta') ??
                    'Contacter le support',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF25D366),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final AppLocalizations? l;
  final String? accountId;
  final bool detailsSubmitted;
  final bool chargesEnabled;
  final bool payoutsEnabled;
  final String? disabledReason;
  final List<String> requirementsDue;
  final bool busy;
  final VoidCallback onOnboard;
  final VoidCallback onRefresh;

  const _StatusCard({
    required this.l,
    required this.accountId,
    required this.detailsSubmitted,
    required this.chargesEnabled,
    required this.payoutsEnabled,
    required this.disabledReason,
    required this.requirementsDue,
    required this.busy,
    required this.onOnboard,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final notConnected = accountId == null;
    final fullyOk = chargesEnabled && payoutsEnabled;
    final inProgress =
        accountId != null && (!chargesEnabled || !payoutsEnabled);

    Color color;
    IconData icon;
    String statusTitle;
    String statusSubtitle;
    if (notConnected) {
      color = AppColors.secondary500;
      icon = Icons.link_off_rounded;
      statusTitle = l?.tr('stripe_connect.status_not_connected') ??
          'Non connecté';
      statusSubtitle = l?.tr('stripe_connect.status_not_connected_sub') ??
          'Connectez Stripe Express pour activer les paiements.';
    } else if (fullyOk) {
      color = Colors.green.shade700;
      icon = Icons.check_circle_rounded;
      statusTitle = l?.tr('stripe_connect.status_active') ?? 'Actif';
      statusSubtitle = l?.tr('stripe_connect.status_active_sub') ??
          'Vous pouvez accepter les paiements par carte.';
    } else {
      color = Colors.orange.shade700;
      icon = Icons.hourglass_top_rounded;
      statusTitle = l?.tr('stripe_connect.status_pending') ??
          'Configuration en cours';
      statusSubtitle = disabledReason != null
          ? _translateDisabledReason(disabledReason!, l)
          : (l?.tr('stripe_connect.status_pending_sub') ??
              'Complétez les informations demandées par Stripe.');
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusTitle,
                      style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand950,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      statusSubtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary600,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (inProgress && requirementsDue.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l?.tr('stripe_connect.requirements_label') ??
                        'À fournir :',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.orange.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  ...requirementsDue.take(6).map((r) => Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• ${_translateRequirement(r, l)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.orange.shade900,
                          ),
                        ),
                      )),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (!notConnected)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: busy ? null : onRefresh,
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      l?.tr('stripe_connect.refresh') ?? 'Actualiser',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: AppColors.secondary200),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
              if (!notConnected && !fullyOk) const SizedBox(width: 8),
              if (notConnected || !fullyOk)
                Expanded(
                  child: FilledButton.icon(
                    onPressed: busy ? null : onOnboard,
                    icon: busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.open_in_new_rounded, size: 16),
                    label: Text(
                      notConnected
                          ? (l?.tr('stripe_connect.connect') ??
                              'Connecter Stripe')
                          : (l?.tr('stripe_connect.continue_onboarding') ??
                              'Continuer la configuration'),
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
}

class _FeesNote extends StatelessWidget {
  final AppLocalizations? l;
  final String plan;
  const _FeesNote({required this.l, required this.plan});

  @override
  Widget build(BuildContext context) {
    final ratePct = plan == 'business'
        ? '1'
        : plan == 'essentiel'
            ? '3'
            : '5';
    final tplFr = 'Frais Mon Salon : {rate} % par paiement sur votre plan '
        'actuel. Les frais Stripe restent séparés et déduits par Stripe.';
    final raw = l?.tr('stripe_connect.fees_note') ?? tplFr;
    final text = raw == 'stripe_connect.fees_note' ? tplFr : raw;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.payments_outlined,
              color: AppColors.brand700, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text.replaceAll('{rate}', ratePct),
              style: const TextStyle(
                  fontSize: 11.5,
                  color: AppColors.brand700,
                  height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartDepositCard extends StatefulWidget {
  final AppLocalizations? l;
  final String salonId;
  final String currency;
  final double initialThreshold;
  final double initialAmount;
  const _CartDepositCard({
    required this.l,
    required this.salonId,
    required this.currency,
    required this.initialThreshold,
    required this.initialAmount,
  });

  @override
  State<_CartDepositCard> createState() => _CartDepositCardState();
}

class _CartDepositCardState extends State<_CartDepositCard> {
  late final TextEditingController _thresholdCtrl;
  late final TextEditingController _amountCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _thresholdCtrl = TextEditingController(
      text: widget.initialThreshold > 0
          ? widget.initialThreshold.toStringAsFixed(0)
          : '',
    );
    _amountCtrl = TextEditingController(
      text: widget.initialAmount > 0
          ? widget.initialAmount.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = widget.l;
    final threshold = double.tryParse(_thresholdCtrl.text.trim()) ?? 0;
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    // Either both set (enable policy) or both empty/0 (disable). Reject the
    // half-configured case so the cart-deposit fallback can't fire by accident.
    final bothSet = threshold > 0 && amount > 0;
    final bothCleared = threshold == 0 && amount == 0;
    if (!bothSet && !bothCleared) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('stripe_connect.cart_deposit.invalid') ??
            'Renseigne le seuil ET l\'acompte, ou laisse les deux vides pour désactiver.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    if (bothSet && amount > threshold) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('stripe_connect.cart_deposit.amount_over_threshold') ??
            'L\'acompte ne peut pas dépasser le seuil.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .update({
        'cartDepositThreshold': threshold,
        'cartDepositAmount': amount,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l?.tr('stripe_connect.cart_deposit.saved') ??
              'Politique d\'acompte enregistrée.'),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.redAccent),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final symbol = CurrencyHelper.symbol(widget.currency);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l?.tr('stripe_connect.cart_deposit.title') ??
                'Politique d\'acompte panier',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l?.tr('stripe_connect.cart_deposit.subtitle') ??
                'Acompte fixe demandé si le total de la réservation atteint le seuil. Laisse vide pour désactiver.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.secondary600, height: 1.35),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (l?.tr('stripe_connect.cart_deposit.threshold_label') ??
                              'Seuil ({symbol})')
                          .replaceAll('{symbol}', symbol),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.secondary600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _thresholdCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '500',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (l?.tr('stripe_connect.cart_deposit.amount_label') ??
                              'Acompte ({symbol})')
                          .replaceAll('{symbol}', symbol),
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.secondary600),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _amountCtrl,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        hintText: '100',
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.brand600,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      l?.tr('stripe_connect.cart_deposit.save') ??
                          'Enregistrer',
                      style: const TextStyle(fontSize: 12),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}


class _NoShowDepositCard extends StatefulWidget {
  final AppLocalizations? l;
  final String salonId;
  final double initialRate;
  const _NoShowDepositCard({
    required this.l,
    required this.salonId,
    required this.initialRate,
  });

  @override
  State<_NoShowDepositCard> createState() => _NoShowDepositCardState();
}

class _NoShowDepositCardState extends State<_NoShowDepositCard> {
  late bool _enabled = widget.initialRate > 0;
  late final TextEditingController _rateCtrl = TextEditingController(
      text: widget.initialRate > 0
          ? widget.initialRate.toStringAsFixed(0)
          : '10');
  bool _saving = false;

  @override
  void dispose() {
    _rateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final l = widget.l;
    final raw = _rateCtrl.text.trim();
    final rate = double.tryParse(raw.replaceAll(',', '.')) ?? 0;
    if (_enabled && (rate <= 0 || rate > 100)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('no_show_deposit.invalid_rate') ??
            'Le pourcentage doit être entre 1 et 100.'),
      ));
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .update({'noShowDepositRate': _enabled ? rate : 0});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: const Color(0xFF16A34A),
        content: Text(l?.tr('common_saved') ?? 'Enregistré ✅'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e'),
      ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.warning_amber_rounded,
                    size: 16, color: Color(0xFFB45309)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l?.tr('no_show_deposit.title') ??
                      'Acompte clients à risque',
                  style: GoogleFonts.dmSans(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppColors.brand950),
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: (v) => setState(() => _enabled = v),
                activeColor: AppColors.brand600,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('no_show_deposit.body') ??
                'Un acompte est demandé aux clients identifiés comme risqués (taux d\'annulation élevé), même sur des prestations sans acompte. Si la prestation a déjà un %, on garde le plus grand.',
            style: const TextStyle(
                fontSize: 12, color: AppColors.secondary500, height: 1.45),
          ),
          if (_enabled) ...[
            const SizedBox(height: 14),
            Text(
              l?.tr('no_show_deposit.rate_label') ?? 'Pourcentage (%)',
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _rateCtrl,
              keyboardType: TextInputType.number,
              // Digits 0-9 only, then a custom formatter clamps to [0, 100].
              // Pasting "150" or typing "999" is auto-truncated to 100.
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(3),
                TextInputFormatter.withFunction((old, fresh) {
                  if (fresh.text.isEmpty) return fresh;
                  final n = int.tryParse(fresh.text);
                  if (n == null) return old;
                  if (n > 100) {
                    return const TextEditingValue(
                      text: '100',
                      selection: TextSelection.collapsed(offset: 3),
                    );
                  }
                  return fresh;
                }),
              ],
              decoration: InputDecoration(
                hintText: '10',
                suffixText: '%',
                filled: true,
                fillColor: AppColors.brand50,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(l?.tr('common_save') ?? 'Enregistrer'),
            ),
          ),
        ],
      ),
    );
  }
}
