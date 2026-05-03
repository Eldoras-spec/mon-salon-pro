import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

const String _kSupportWhatsapp = '212663322420';
const String _kSupportLlcMessage =
    'Bonjour, je souhaite recevoir de l\'aide pour la création d\'une LLC US '
    'afin d\'activer les paiements par carte sur Mon Salon.';

/// Pays acceptés par Stripe Connect Express où l'onboarding peut aboutir
/// directement avec le pays renseigné par l'owner. Pour les autres
/// (notamment Maroc), on affiche le CTA aide LLC.
const Set<String> _kStripeSupportedCountriesLower = {
  'france',
  'spain',
  'espagne',
  'germany',
  'allemagne',
  'united kingdom',
  'royaume-uni',
  'england',
  'united states',
  'etats-unis',
  'italy',
  'italie',
  'portugal',
  'netherlands',
  'pays-bas',
  'belgium',
  'belgique',
  'canada',
  'australia',
  'australie',
  'japan',
  'japon',
  'singapore',
  'uae',
  'emirats arabes unis',
};

bool _isCountrySupported(String? raw) {
  final s = (raw ?? '').trim().toLowerCase();
  if (s.isEmpty) return false;
  if (s.length == 2) return true; // Already an ISO code — let Stripe decide
  return _kStripeSupportedCountriesLower.contains(s);
}

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
            country: salon.country,
            plan: salon.plan,
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
  final String country;
  final String plan;
  const _Body({
    required this.salonId,
    required this.country,
    required this.plan,
  });

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  bool _busy = false;

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

  Future<void> _contactSupportLlc() async {
    final url = Uri.parse(
        'https://wa.me/$_kSupportWhatsapp?text=${Uri.encodeComponent(_kSupportLlcMessage)}');
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
    final supported = _isCountrySupported(widget.country);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Intro(l: l),
          const SizedBox(height: 14),
          if (!supported)
            _LlcHelpCard(
              l: l,
              country: widget.country,
              onContact: _contactSupportLlc,
            ),
          if (!supported) const SizedBox(height: 14),
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
              return _StatusCard(
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

class _LlcHelpCard extends StatelessWidget {
  final AppLocalizations? l;
  final String country;
  final VoidCallback onContact;
  const _LlcHelpCard(
      {required this.l, required this.country, required this.onContact});

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
              Icon(Icons.info_outline,
                  color: Colors.amber.shade800, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l?.tr('stripe_connect.llc_title') ??
                      'Stripe non disponible dans votre pays',
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
            (l?.tr('stripe_connect.llc_body') ??
                    'Stripe ne supporte pas encore "{country}". Nous pouvons vous '
                        'aider à créer une LLC américaine en quelques jours pour '
                        'activer les paiements par carte. Contactez-nous sur WhatsApp.')
                .replaceAll('{country}', country),
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
                l?.tr('stripe_connect.llc_cta') ??
                    'Demander de l\'aide LLC',
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
          ? 'Stripe : $disabledReason'
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
                          '• $r',
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
              if (!notConnected) const SizedBox(width: 8),
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

