import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/owner_providers.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';
import '../widgets/bot_quota_card.dart';
import 'owner_promotions_screen.dart';
import 'owner_subscription_screen.dart';

/// Owner-facing config screen for the WhatsApp Zayna bot. Available
/// from `Profil → Assistant BOT` for Business-plan owners.
///
/// Streams `salons/{id}` for status + botConfig, and the
/// `salons/{id}/botKnowledge` subcollection for the learned FAQ.
///
/// Mutations write back to `salons/{id}.botConfig.*` directly (rules
/// allow owner-only updates on their own salon doc).
/// Exposed at top level so the `_BusinessGate` upsell + the header
/// help-icon both open the same sheet without duplicating the
/// ~180-line capability content.
void showZaynaCapabilitiesSheet(BuildContext context) {
    final l = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          expand: false,
          builder: (_, scroll) => ListView(
            controller: scroll,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.secondary200,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(
                l?.tr('bot_settings.help_title') ??
                    'Comment fonctionne Zayna ?',
                style: GoogleFonts.dmSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                l?.tr('bot_settings.help_subtitle') ??
                    'Vue d\'ensemble des capacités de votre assistante WhatsApp.',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary500,
                    height: 1.4),
              ),
              const SizedBox(height: 18),
              _helpSection(
                Icons.event_available_rounded,
                Colors.green.shade700,
                l?.tr('bot_settings.help_book_title') ??
                    'Réservation automatique',
                l?.tr('bot_settings.help_book_body') ??
                    'Quand un client écrit "je veux un balayage demain", Zayna lit la disponibilité de l\'équipe en temps réel (en croisant les RDV existants, les indisponibilités déclarées par chaque employé, et les services qu\'il pratique), propose les 3 meilleurs créneaux, gère les services complexes en plusieurs étapes (couleur + cut + brushing), confirme et crée le RDV dans l\'agenda. Pour modifier ou annuler, le client peut juste lui écrire — Zayna gère sans intervention de votre part.',
              ),
              _helpSection(
                Icons.psychology_rounded,
                Colors.purple.shade600,
                l?.tr('bot_settings.help_memory_title') ??
                    'Mémoire client (3 niveaux)',
                l?.tr('bot_settings.help_memory_body') ??
                    'Niveau 1 — Identité : nom, langue préférée, anniversaire (collectés au 1er contact). Niveau 2 — Sensibilité : type de cheveux/peau, allergies déclarées, préférences (sans coloration aux PPD, jamais d\'huile coco, etc.). Niveau 3 — Historique : 5 dernières visites avec dates, employés et services. À chaque message, Zayna recharge ces 3 couches pour personnaliser sa réponse — elle dit "Bonjour Sarah" et propose le mardi 14h si c\'est son créneau habituel.',
              ),
              _helpSection(
                Icons.warning_amber_rounded,
                Colors.red.shade600,
                l?.tr('bot_settings.help_allergens_title') ??
                    'Vigilance allergènes (2 niveaux)',
                l?.tr('bot_settings.help_allergens_body') ??
                    'Niveau 1 — Allergies du client : Zayna les demande au 1er contact ("avez-vous des allergies connues ?") et les mémorise. À chaque résa suivante, elle croise et bloque si match avec un service à risque. Niveau 2 — Liste owner (vous) : la liste d\'allergènes à surveiller systématiquement (PPD, formaldéhyde, ammoniaque, thiomersal, résorcinol…). Zayna pose la question pré-résa quand ces ingrédients sont concernés, même si le client ne les a pas mentionnés. En cas de match : refus du booking + alternative proposée + escalade vers vous.',
              ),
              _helpSection(
                Icons.lightbulb_outline_rounded,
                Colors.amber.shade700,
                l?.tr('bot_settings.help_smart_title') ??
                    'Suggestions intelligentes',
                l?.tr('bot_settings.help_smart_body') ??
                    'Smart slots : Zayna détecte si un client a un créneau récurrent (3 visites le samedi 11h) et le propose en priorité aux prochaines réservations. Upsell : selon le service principal, elle suggère le complémentaire le plus rentable du salon (ex: cut → propose un brushing à -20%). Continuité : elle garde le même employé que les visites précédentes si possible, sinon explique pourquoi le change.',
              ),
              _helpSection(
                Icons.escalator_warning_rounded,
                Colors.orange.shade700,
                l?.tr('bot_settings.help_escalate_title') ??
                    'Escalade intelligente',
                l?.tr('bot_settings.help_escalate_body') ??
                    'Quand Zayna détecte un cas sensible (réclamation, demande hors-catalogue, allergie inconnue, sentiment client négatif détecté en analyse), elle vous envoie sur WhatsApp un résumé compact + 2 boutons "Répondre via Zayna" (vous dictez, Zayna formate et envoie au client) ou "Contacter directement" (Zayna donne le numéro client + s\'efface). La conversation reste en mode handover tant que vous ne la fermez pas.',
              ),
              _helpSection(
                Icons.school_outlined,
                Colors.blue.shade600,
                l?.tr('bot_settings.help_learn_title') ??
                    'FAQ apprenante',
                l?.tr('bot_settings.help_learn_body') ??
                    'Quand vous répondez à un client via Zayna en mode handover (avec le bouton "Répondre via Zayna"), elle mémorise la question + votre réponse + la langue + transforme la question en vecteur sémantique. À chaque future question similaire (même formulée autrement), Zayna cherche dans sa base par cosine similarity ≥ 0.85 et répond directement sans vous solliciter. Vous pouvez voir la liste, la nettoyer et supprimer ce qui ne s\'applique plus depuis cette page.',
              ),
              _helpSection(
                Icons.send_rounded,
                Colors.teal.shade600,
                l?.tr('bot_settings.help_proactive_title') ??
                    'Messages proactifs (4 types)',
                l?.tr('bot_settings.help_proactive_body') ??
                    'Anniversaire (Marketing) : Zayna souhaite + offre cadeau aux clients qui ont opté-in pour le marketing, jour J. Réactivation 90j (Marketing) : relance 1× les clients silencieux depuis 3 mois. Avis Google (Utility) : J+1 après un RDV terminé, propose laisser un avis contre une remise sur la prochaine prestation. Place libérée (Utility) : quand un RDV est annulé et qu\'un client était sur liste d\'attente, alerte WhatsApp instantanée. Cap dur de 20 envois proactifs/jour pour éviter le spam.',
              ),
              _helpSection(
                Icons.bar_chart_rounded,
                Colors.indigo.shade600,
                l?.tr('bot_settings.help_owner_title') ??
                    'Zayna comme assistante owner',
                l?.tr('bot_settings.help_owner_body') ??
                    'Depuis votre propre WhatsApp, vous pouvez interroger Zayna : "CA d\'avril ?", "RDV de demain ?", "qui est libre vendredi 15h ?", "combien j\'ai dépensé en charges ce mois ?", "top 5 clients VIP ?". Elle répond instantanément sans que vous ayez à ouvrir l\'app.',
              ),
              _helpSection(
                Icons.shield_outlined,
                Colors.grey.shade700,
                l?.tr('bot_settings.help_safety_title') ??
                    'Pause d\'urgence',
                l?.tr('bot_settings.help_safety_body') ??
                    'Le toggle "Mettre Zayna en pause" stoppe immédiatement le traitement de TOUS les messages entrants : aucun nouveau message ne reçoit de réponse, aucun proactif n\'est envoyé. Les conversations en cours restent intactes mais figées. Réactivez en 1 clic quand vous êtes prêt. Utile en cas de bug détecté ou pour un événement exceptionnel (fermeture imprévue).',
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(sheetCtx),
                  child: Text(
                    l?.tr('common_close') ?? 'Fermer',
                    style: const TextStyle(
                      color: AppColors.brand600,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _helpSection(
      IconData icon, Color color, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.secondary600,
                      height: 1.45),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

class OwnerBotSettingsScreen extends ConsumerWidget {
  const OwnerBotSettingsScreen({super.key});

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
          l?.tr('bot_settings.title') ?? 'Assistant BOT',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 18,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline_rounded,
                color: AppColors.brand600, size: 22),
            tooltip: l?.tr('bot_settings.help_tooltip') ??
                'Comment ça marche ?',
            onPressed: () => showZaynaCapabilitiesSheet(context),
          ),
        ],
      ),
      body: salonAsync.when(
        data: (salon) {
          if (salon == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!salon.isBusiness) {
            return _BusinessGate(l: l);
          }
          return _Body(salonId: salon.id);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final String salonId;
  const _Body({required this.salonId});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('salons')
          .doc(salonId)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data?.data() ?? {};
        final botStatus = data['botStatus'] as String? ?? 'pending';
        final botWhatsapp = data['botWhatsapp'] as String?;
        final setupComplete = data['botSetupComplete'] == true;
        final aiPromosEnabled = data['aiPromosEnabled'] == true;
        final cfgRaw = data['botConfig'];
        final cfg = cfgRaw is Map
            ? Map<String, dynamic>.from(cfgRaw)
            : <String, dynamic>{};
        final proRaw = cfg['proactiveOptIn'];
        final pro = proRaw is Map
            ? Map<String, dynamic>.from(proRaw)
            : <String, dynamic>{};

        final paused = cfg['paused'] == true;
        final escalRaw = cfg['escalationCases'];
        final escal = escalRaw is Map
            ? Map<String, dynamic>.from(escalRaw)
            : <String, dynamic>{};
        final allergensRaw = cfg['allergens'];
        final allergens = allergensRaw is List
            ? allergensRaw.map((e) => e.toString()).toList()
            : <String>[];
        final faqRaw = cfg['faqBase'];
        final faqBase = faqRaw is List
            ? faqRaw
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList()
            : <Map<String, dynamic>>[];

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _StatusCard(
                botStatus: botStatus,
                botWhatsapp: botWhatsapp,
                setupComplete: setupComplete,
              ),
              if (botStatus == 'active' &&
                  setupComplete &&
                  botWhatsapp != null &&
                  botWhatsapp.isNotEmpty) ...[
                const SizedBox(height: 12),
                _WaMeShareCard(botWhatsapp: botWhatsapp),
              ],
              const SizedBox(height: 16),
              BotQuotaCard(salonId: salonId),
              const SizedBox(height: 16),
              _PauseCard(salonId: salonId, paused: paused),
              const SizedBox(height: 16),
              _ClientCapCard(salonId: salonId, cfg: cfg),
              const SizedBox(height: 16),
              _ProactivesCard(
                salonId: salonId,
                pro: pro,
                aiPromosEnabled: aiPromosEnabled,
              ),
              const SizedBox(height: 16),
              _BehaviourCard(
                salonId: salonId,
                cfg: cfg,
              ),
              const SizedBox(height: 16),
              _EscalationCard(salonId: salonId, escal: escal),
              const SizedBox(height: 16),
              _AllergensCard(salonId: salonId, allergens: allergens),
              const SizedBox(height: 16),
              _FaqBaseCard(salonId: salonId, faqBase: faqBase),
              const SizedBox(height: 16),
              _LearnedFaqCard(salonId: salonId),
              const SizedBox(height: 16),
              _SetupWizardCard(botWhatsapp: botWhatsapp),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }
}

// ── Status ────────────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final String botStatus;
  final String? botWhatsapp;
  final bool setupComplete;
  const _StatusCard({
    required this.botStatus,
    required this.botWhatsapp,
    required this.setupComplete,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    Color color;
    IconData icon;
    String title;
    String subtitle;
    if (botWhatsapp == null || botWhatsapp!.isEmpty) {
      color = AppColors.secondary500;
      icon = Icons.link_off_rounded;
      title = l?.tr('bot_settings.status_not_provisioned') ??
          'Sender WhatsApp non provisionné';
      subtitle = l?.tr('bot_settings.status_not_provisioned_sub') ??
          'Contactez le support pour activer un numéro WhatsApp dédié à votre salon.';
    } else if (botStatus == 'active' && setupComplete) {
      color = Colors.green.shade700;
      icon = Icons.check_circle_rounded;
      title = l?.tr('bot_settings.status_active') ?? 'Zayna est active';
      subtitle = (l?.tr('bot_settings.status_active_sub') ??
              'Numéro : {number}')
          .replaceAll('{number}', botWhatsapp!);
    } else {
      color = Colors.orange.shade700;
      icon = Icons.hourglass_top_rounded;
      title = l?.tr('bot_settings.status_pending') ?? 'Configuration à finaliser';
      subtitle = l?.tr('bot_settings.status_pending_sub') ??
          'Ouvrez WhatsApp et écrivez à votre numéro Zayna pour terminer la configuration.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Row(
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
                  title,
                  style: GoogleFonts.dmSans(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary600,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── wa.me share link (active bots only) ──────────────────────────
//
// Compact action card so the owner can grab the public wa.me link of
// their Zayna sender and paste it on their Instagram bio, Google Business
// Profile, etc. Single tap = copy to clipboard + snackbar feedback.
class _WaMeShareCard extends StatelessWidget {
  final String botWhatsapp;
  const _WaMeShareCard({required this.botWhatsapp});

  String get _digits => botWhatsapp.replaceAll(RegExp(r'[^0-9]'), '');
  String get _link => 'https://wa.me/$_digits';

  Future<void> _copy(BuildContext context) async {
    final l = AppLocalizations.of(context);
    await Clipboard.setData(ClipboardData(text: _link));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l?.tr('bot_settings.wame_copied') ?? 'Lien copié'),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand200),
      ),
      child: Row(
        children: [
          const Icon(Icons.link_rounded, size: 20, color: AppColors.brand700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l?.tr('bot_settings.wame_title') ??
                      'Lien WhatsApp à partager',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _link,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary600,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  l?.tr('bot_settings.wame_hint') ??
                      'À coller sur la bio Instagram, profil Google, etc.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: l?.tr('bot_settings.wame_copy') ?? 'Copier',
            onPressed: () => _copy(context),
            icon: const Icon(Icons.content_copy_rounded,
                size: 18, color: AppColors.brand700),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: AppColors.brand200),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Proactive opt-ins ─────────────────────────────────────────────

class _ProactivesCard extends StatelessWidget {
  final String salonId;
  final Map<String, dynamic> pro;
  final bool aiPromosEnabled;
  const _ProactivesCard({
    required this.salonId,
    required this.pro,
    required this.aiPromosEnabled,
  });

  Future<void> _toggle(String key, bool value) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.proactiveOptIn.$key': value});
  }

  /// Show the same in-app explanation Zayna would give when she returns
  /// `needs_ai_promo_config`: the proactive flow depends on AI promos
  /// being enabled with the discount/threshold config set. CTA jumps to
  /// the Promotions screen where "Réductions intelligentes" lives.
  void _showAiPromoGate(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('bot_settings.ai_gate_title') ??
            'Réductions intelligentes requises'),
        content: Text(l?.tr('bot_settings.ai_gate_body') ??
            'Ces messages envoient une réduction au client. Activez d\'abord les Réductions intelligentes (avec les % à appliquer) dans la page Promotions.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerPromotionsScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
            ),
            child: Text(l?.tr('bot_settings.ai_gate_configure') ??
                'Configurer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('bot_settings.proactives_title') ??
                'Messages proactifs',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('bot_settings.proactives_desc') ??
                'Zayna envoie ces messages automatiquement aux clients concernés. Cap de 20 envois par jour.',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary500,
                height: 1.4),
          ),
          const SizedBox(height: 8),
          // G3 + G2 depend on aiPromosEnabled (the discount %s come from
          // aiPromoConfig). When AI promos is off, the proactive CF
          // silently skips the salon — gate the toggle here so the
          // misconfig can't happen. Pour le owner : un tap sur le toggle
          // ouvre un dialog qui le redirige vers la page Promotions.
          _toggleRow(
            label: l?.tr('bot_settings.g3_label') ?? 'Anniversaire',
            desc: l?.tr('bot_settings.g3_desc') ??
                'Souhait + offre (Marketing — opt-in client requis)',
            value: pro['g3'] != false,
            onChanged: aiPromosEnabled ? (v) => _toggle('g3', v) : null,
            gatedNote: aiPromosEnabled
                ? null
                : (l?.tr('bot_settings.needs_ai_promos') ??
                    'Nécessite Réductions intelligentes'),
            onGatedTap: () => _showAiPromoGate(context),
          ),
          _toggleRow(
            label: l?.tr('bot_settings.g2_label') ??
                'Réactivation absence',
            desc: l?.tr('bot_settings.g2_desc') ??
                'Relance les clients silencieux (Marketing — opt-in client requis)',
            value: pro['g2'] != false,
            onChanged: aiPromosEnabled ? (v) => _toggle('g2', v) : null,
            gatedNote: aiPromosEnabled
                ? null
                : (l?.tr('bot_settings.needs_ai_promos') ??
                    'Nécessite Réductions intelligentes'),
            onGatedTap: () => _showAiPromoGate(context),
          ),
          _toggleRow(
            label: l?.tr('bot_settings.j2_label') ??
                'Demande d\'avis Google',
            desc: l?.tr('bot_settings.j2_desc') ??
                'Envoyé J+1 après un RDV terminé (Utility, sans opt-in)',
            value: pro['j2'] != false,
            onChanged: (v) => _toggle('j2', v),
          ),
          _toggleRow(
            label: l?.tr('bot_settings.k3_label') ??
                'Place libérée (waitlist)',
            desc: l?.tr('bot_settings.k3_desc') ??
                'Notifie les clients en liste d\'attente (Utility)',
            value: pro['k3'] != false,
            onChanged: (v) => _toggle('k3', v),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow({
    required String label,
    required String desc,
    required bool value,
    required ValueChanged<bool>? onChanged,
    String? gatedNote,
    VoidCallback? onGatedTap,
  }) {
    final isGated = onChanged == null;
    return InkWell(
      onTap: isGated ? onGatedTap : null,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isGated
                          ? AppColors.secondary400
                          : AppColors.brand950,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    desc,
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.secondary500),
                  ),
                  if (gatedNote != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.lock_outline_rounded,
                            size: 12, color: Color(0xFFB45309)),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            gatedNote,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB45309),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Switch(
              value: isGated ? false : value,
              onChanged: onChanged,
              activeColor: AppColors.brand600,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Behaviour (tone, upsell, sentiment) ───────────────────────────

class _BehaviourCard extends StatelessWidget {
  final String salonId;
  final Map<String, dynamic> cfg;
  const _BehaviourCard({required this.salonId, required this.cfg});

  Future<void> _set(String field, dynamic value) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.$field': value});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final tone = cfg['tone'] as String? ?? 'friendly';
    final upsell = cfg['upsellEnabled'] != false; // default true
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('bot_settings.behaviour_title') ?? 'Comportement',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l?.tr('bot_settings.tone_label') ?? 'Ton de la conversation',
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.brand950),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _toneChip(context, 'friendly',
                  l?.tr('bot_settings.tone_friendly') ?? 'Amical', tone, _set),
              _toneChip(context, 'professional',
                  l?.tr('bot_settings.tone_professional') ?? 'Professionnel', tone, _set),
              _toneChip(context, 'casual',
                  l?.tr('bot_settings.tone_casual') ?? 'Décontracté', tone, _set),
              _toneChip(context, 'formal',
                  l?.tr('bot_settings.tone_formal') ?? 'Formel', tone, _set),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('bot_settings.upsell_label') ?? 'Suggestions d\'add-ons',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l?.tr('bot_settings.upsell_desc') ??
                          'Zayna propose des prestations complémentaires lors d\'une réservation',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary500),
                    ),
                  ],
                ),
              ),
              Switch(
                value: upsell,
                onChanged: (v) => _set('upsellEnabled', v),
                activeColor: AppColors.brand600,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _toneChip(BuildContext context, String value, String label,
      String current, Future<void> Function(String, dynamic) onSet) {
    final selected = current == value;
    return InkWell(
      onTap: () => onSet('tone', value),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.brand600 : AppColors.secondary50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.secondary200),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.secondary600,
          ),
        ),
      ),
    );
  }
}

