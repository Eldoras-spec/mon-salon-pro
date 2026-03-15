import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../services/app_localizations.dart';
import 'basic_registration_screen.dart';
import 'login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _controller = PageController();
  int _currentPage = 0;

  static const _pageIcons = [
    Icons.store_rounded,
    Icons.calendar_month_rounded,
    Icons.trending_up_rounded,
  ];

  static const _titleKeys = [
    'welcome_title_1',
    'welcome_title_2',
    'welcome_title_3',
  ];

  static const _descKeys = [
    'welcome_desc_1',
    'welcome_desc_2',
    'welcome_desc_3',
  ];

  static const _titleFallbacks = [
    'Votre salon, simplifie',
    'Agenda intelligent',
    'Suivez votre activite',
  ];

  static const _descFallbacks = [
    'Gerez vos rendez-vous, votre equipe et vos clients depuis une seule application.',
    'Vos clients reservent en ligne, vous recevez les demandes en temps reel et organisez votre planning facilement.',
    'Statistiques, finances, promotions — tout ce qu\'il faut pour developper votre salon.',
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_currentPage < _pageIcons.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _goToRegistration();
    }
  }

  void _goToRegistration() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const BasicRegistrationScreen(isClient: false),
      ),
    );
  }

  void _goToLogin() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 40),

            // Pages
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _pageIcons.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (_, i) => _buildPage(
                  icon: _pageIcons[i],
                  title: l?.tr(_titleKeys[i]) ?? _titleFallbacks[i],
                  subtitle: l?.tr(_descKeys[i]) ?? _descFallbacks[i],
                ),
              ),
            ),

            // Dots
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                _pageIcons.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _currentPage == i ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _currentPage == i
                        ? AppColors.brand600
                        : AppColors.secondary200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  CustomButton(
                    text: _currentPage < _pageIcons.length - 1
                        ? (l?.tr('welcome_next') ?? 'Suivant')
                        : (l?.tr('welcome_create_salon') ?? 'Cr\u00e9er mon salon'),
                    onPressed: _next,
                    icon: _currentPage < _pageIcons.length - 1
                        ? Icons.arrow_forward_rounded
                        : Icons.rocket_launch_rounded,
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          l?.tr('welcome_already_account') ?? 'D\u00e9j\u00e0 un compte ?',
                          style: GoogleFonts.plusJakartaSans(
                            color: AppColors.secondary500,
                            fontSize: 14,
                          ),
                        ),
                        TextButton(
                          onPressed: _goToLogin,
                          child: Text(
                            l?.tr('welcome_login') ?? 'Se connecter',
                            style: GoogleFonts.plusJakartaSans(
                              color: AppColors.brand700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildPage({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.brand50,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.brand200.withValues(alpha: 0.5),
                  blurRadius: 30,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: Icon(icon, size: 48, color: AppColors.brand600),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: AppColors.secondary500,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}
