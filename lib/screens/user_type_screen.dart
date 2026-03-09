import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import 'basic_registration_screen.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';

class UserTypeSelectionScreen extends StatefulWidget {
  const UserTypeSelectionScreen({super.key});

  @override
  State<UserTypeSelectionScreen> createState() =>
      _UserTypeSelectionScreenState();
}

class _UserTypeSelectionScreenState extends State<UserTypeSelectionScreen> {
  bool _isClientSelected = true;

  void _handleContinue() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            BasicRegistrationScreen(isClient: _isClientSelected),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 32),
                    _buildHeader(),
                    const SizedBox(height: 36),
                    _buildCard(
                      isClient: true,
                      emoji: '✂️',
                      title: 'Je suis client',
                      subtitle: 'Je cherche un salon et je réserve mes rendez-vous en ligne.',
                      accentColor: AppColors.brand600,
                      lightColor: AppColors.brand50,
                    ),
                    const SizedBox(height: 14),
                    _buildCard(
                      isClient: false,
                      emoji: '💼',
                      title: 'Je suis propriétaire',
                      subtitle: 'Je gère mon salon, mes équipes et mes clients.',
                      accentColor: const Color(0xFF7C3AED),
                      lightColor: const Color(0xFFF5F3FF),
                    ),
                    const SizedBox(height: 40),
                    CustomButton(
                      text: 'Continuer',
                      onPressed: _handleContinue,
                      icon: Icons.arrow_forward_rounded,
                    ),
                    const SizedBox(height: 20),
                    _buildTerms(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back_rounded),
            color: AppColors.secondary600,
          ),
          Row(
            children: List.generate(3, (i) {
              final active = i == 0;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: active ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.brand600 : AppColors.secondary200,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(width: 48), // balance the back button
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.brand50,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            'Étape 1 sur 3',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.brand600,
              letterSpacing: 0.3,
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Qui êtes-vous ?',
          style: GoogleFonts.dmSans(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Choisissez votre profil pour une\nexpérience entièrement personnalisée.',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.secondary500,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildCard({
    required bool isClient,
    required String emoji,
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color lightColor,
  }) {
    final selected = _isClientSelected == isClient;

    return GestureDetector(
      onTap: () => setState(() => _isClientSelected = isClient),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: selected ? lightColor : AppColors.secondary50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accentColor : Colors.transparent,
            width: 2,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ]
              : [],
        ),
        child: Row(
          children: [
            // Emoji icon
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: selected ? accentColor : AppColors.secondary200,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 26)),
              ),
            ),
            const SizedBox(width: 16),

            // Text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: selected ? AppColors.brand950 : AppColors.secondary700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.secondary500,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Radio indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? accentColor : Colors.transparent,
                border: Border.all(
                  color: selected ? accentColor : AppColors.secondary300,
                  width: 2,
                ),
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white, size: 14)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerms() {
    return Center(
      child: RichText(
        textAlign: TextAlign.center,
        text: TextSpan(
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color: AppColors.secondary400,
            height: 1.6,
          ),
          children: [
            const TextSpan(text: 'En continuant, vous acceptez nos '),
            TextSpan(
              text: 'Conditions d\'utilisation',
              style: const TextStyle(
                color: AppColors.brand700,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TermsScreen(),
                    ),
                  );
                },
            ),
            const TextSpan(text: ' et notre '),
            TextSpan(
              text: 'Politique de confidentialité',
              style: const TextStyle(
                color: AppColors.brand700,
                fontWeight: FontWeight.w600,
              ),
              recognizer: TapGestureRecognizer()
                ..onTap = () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyScreen(),
                    ),
                  );
                },
            ),
            const TextSpan(text: '.'),
          ],
        ),
      ),
    );
  }
}
