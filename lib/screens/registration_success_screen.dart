import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../services/notification_service.dart';
import '../services/database_service.dart';
import 'client_salon_profile_screen.dart';

class RegistrationSuccessScreen extends StatefulWidget {
  final bool isOwner;

  const RegistrationSuccessScreen({super.key, this.isOwner = true});

  @override
  State<RegistrationSuccessScreen> createState() =>
      _RegistrationSuccessScreenState();
}

class _RegistrationSuccessScreenState extends State<RegistrationSuccessScreen> {
  bool _notificationsEnabled = false;
  final NotificationService _notificationService = NotificationService();

  Future<void> _goToDashboard() async {
    if (_notificationsEnabled) {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        try {
          await _notificationService.saveTokenForUser(user.uid);
        } catch (e) {
          debugPrint('Erreur FCM token: $e');
        }
      }
    }

    if (!mounted) return;

    Navigator.of(
      context,
      rootNavigator: true,
    ).popUntil((route) => route.isFirst);
  }

  Future<void> _previewProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final salon = await DatabaseService().getSalon(user.uid);
    if (salon == null || !mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ClientSalonProfileScreen(salon: salon),
      ),
    );
  }

  Future<void> _handleNotificationToggle(bool value) async {
    setState(() {
      _notificationsEnabled = value;
    });

    if (value) {
      await _notificationService.initialize();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: SingleChildScrollView(
        child: Column(
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: _buildBrandSection(),
            ),
            _buildContentSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildBrandSection() {
    return Container(
      color: AppColors.brand900,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://storage.googleapis.com/uxpilot-auth.appspot.com/f0e856fedb-2199ac55601432ae5ca2.png',
            fit: BoxFit.cover,
            color: AppColors.brand950.withValues(alpha: 0.8),
            colorBlendMode: BlendMode.overlay,
            errorBuilder: (_, _, _) => Container(color: AppColors.brand900),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Icon(
                          Icons.spa,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Mon Salon',
                        style: GoogleFonts.dmSans(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox.shrink(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContentSection() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 40,
            offset: Offset(0, -10),
          ),
        ],
      ),
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
                      ? 'Tout est prêt !'
                      : 'Bienvenue sur Mon Salon !',
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
                      ? 'Votre profil salon a été créé avec succès. Vous pouvez maintenant gérer vos rendez-vous et vos clients.'
                      : 'Votre compte a été créé. Vous êtes prêt à découvrir et réserver les meilleurs professionnels près de chez vous.',
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
                        widget.isOwner ? 'RÉCAPITULATIF' : 'DÉTAILS DU COMPTE',
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
                          'Profil créé',
                          'Votre salon est en ligne',
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          'Services configurés',
                          'Vos services sont prêts',
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          'Équipe ajoutée',
                          'Vos employés sont assignés',
                        ),
                      ] else ...[
                        _buildSummaryItem(
                            'Profil actif', 'Membre standard'),
                        const SizedBox(height: 16),
                        _buildSummaryItem(
                          'Email vérifié',
                          'Compte prêt à utiliser',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 32),

                // Notification Toggle
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: AppColors.secondary200),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: const BoxDecoration(
                          color: AppColors.brand50,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.notifications_outlined,
                          color: AppColors.brand600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Activer les notifications',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: AppColors.secondary900,
                              ),
                            ),
                            Text(
                              'Recevez des alertes pour les nouvelles réservations',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.secondary500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _notificationsEnabled,
                        onChanged: _handleNotificationToggle,
                        activeColor: AppColors.brand500,
                        activeTrackColor: AppColors.brand200,
                      ),
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
                            ? 'Aller au tableau de bord'
                            : 'Découvrir les salons',
                        onPressed: _goToDashboard,
                        icon: widget.isOwner
                            ? Icons.arrow_forward
                            : Icons.search,
                      ),
                    ),
                    if (widget.isOwner) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _previewProfile,
                          icon: const Icon(Icons.remove_red_eye, size: 18),
                          label: const Text('Aperçu du profil'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.secondary600,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            side: const BorderSide(
                              color: AppColors.secondary200,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
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
