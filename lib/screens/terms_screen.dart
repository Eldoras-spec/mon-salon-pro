import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.brand900),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Conditions d\'utilisation',
          style: GoogleFonts.dmSans(
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Dernière mise à jour : 27 avril 2026',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: AppColors.secondary400,
              ),
            ),
            const SizedBox(height: 24),
            _buildSection(
              '1. Acceptation des conditions',
              'En utilisant l\'application Mon Salon, vous acceptez les présentes conditions d\'utilisation. '
                  'Si vous n\'acceptez pas ces conditions, veuillez ne pas utiliser l\'application.',
            ),
            _buildSection(
              '2. Description du service',
              'Mon Salon est une application de prise de rendez-vous en ligne qui permet :\n\n'
                  '• Aux clients : de rechercher des salons, réserver des créneaux, consulter les services proposés et gérer leurs rendez-vous.\n\n'
                  '• Aux propriétaires de salons : de gérer leur établissement, leurs rendez-vous, leur équipe, leurs finances et leurs promotions.',
            ),
            _buildSection(
              '3. Inscription et compte',
              '• Vous devez fournir des informations exactes lors de l\'inscription.\n\n'
                  '• Vous êtes responsable de la confidentialité de votre mot de passe.\n\n'
                  '• Un seul compte par personne est autorisé.\n\n'
                  '• Vous devez avoir au moins 16 ans pour utiliser l\'application.',
            ),
            _buildSection(
              '4. Réservations et rendez-vous',
              '• Les réservations sont confirmées une fois validées par le salon.\n\n'
                  '• Toute annulation doit être effectuée dans un délai raisonnable avant le rendez-vous.\n\n'
                  '• Les prix affichés sont indicatifs et peuvent varier selon les prestations réalisées.\n\n'
                  '• Mon Salon n\'est pas responsable des prestations réalisées par les salons.',
            ),
            _buildSection(
              '5. Obligations des utilisateurs',
              '• Ne pas utiliser l\'application à des fins illégales ou frauduleuses.\n\n'
                  '• Ne pas perturber le fonctionnement de l\'application.\n\n'
                  '• Respecter les autres utilisateurs et les professionnels.\n\n'
                  '• Ne pas publier de contenu offensant ou inapproprié dans les avis.',
            ),
            _buildSection(
              '6. Obligations des propriétaires de salons',
              '• Fournir des informations exactes sur les services, horaires et tarifs.\n\n'
                  '• Honorer les rendez-vous confirmés.\n\n'
                  '• Respecter les normes d\'hygiène et de sécurité en vigueur.\n\n'
                  '• Traiter les données des clients de manière confidentielle.',
            ),
            _buildSection(
              '7. Codes promotionnels',
              '• Les codes promotionnels sont soumis à des conditions spécifiques (durée de validité, utilisation unique, etc.).\n\n'
                  '• Mon Salon se réserve le droit de modifier ou supprimer une offre promotionnelle à tout moment.',
            ),
            _buildSection(
              '7 bis. Abonnements et paiements',
              '• Mon Salon propose trois plans : Free (gratuit, équipe limitée à 2 membres), Essentiel (équipe illimitée + rappels WhatsApp + paiements par carte à commission réduite), Business (Essentiel + assistante WhatsApp Zayna 1000 messages/mois inclus + paiements par carte à commission minimale + vidéos premium).\n\n'
                  '• Les abonnements Essentiel et Business sont facturés mensuellement via Apple In-App Purchase, Google Play Billing ou Stripe selon la plateforme.\n\n'
                  '• Vous pouvez annuler votre abonnement à tout moment ; il reste actif jusqu\'à la fin de la période payée.',
            ),
            _buildSection(
              '7 ter. Paiements en ligne via Stripe Connect',
              '• Tous les plans (Free, Essentiel, Business) peuvent activer les paiements par carte bancaire (incluant Apple Pay et Google Pay) pour leurs prestations et leurs produits boutique, via Stripe Connect Express.\n\n'
                  '• Le salon connecte son propre compte Stripe et est le « merchant of record » pour toutes les transactions effectuées via son compte. Il est responsable de l\'exécution des prestations, de la TVA, des litiges et des chargebacks.\n\n'
                  '• Pour chaque prestation, le salon peut configurer : aucun paiement, paiement intégral, acompte en pourcentage, ou acompte fixe au-delà d\'un seuil.\n\n'
                  '• Mon Salon prélève une commission de plateforme variable selon le plan : 5% pour Free, 3% pour Essentiel, 1% pour Business. Les frais Stripe (~2,9% + 0,30 USD selon les pays) sont indépendants et déduits par Stripe.\n\n'
                  '• Mon Salon ne stocke aucune donnée bancaire ; toutes les informations de carte transitent par les systèmes PCI-DSS Level 1 de Stripe.\n\n'
                  '• Les salons en plan Business bénéficient également de l\'assistante WhatsApp IA Zayna avec 1000 messages/mois inclus ; au-delà, des packs bonus sont disponibles via Stripe.',
            ),
            _buildSection(
              '8. Propriété intellectuelle',
              'Tous les contenus de l\'application (textes, images, logos, design) sont protégés par les droits de propriété intellectuelle. '
                  'Toute reproduction ou utilisation sans autorisation est interdite.',
            ),
            _buildSection(
              '9. Limitation de responsabilité',
              '• Mon Salon agit en tant qu\'intermédiaire entre les clients et les salons.\n\n'
                  '• Nous ne sommes pas responsables de la qualité des prestations fournies par les salons.\n\n'
                  '• L\'application est fournie « en l\'état », sans garantie de disponibilité permanente.',
            ),
            _buildSection(
              '10. Résiliation',
              '• Vous pouvez supprimer votre compte à tout moment.\n\n'
                  '• Nous nous réservons le droit de suspendre ou supprimer un compte en cas de non-respect des présentes conditions.',
            ),
            _buildSection(
              '11. Modifications',
              'Nous nous réservons le droit de modifier ces conditions à tout moment. '
                  'Les utilisateurs seront informés des modifications importantes. '
                  'L\'utilisation continue de l\'application vaut acceptation des nouvelles conditions.',
            ),
            _buildSection(
              '12. Contact',
              'Pour toute question relative à ces conditions, vous pouvez nous contacter à :\n\n'
                  'Email : contact@blagence.com',
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            content,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.secondary600,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
