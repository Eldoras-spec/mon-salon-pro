import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../services/app_localizations.dart';

class RegistrationSuccessScreen extends StatefulWidget {
  final bool isOwner;

  const RegistrationSuccessScreen({super.key, this.isOwner = true});

  @override
  State<RegistrationSuccessScreen> createState() =>
      _RegistrationSuccessScreenState();
}

class _RegistrationSuccessScreenState extends State<RegistrationSuccessScreen> {
  void _goToDashboard() {
    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // Success Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand500.withValues(alpha: 0.3),
                        blurRadius: 20,
                        spreadRadius: 5,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.check_circle,
                      color: AppColors.brand500,
                      size: 80,
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // Title & Subtitle
                Text(
                  widget.isOwner
                      ? (l?.tr('success_title') ?? 'Tout est pr\u00eat !')
                      : (l?.tr('success_welcome') ?? 'Bienvenue sur Mon Salon !'),
                  style: GoogleFonts.dmSans(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  widget.isOwner
                      ? (l?.tr('success_message') ?? 'Votre profil salon a \u00e9t\u00e9 cr\u00e9\u00e9 avec succ\u00e8s. Vous pouvez maintenant recevoir des r\u00e9servations.')
                      : 'Votre compte a \u00e9t\u00e9 cr\u00e9\u00e9. Vous \u00eates pr\u00eat \u00e0 d\u00e9couvrir et r\u00e9server les meilleurs professionnels pr\u00e8s de chez vous.',
                  style: const TextStyle(
                    color: AppColors.secondary500,
                    fontSize: 16,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 32),

                // Summary Card
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    border: Border.all(color: AppColors.secondary100),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isOwner
                            ? (l?.tr('success_recap') ?? 'R\u00c9CAPITULATIF')
                            : (l?.tr('success_account_details') ?? 'D\u00c9TAILS DU COMPTE'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary400,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (widget.isOwner) ...[
                        _buildSummaryItem(
                          l?.tr('success_profile_created') ?? 'Profil cr\u00e9\u00e9',
                          l?.tr('success_salon_online') ?? 'Votre salon est en ligne',
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          l?.tr('success_services_configured') ?? 'Services configur\u00e9s',
                          l?.tr('success_services_ready') ?? 'Vos services sont pr\u00eats',
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          l?.tr('success_team_added') ?? '\u00c9quipe ajout\u00e9e',
                          l?.tr('success_team_assigned') ?? 'Vos employ\u00e9s sont assign\u00e9s',
                        ),
                      ] else ...[
                        _buildSummaryItem(
                            'Profil actif', 'Membre standard'),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          'Email v\u00e9rifi\u00e9',
                          'Compte pr\u00eat \u00e0 utiliser',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 48),

                // Action Buttons
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: CustomButton(
                        text: widget.isOwner
                            ? (l?.tr('success_go_dashboard') ?? 'Aller au tableau de bord')
                            : (l?.tr('success_discover_salons') ?? 'D\u00e9couvrir les salons'),
                        onPressed: _goToDashboard,
                        icon: widget.isOwner
                            ? Icons.arrow_forward
                            : Icons.search,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildSummaryItem(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: const BoxDecoration(
            color: AppColors.brand100,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check, size: 12, color: AppColors.brand600),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.secondary800,
                ),
              ),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.secondary500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