// ── Learned FAQ ───────────────────────────────────────────────────

class _LearnedFaqCard extends StatefulWidget {
  final String salonId;
  const _LearnedFaqCard({required this.salonId});

  @override
  State<_LearnedFaqCard> createState() => _LearnedFaqCardState();
}

class _LearnedFaqCardState extends State<_LearnedFaqCard> {
  static const int _kInitialCount = 5;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('bot_settings.faq_title') ?? 'FAQ apprenante',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('bot_settings.faq_desc') ??
                'Zayna mémorise vos réponses pour répondre directement aux prochaines questions similaires.',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary500,
                height: 1.4),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('salons')
                .doc(widget.salonId)
                .collection('botKnowledge')
                .orderBy('lastUsedAt', descending: true)
                .limit(50)
                .snapshots(),
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final docs = snap.data?.docs ?? [];
              if (docs.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    l?.tr('bot_settings.faq_empty') ??
                        'Aucune réponse mémorisée pour l\'instant. Zayna apprend dès que vous répondez à un client via elle.',
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary500,
                        fontStyle: FontStyle.italic),
                  ),
                );
              }
              final visible = _expanded ? docs : docs.take(_kInitialCount).toList();
              final hidden = docs.length - visible.length;
              return Column(
                children: [
                  ...visible.map((d) => _FaqRow(
                        docRef: d.reference,
                        data: d.data(),
                      )),
                  if (docs.length > _kInitialCount) ...[
                    const SizedBox(height: 4),
                    InkWell(
                      onTap: () => setState(() => _expanded = !_expanded),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              _expanded
                                  ? Icons.keyboard_arrow_up_rounded
                                  : Icons.keyboard_arrow_down_rounded,
                              size: 16,
                              color: AppColors.brand600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _expanded
                                  ? (l?.tr('bot_settings.faq_show_less') ??
                                      'Voir moins')
                                  : ((l?.tr('bot_settings.faq_show_more') ??
                                          'Voir les {count} autres')
                                      .replaceAll(
                                          '{count}', hidden.toString())),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.brand600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  final DocumentReference<Map<String, dynamic>> docRef;
  final Map<String, dynamic> data;
  const _FaqRow({required this.docRef, required this.data});

  Future<void> _delete(BuildContext context) async {
    final l = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(l?.tr('bot_settings.faq_delete_title') ??
            'Supprimer cette réponse ?'),
        content: Text(l?.tr('bot_settings.faq_delete_body') ??
            'Zayna ne pourra plus utiliser cette réponse pour les questions similaires.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(
              l?.tr('common_delete') ?? 'Supprimer',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      await docRef.delete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final question = data['question'] as String? ?? '';
    final answer = data['answer'] as String? ?? '';
    final used = (data['askedCount'] as num?)?.toInt() ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.secondary50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  question,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 4),
                Text(
                  answer,
                  style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.secondary600,
                      height: 1.4),
                ),
                const SizedBox(height: 6),
                Text(
                  used == 1 ? '1 réutilisation' : '$used réutilisations',
                  style: const TextStyle(
                      fontSize: 10,
                      color: AppColors.secondary400,
                      fontStyle: FontStyle.italic),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => _delete(context),
            icon: const Icon(Icons.delete_outline_rounded,
                size: 18, color: AppColors.secondary500),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }
}

// ── Setup wizard relaunch ─────────────────────────────────────────

class _SetupWizardCard extends StatelessWidget {
  final String? botWhatsapp;
  const _SetupWizardCard({required this.botWhatsapp});

  Future<void> _open(BuildContext context) async {
    final wa = (botWhatsapp ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (wa.isEmpty) return;
    final url = Uri.parse('https://wa.me/$wa?text=${Uri.encodeComponent("aide")}');
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible d\'ouvrir WhatsApp.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final disabled = botWhatsapp == null || botWhatsapp!.isEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE7F8EE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBBF0CC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.chat_bubble_outline,
                  color: Color(0xFF15803D), size: 20),
              const SizedBox(width: 8),
              Text(
                l?.tr('bot_settings.wizard_title') ??
                    'Discuter avec Zayna',
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF15803D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l?.tr('bot_settings.wizard_desc') ??
                'Ouvre WhatsApp avec votre numéro Zayna pour relancer la configuration ou modifier des règles métier en discutant.',
            style: const TextStyle(
                fontSize: 12, color: Color(0xFF166534), height: 1.4),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: disabled ? null : () => _open(context),
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              label: Text(
                l?.tr('bot_settings.wizard_cta') ??
                    'Ouvrir WhatsApp avec Zayna',
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

// ── Pause kill-switch ─────────────────────────────────────────────

class _PauseCard extends StatelessWidget {
  final String salonId;
  final bool paused;
  const _PauseCard({required this.salonId, required this.paused});

  Future<void> _toggle(BuildContext context, bool v) async {
    if (v) {
      // Confirm before pausing
      final ok = await showDialog<bool>(
        context: context,
        builder: (dCtx) => AlertDialog(
          title: Text(AppLocalizations.of(context)?.tr('bot_settings.pause_confirm_title') ??
              'Mettre Zayna en pause ?'),
          content: Text(AppLocalizations.of(context)?.tr('bot_settings.pause_confirm_body') ??
              'Aucun message ne sera traité jusqu\'à réactivation. Les conversations en cours sont gelées.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dCtx, false),
              child: Text(AppLocalizations.of(context)?.tr('common_cancel') ?? 'Annuler'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dCtx, true),
              child: Text(
                AppLocalizations.of(context)?.tr('bot_settings.pause_confirm_ok') ?? 'Mettre en pause',
                style: const TextStyle(color: Colors.redAccent),
              ),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.paused': v});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final color = paused ? Colors.red.shade600 : Colors.green.shade700;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: paused ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: paused ? Colors.red.shade200 : AppColors.secondary100),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              paused ? Icons.pause_circle_outline : Icons.bolt_rounded,
              color: color,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  paused
                      ? (l?.tr('bot_settings.paused_title') ??
                          'Zayna est en pause')
                      : (l?.tr('bot_settings.active_title') ??
                          'Zayna répond aux messages'),
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 2),
                Text(
                  paused
                      ? (l?.tr('bot_settings.paused_desc') ??
                          'Aucun message entrant n\'est traité.')
                      : (l?.tr('bot_settings.active_desc') ??
                          'Coupez l\'assistante en 1 clic en cas d\'urgence.'),
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.secondary500),
                ),
              ],
            ),
          ),
          Switch(
            value: paused,
            onChanged: (v) => _toggle(context, v),
            activeColor: Colors.red.shade600,
          ),
        ],
      ),
    );
  }
}

// ── Per-client daily message cap ──────────────────────────────────
//
// Owner-tunable rate-limit applied by `_checkClientDailyCap` in
// whatsappBot.ts. When `enabled == false`, the CF skips the cap check
// entirely (a client can send unlimited messages in 24h). When enabled,
// the slider value (clamped 30..100 in UI; CF clamps 1..500 defensively)
// becomes the per-client per-day ceiling. Hitting the ceiling routes to
// the existing handover-to-owner flow.
//
// Defaults preserve legacy behavior: `enabled=true, messagesPerDay=30`
// when the field is missing on a salon doc.

class _ClientCapCard extends StatefulWidget {
  final String salonId;
  final Map<String, dynamic> cfg;
  const _ClientCapCard({required this.salonId, required this.cfg});

  @override
  State<_ClientCapCard> createState() => _ClientCapCardState();
}

class _ClientCapCardState extends State<_ClientCapCard> {
  // Local mirror so the slider stays responsive while the write
  // round-trips Firestore. Debounced commit on slider end.
  late bool _enabled;
  late double _value;

  @override
  void initState() {
    super.initState();
    final raw = widget.cfg['clientDailyCap'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    _enabled = map['enabled'] != false; // default true
    final v = (map['messagesPerDay'] as num?)?.toInt() ?? 30;
    _value = v.clamp(30, 100).toDouble();
  }

  @override
  void didUpdateWidget(covariant _ClientCapCard old) {
    super.didUpdateWidget(old);
    // Reflect external changes (e.g. another device, or after a
    // Firestore round-trip) without clobbering an in-flight slide.
    final raw = widget.cfg['clientDailyCap'];
    final map = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final remoteEnabled = map['enabled'] != false;
    final remoteValue =
        ((map['messagesPerDay'] as num?)?.toInt() ?? 30).clamp(30, 100).toDouble();
    if (remoteEnabled != _enabled || (remoteValue - _value).abs() > 0.01) {
      setState(() {
        _enabled = remoteEnabled;
        _value = remoteValue;
      });
    }
  }

  Future<void> _writeEnabled(bool v) async {
    setState(() => _enabled = v);
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(widget.salonId)
        .update({
      'botConfig.clientDailyCap.enabled': v,
      'botConfig.clientDailyCap.messagesPerDay': _value.toInt(),
    });
  }

  Future<void> _writeValue(int v) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(widget.salonId)
        .update({'botConfig.clientDailyCap.messagesPerDay': v});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.speed_rounded,
                  color: AppColors.brand700,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('bot_settings.client_cap_title') ??
                          'Limite par client (24h)',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.brand950,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _enabled
                          ? (l?.tr('bot_settings.client_cap_desc_on') ??
                              'Plafond le nombre de messages que Zayna traite par client et par jour.')
                          : (l?.tr('bot_settings.client_cap_desc_off') ??
                              'Aucune limite — Zayna répond sans plafond par client.'),
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _enabled,
                onChanged: _writeEnabled,
                activeColor: AppColors.brand600,
              ),
            ],
          ),
          if (_enabled) ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.secondary100),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    (l?.tr('bot_settings.client_cap_slider_label') ??
                            '{n} messages / client / jour')
                        .replaceAll('{n}', '${_value.toInt()}'),
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand950,
                    ),
                  ),
                ),
                Text(
                  '${_value.toInt()}',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand700,
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                activeTrackColor: AppColors.brand600,
                inactiveTrackColor: AppColors.brand100,
                thumbColor: AppColors.brand700,
                overlayShape:
                    const RoundSliderOverlayShape(overlayRadius: 16),
                thumbShape:
                    const RoundSliderThumbShape(enabledThumbRadius: 8),
              ),
              child: Slider(
                value: _value,
                min: 30,
                max: 100,
                divisions: 7, // 30, 40, 50, 60, 70, 80, 90, 100
                onChanged: (v) => setState(() => _value = v),
                onChangeEnd: (v) => _writeValue(v.toInt()),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('30',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.secondary400)),
                Text('100',
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.secondary400)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              l?.tr('bot_settings.client_cap_hint') ??
                  'Au-delà, Zayna transfère la conversation à votre WhatsApp pour que vous repreniez la main.',
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary400,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Escalation cases ──────────────────────────────────────────────

