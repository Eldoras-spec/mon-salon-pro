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

/// Owner-facing config screen for the WhatsApp Zayna bot. Available
/// from `Profil → Assistant BOT` for Business-plan owners.
///
/// Streams `salons/{id}` for status + botConfig, and the
/// `salons/{id}/botKnowledge` subcollection for the learned FAQ.
///
/// Mutations write back to `salons/{id}.botConfig.*` directly (rules
/// allow owner-only updates on their own salon doc).
class OwnerBotSettingsScreen extends ConsumerWidget {
  const OwnerBotSettingsScreen({super.key});

  void _showHowItWorks(BuildContext context) {
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
            onPressed: () => _showHowItWorks(context),
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
              _ProactivesCard(
                salonId: salonId,
                pro: pro,
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
  const _ProactivesCard({required this.salonId, required this.pro});

  Future<void> _toggle(String key, bool value) async {
    await FirebaseFirestore.instance
        .collection('salons')
        .doc(salonId)
        .update({'botConfig.proactiveOptIn.$key': value});
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
          // All proactives default ON — owner decides what to disable.
          _toggleRow(
            l?.tr('bot_settings.g3_label') ?? 'Anniversaire',
            l?.tr('bot_settings.g3_desc') ??
                'Souhait + offre (Marketing — opt-in client requis)',
            pro['g3'] != false,
            (v) => _toggle('g3', v),
          ),
          _toggleRow(
            l?.tr('bot_settings.g2_label') ?? 'Réactivation 90 jours',
            l?.tr('bot_settings.g2_desc') ??
                'Relance les clients silencieux (Marketing — opt-in client requis)',
            pro['g2'] != false,
            (v) => _toggle('g2', v),
          ),
          _toggleRow(
            l?.tr('bot_settings.j2_label') ??
                'Demande d\'avis Google',
            l?.tr('bot_settings.j2_desc') ??
                'Envoyé J+1 après un RDV terminé (Utility, sans opt-in)',
            pro['j2'] != false,
            (v) => _toggle('j2', v),
          ),
          _toggleRow(
            l?.tr('bot_settings.k3_label') ?? 'Place libérée (waitlist)',
            l?.tr('bot_settings.k3_desc') ??
                'Notifie les clients en liste d\'attente (Utility)',
            pro['k3'] != false,
            (v) => _toggle('k3', v),
          ),
        ],
      ),
    );
  }

  Widget _toggleRow(
      String label, String desc, bool value, ValueChanged<bool> onChanged) {
    return Padding(
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
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(
                      fontSize: 11, color: AppColors.secondary500),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.brand600,
          ),
        ],
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

class _BusinessGate extends StatelessWidget {
  final AppLocalizations? l;
  const _BusinessGate({required this.l});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.brand50,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: AppColors.brand700, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              l?.tr('bot_settings.business_only_title') ??
                  'Réservé au plan Business',
              style: GoogleFonts.dmSans(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.brand950,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l?.tr('bot_settings.business_only_body') ??
                  'L\'assistante WhatsApp Zayna est incluse dans le plan Business. Passez Business pour activer la réception et la réponse automatique des messages clients.',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondary500,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
