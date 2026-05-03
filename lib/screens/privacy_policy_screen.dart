import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

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
          'Politique de confidentialité',
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
              '1. Introduction',
              'La protection de vos données personnelles est une priorité pour Mon Salon. '
                  'Cette politique décrit quelles données nous collectons, pourquoi et comment nous les utilisons.',
            ),
            _buildSection(
              '2. Données collectées',
              'Nous collectons les données suivantes :\n\n'
                  '• Informations de compte : nom, prénom, email.\n\n'
                  '• Données de réservation : historique des rendez-vous, services choisis, salons visités.\n\n'
                  '• Données de localisation : uniquement pour vous proposer des salons à proximité (avec votre accord).\n\n'
                  '• Données techniques : type d\'appareil, système d\'exploitation, pour améliorer l\'application.',
            ),
            _buildSection(
              '3. Utilisation des données',
              'Vos données sont utilisées pour :\n\n'
                  '• Gérer votre compte et vos réservations.\n\n'
                  '• Vous envoyer des rappels de rendez-vous par notification.\n\n'
                  '• Vous informer des promotions des salons que vous avez ajoutés en favoris.\n\n'
                  '• Améliorer nos services et l\'expérience utilisateur.\n\n'
                  '• Assurer la sécurité de l\'application.',
            ),
            _buildSection(
              '4. Partage des données',
              '• Avec les salons : votre nom et téléphone sont partagés avec le salon lors d\'une réservation pour permettre la prestation.\n\n'
                  '• Avec nos prestataires techniques : Google Firebase (hébergement, base de données), Google Cloud (modèle d\'IA Gemini pour l\'assistante WhatsApp Zayna), Stripe Inc. (traitement des paiements et abonnements), Infobip (envoi des messages WhatsApp d\'OTP et de Zayna), Meta WhatsApp Business (canal de communication WhatsApp).\n\n'
                  '• Nous ne vendons jamais vos données à des tiers.\n\n'
                  '• Nous pouvons partager des données anonymisées à des fins statistiques.',
            ),
            _buildSection(
              '4 bis. Paiements en ligne — Stripe Connect',
              '• Lorsqu\'un salon active les paiements en ligne, il connecte son propre compte Stripe via Stripe Connect Express.\n\n'
                  '• Vos informations bancaires (numéro de carte, CVC, etc.) sont collectées et stockées exclusivement par Stripe (PCI-DSS Level 1). Mon Salon ne stocke aucune donnée bancaire.\n\n'
                  '• Lors d\'un paiement, Stripe transmet à Mon Salon uniquement : montant, devise, identifiant de transaction, statut. Ces données sont liées à votre rendez-vous ou commande boutique.\n\n'
                  '• Politique de confidentialité Stripe : https://stripe.com/privacy',
            ),
            _buildSection(
              '4 ter. Assistante WhatsApp Zayna',
              '• Si le salon où vous réservez est en plan Business et a activé l\'assistante Zayna, vos messages WhatsApp avec ce salon sont traités par notre assistante IA basée sur Google Gemini.\n\n'
                  '• Les conversations sont stockées de manière sécurisée pour permettre la continuité du dialogue. Elles ne sont pas utilisées à d\'autres fins.\n\n'
                  '• Si vous nous envoyez un message vocal, il est transcrit par Gemini en texte (audio non conservé après transcription) puis traité comme un message texte.\n\n'
                  '• Vous pouvez à tout moment demander à parler avec une personne du salon via la commande "humain" ou "agent".',
            ),
            _buildSection(
              '5. Stockage et sécurité',
              '• Vos données sont stockées de manière sécurisée sur les serveurs Firebase (Google Cloud).\n\n'
                  '• Les mots de passe sont chiffrés et ne sont jamais stockés en clair.\n\n'
                  '• Nous mettons en œuvre des mesures de sécurité pour protéger vos données contre tout accès non autorisé.',
            ),
            _buildSection(
              '6. Notifications',
              '• Nous envoyons des notifications push pour les rappels de rendez-vous (24h avant) et les messages des salons.\n\n'
                  '• Vous pouvez désactiver les notifications à tout moment dans les réglages de votre appareil.',
            ),
            _buildSection(
              '7. Vos droits',
              'Conformément à la réglementation en vigueur, vous disposez des droits suivants :\n\n'
                  '• Droit d\'accès : consulter les données que nous détenons sur vous.\n\n'
                  '• Droit de rectification : corriger vos informations personnelles.\n\n'
                  '• Droit de suppression : demander la suppression de votre compte et de vos données.\n\n'
                  '• Droit de portabilité : récupérer vos données dans un format lisible.\n\n'
                  '• Droit d\'opposition : vous opposer au traitement de vos données.',
            ),
            _buildSection(
              '8. Cookies et traceurs',
              'L\'application n\'utilise pas de cookies. '
                  'Nous utilisons uniquement des identifiants techniques nécessaires au bon fonctionnement du service (tokens d\'authentification, tokens de notification).',
            ),
            _buildSection(
              '9. Durée de conservation',
              '• Données de compte : conservées tant que votre compte est actif.\n\n'
                  '• Historique de rendez-vous : conservé pendant 2 ans après le dernier rendez-vous.\n\n'
                  '• En cas de suppression de compte : vos données sont supprimées sous 30 jours.',
            ),
            _buildSection(
              '10. Mineurs',
              'L\'application est destinée aux personnes de 16 ans et plus. '
                  'Nous ne collectons pas sciemment de données auprès de mineurs de moins de 16 ans.',
            ),
            _buildSection(
              '11. Modifications',
              'Cette politique peut être mise à jour. Nous vous informerons de tout changement significatif. '
                  'La date de dernière mise à jour est indiquée en haut de cette page.',
            ),
            _buildSection(
              '12. Contact',
              'Pour exercer vos droits ou poser une question sur vos données :\n\n'
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