class _EscalationCard extends StatelessWidget {
  final String salonId;
  final Map<String, dynamic> escal;
  const _EscalationCard({required this.salonId, required this.escal});

  static const _kCases = [
    'complaint',
    'price_dispute',
    'unknown_allergy',
    'service_unavailable',
    'refund_request',
    'sensitive_topic',
  ];

  Future<void> _toggle(String key, bool v) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.escalationCases.$key': v});
  }

  String _label(AppLocalizations? l, String key) {
    final fallback = {
      'complaint': 'Réclamation client',
      'price_dispute': 'Désaccord sur un prix',
      'unknown_allergy': 'Allergie non répertoriée',
      'service_unavailable': 'Service hors catalogue',
      'refund_request': 'Demande de remboursement',
      'sensitive_topic': 'Sujet sensible (santé, etc.)',
    }[key]!;
    return l?.tr('bot_settings.escal_$key') ?? fallback;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('bot_settings.escal_title') ?? 'Cas d\'escalade',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('bot_settings.escal_desc') ??
                'Quand l\'un de ces cas est détecté, Zayna vous transfère la conversation par WhatsApp.',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary500,
                height: 1.4),
          ),
          const SizedBox(height: 8),
          ..._kCases.map((key) {
            // Default ON: missing key OR explicit true → active.
            final value = escal[key] != false;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _label(l, key),
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950),
                    ),
                  ),
                  Switch(
                    value: value,
                    onChanged: (v) => _toggle(key, v),
                    activeColor: AppColors.brand600,
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Allergens to monitor ──────────────────────────────────────────

class _AllergensCard extends StatefulWidget {
  final String salonId;
  final List<String> allergens;
  const _AllergensCard({required this.salonId, required this.allergens});

  @override
  State<_AllergensCard> createState() => _AllergensCardState();
}

class _AllergensCardState extends State<_AllergensCard> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _add(String value) async {
    final v = value.trim();
    if (v.isEmpty) return;
    if (widget.allergens.contains(v)) return;
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(widget.salonId)
        .update({
      'botConfig.allergens': FieldValue.arrayUnion([v])
    });
    _ctrl.clear();
  }

  Future<void> _remove(String v) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(widget.salonId)
        .update({
      'botConfig.allergens': FieldValue.arrayRemove([v])
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l?.tr('bot_settings.allergens_title') ??
                'Allergènes à surveiller',
            style: GoogleFonts.dmSans(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('bot_settings.allergens_desc') ??
                'Liste des ingrédients à risque (PPD, formaldéhyde, ammoniaque…). Zayna alerte le client si un service en contient et bloque la résa en cas de match avec ses allergies déclarées.',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary500,
                height: 1.4),
          ),
          const SizedBox(height: 12),
          if (widget.allergens.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.allergens
                  .map((a) => Chip(
                        label: Text(a, style: const TextStyle(fontSize: 12)),
                        onDeleted: () => _remove(a),
                        deleteIconColor: AppColors.secondary500,
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: Colors.red.shade200),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  onSubmitted: _add,
                  decoration: InputDecoration(
                    hintText: l?.tr('bot_settings.allergens_hint') ??
                        'Ex: PPD, formaldéhyde, résorcinol…',
                    hintStyle: const TextStyle(
                        fontSize: 13, color: AppColors.secondary400),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.secondary200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.secondary200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(
                          color: AppColors.brand500, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _add(_ctrl.text),
                icon: const Icon(Icons.add_circle_rounded,
                    size: 28, color: AppColors.brand600),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── FAQ pré-remplie (faqBase) ─────────────────────────────────────

class _FaqBaseCard extends StatelessWidget {
  final String salonId;
  final List<Map<String, dynamic>> faqBase;
  const _FaqBaseCard({required this.salonId, required this.faqBase});

  Future<void> _delete(String id) async {
    final updated = faqBase.where((q) => q['id'] != id).toList();
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.faqBase': updated});
  }

  Future<void> _editOrAdd(BuildContext context, [Map<String, dynamic>? existing]) async {
    final l = AppLocalizations.of(context);
    final qCtrl = TextEditingController(text: existing?['question'] as String? ?? '');
    final aCtrl = TextEditingController(text: existing?['answer'] as String? ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        title: Text(existing == null
            ? (l?.tr('bot_settings.faqbase_add') ?? 'Ajouter une réponse')
            : (l?.tr('bot_settings.faqbase_edit') ?? 'Modifier la réponse')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: qCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: l?.tr('bot_settings.faqbase_q_label') ?? 'Question',
                  hintText: l?.tr('bot_settings.faqbase_q_hint') ??
                      'Ex: Faites-vous des balayages sur cheveux noirs ?',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: aCtrl,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText: l?.tr('bot_settings.faqbase_a_label') ?? 'Réponse de Zayna',
                  hintText: l?.tr('bot_settings.faqbase_a_hint') ??
                      'Ex: Oui, sur cheveux noirs nous proposons un balayage progressif…',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dCtx, true),
            child: Text(l?.tr('common_save') ?? 'Enregistrer'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final question = qCtrl.text.trim();
    final answer = aCtrl.text.trim();
    if (question.isEmpty || answer.isEmpty) return;

    final id = existing?['id'] as String? ??
        DateTime.now().millisecondsSinceEpoch.toString();
    final updated = [...faqBase];
    final idx = updated.indexWhere((q) => q['id'] == id);
    final entry = {
      'id': id,
      'question': question,
      'answer': answer,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    if (idx >= 0) {
      updated[idx] = entry;
    } else {
      updated.add(entry);
    }
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.faqBase': updated});
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
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
              Expanded(
                child: Text(
                  l?.tr('bot_settings.faqbase_title') ??
                      'FAQ pré-remplie',
                  style: GoogleFonts.dmSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => _editOrAdd(context),
                icon: const Icon(Icons.add_circle_rounded,
                    size: 24, color: AppColors.brand600),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('bot_settings.faqbase_desc') ??
                'Pré-rédigez les réponses aux questions courantes. Zayna les utilise en priorité (avant la FAQ apprenante et avant le LLM).',
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary500,
                height: 1.4),
          ),
          const SizedBox(height: 12),
          if (faqBase.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                l?.tr('bot_settings.faqbase_empty') ??
                    'Aucune FAQ pré-remplie. Cliquez sur + pour en ajouter.',
                style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.secondary500,
                    fontStyle: FontStyle.italic),
              ),
            )
          else
            ...faqBase.map((entry) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry['question']?.toString() ?? '',
                              style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brand950),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              entry['answer']?.toString() ?? '',
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.secondary600,
                                  height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => _editOrAdd(context, entry),
                        icon: const Icon(Icons.edit_outlined,
                            size: 18, color: AppColors.secondary500),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const SizedBox(width: 6),
                      IconButton(
                        onPressed: () =>
                            _delete(entry['id']?.toString() ?? ''),
                        icon: const Icon(Icons.delete_outline_rounded,
                            size: 18, color: AppColors.secondary500),
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}

// ── Business plan gate ────────────────────────────────────────────

/// Upsell screen shown to Free + Essential plan owners when they tap the
/// "Assistant BOT" entry. Replaces the previous flat "Business only"
/// gate. Three sections:
///   1. Hero header with a looping WhatsApp-style chat preview cycling
///      through Zayna's capabilities (4 scenarios × 3s = 12s loop).
///   2. Feature bullets that describe what Zayna does, in the owner's
///      terms (not technical).
///   3. CTA pushing to OwnerSubscriptionScreen for the upgrade.
///
/// Keeps the source order text-first for screen-readers; visual ordering
/// is preserved via Column for native a11y tree.
class _BusinessGate extends StatefulWidget {
  final AppLocalizations? l;
  const _BusinessGate({required this.l});

  @override
  State<_BusinessGate> createState() => _BusinessGateState();
}

class _BusinessGateState extends State<_BusinessGate>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  int _scene = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() => _scene = (_scene + 1) % 4);
          _ctrl.forward(from: 0);
        }
      });
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // 4 scenarios, each a pair (client → Zayna). Stay short so they read
  // at-a-glance during the 3s window. Texts are i18n-keyed.
  List<({String tr, String fallback, bool fromZayna})> _scenes(int i) {
    switch (i) {
      case 0:
        return [
          (
            tr: 'bot_upsell.scene1_client',
            fallback: 'Salam, RDV mardi 18h pour une coupe ?',
            fromZayna: false
          ),
          (
            tr: 'bot_upsell.scene1_zayna',
            fallback: "Bonjour ! Mardi 18h c'est libre avec Sarah. Je confirme ?",
            fromZayna: true
          ),
        ];
      case 1:
        return [
          (
            tr: 'bot_upsell.scene2_client',
            fallback: 'Tu te souviens de mes allergies ?',
            fromZayna: false
          ),
          (
            tr: 'bot_upsell.scene2_zayna',
            fallback: 'Oui Yasmin, ammoniaque et sulfates. On reste sur Olaplex.',
            fromZayna: true
          ),
        ];
      case 2:
        return [
          (
            tr: 'bot_upsell.scene3_client',
            fallback: 'Vous ouvrez à quelle heure dimanche ?',
            fromZayna: false
          ),
          (
            tr: 'bot_upsell.scene3_zayna',
            fallback: '10h - 19h en continu. À dimanche !',
            fromZayna: true
          ),
        ];
      default:
        return [
          (
            tr: 'bot_upsell.scene4_zayna',
            fallback: "Salut Marie 👋 RDV demain 14h avec Sophie. À demain !",
            fromZayna: true
          ),
          (
            tr: 'bot_upsell.scene4_client',
            fallback: 'Merci, confirmé !',
            fromZayna: false
          ),
        ];
    }
    // Unreachable — default returns above.
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.l;
    final scenes = _scenes(_scene);

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Hero header ────────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppColors.brand50,
                    Color(0xFFFAFBF5),
                  ],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.brand100),
              ),
              child: Column(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.brand500,
                          AppColors.brand700,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.brand500.withValues(alpha: 0.3),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l?.tr('bot_upsell.title') ??
                        'Zayna, votre assistante WhatsApp',
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.brand950,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    l?.tr('bot_upsell.subtitle') ??
                        'Elle répond, réserve et fidélise vos clients sur WhatsApp, 24h/24, dans leur langue.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary500,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 20),

                  // ── Animated chat preview ────────────────────────
                  _ChatPreview(
                    key: ValueKey('scene_$_scene'),
                    bubbles: scenes,
                    l: l,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Feature bullets ─────────────────────────────────────
            _Feature(
              icon: Icons.chat_bubble_rounded,
              iconBg: const Color(0xFFDCFCE7),
              iconColor: const Color(0xFF16A34A),
              title: l?.tr('bot_upsell.feat1_title') ??
                  'Réservations 24/7 sur WhatsApp',
              body: l?.tr('bot_upsell.feat1_body') ??
                  'Plus aucun appel manqué la nuit ou le dimanche. Vos clients réservent directement par WhatsApp et Zayna prend le RDV à votre place.',
            ),
            const SizedBox(height: 14),
            _Feature(
              icon: Icons.favorite_rounded,
              iconBg: const Color(0xFFFCE7F3),
              iconColor: const Color(0xFFDB2777),
              title: l?.tr('bot_upsell.feat2_title') ??
                  'Mémoire client personnalisée',
              body: l?.tr('bot_upsell.feat2_body') ??
                  'Préférences, allergies, dernière prestation : Zayna se souvient de chaque cliente et adapte ses réponses sans que vous ayez à le lui dire.',
            ),
            const SizedBox(height: 14),
            _Feature(
              icon: Icons.flash_on_rounded,
              iconBg: const Color(0xFFFEF3C7),
              iconColor: const Color(0xFFD97706),
              title: l?.tr('bot_upsell.feat3_title') ??
                  'Rappels et promos automatiques',
              body: l?.tr('bot_upsell.feat3_body') ??
                  'Rappels J-1 et H-1 envoyés tout seuls, win-back des clientes inactives, promo anniversaire — sans rien faire de votre côté.',
            ),
            const SizedBox(height: 14),
            _Feature(
              icon: Icons.insights_rounded,
              iconBg: const Color(0xFFDBEAFE),
              iconColor: const Color(0xFF2563EB),
              title: l?.tr('bot_upsell.feat4_title') ??
                  'Votre tableau de bord WhatsApp',
              body: l?.tr('bot_upsell.feat4_body') ??
                  'Demandez à Zayna depuis votre propre WhatsApp : « CA d\'avril ? », « Qui est libre vendredi 15h ? », « Mes top clientes VIP ? ». Elle répond directement.',
            ),

            const SizedBox(height: 28),

            // ── See-more button ─────────────────────────────────────
            // Same sheet the header help-icon opens on the Business
            // version of this screen — reusing it keeps a single source
            // of truth for "what Zayna can do".
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showZaynaCapabilitiesSheet(context),
                icon: const Icon(Icons.menu_book_rounded, size: 18),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    l?.tr('bot_upsell.see_capabilities') ??
                        'Voir toutes les capacités',
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brand700,
                  side: const BorderSide(color: AppColors.brand200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),

            // ── CTA ─────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerSubscriptionScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.workspace_premium_rounded, size: 20),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    l?.tr('bot_upsell.cta') ??
                        'Passer à Business pour activer Zayna',
                    style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l?.tr('bot_upsell.cta_hint') ??
                  '1000 messages WhatsApp inclus par mois',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.secondary400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two WhatsApp-style bubbles that fade in sequentially. Keyed on the
/// scene index by the parent so swapping scenes rebuilds the widget and
/// re-plays the entry animation.
class _ChatPreview extends StatefulWidget {
  const _ChatPreview({
    super.key,
    required this.bubbles,
    required this.l,
  });
  final List<({String tr, String fallback, bool fromZayna})> bubbles;
  final AppLocalizations? l;

  @override
  State<_ChatPreview> createState() => _ChatPreviewState();
}

class _ChatPreviewState extends State<_ChatPreview>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFECE5DD),
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.all(12),
      child: SizedBox(
        height: 130,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.bubbles.length; i++) ...[
              _AnimatedBubble(
                controller: _ctrl,
                delay: i == 0 ? 0.0 : 0.45,
                text: widget.l?.tr(widget.bubbles[i].tr) ??
                    widget.bubbles[i].fallback,
                fromZayna: widget.bubbles[i].fromZayna,
              ),
              if (i < widget.bubbles.length - 1) const SizedBox(height: 6),
            ],
          ],
        ),
      ),
    );
  }
}

class _AnimatedBubble extends StatelessWidget {
  const _AnimatedBubble({
    required this.controller,
    required this.delay,
    required this.text,
    required this.fromZayna,
  });

  final AnimationController controller;
  final double delay;
  final String text;
  final bool fromZayna;

  @override
  Widget build(BuildContext context) {
    final anim = CurvedAnimation(
      parent: controller,
      curve: Interval(delay, (delay + 0.5).clamp(0, 1),
          curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) {
        return Opacity(
          opacity: anim.value,
          child: Transform.translate(
            offset: Offset(0, (1 - anim.value) * 8),
            child: child,
          ),
        );
      },
      child: Align(
        alignment:
            fromZayna ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 260),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: fromZayna ? const Color(0xFFDCF8C6) : Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(10),
                topRight: const Radius.circular(10),
                bottomLeft: Radius.circular(fromZayna ? 10 : 2),
                bottomRight: Radius.circular(fromZayna ? 2 : 10),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: Color(0xFF1F2A1B),
                height: 1.35,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.dmSans(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                body,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: AppColors.secondary500,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
