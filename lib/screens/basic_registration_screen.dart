import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../providers/auth_providers.dart';
import '../services/app_localizations.dart';
import 'owner_onboarding_step1_screen.dart';
import 'terms_screen.dart';
import 'privacy_policy_screen.dart';

class BasicRegistrationScreen extends ConsumerStatefulWidget {
  final bool isClient;
  const BasicRegistrationScreen({super.key, required this.isClient});

  @override
  ConsumerState<BasicRegistrationScreen> createState() =>
      _BasicRegistrationScreenState();
}

class _BasicRegistrationScreenState
    extends ConsumerState<BasicRegistrationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _acceptTerms = false;
  int _passwordStrength = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _passwordController.addListener(_updatePasswordStrength);
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _updatePasswordStrength() {
    final pass = _passwordController.text;
    int strength = 0;
    if (pass.isNotEmpty) strength = 1;
    if (pass.length > 4) strength = 2;
    if (pass.length > 8) strength = 3;
    if (pass.length > 10 &&
        pass.contains(RegExp(r'[A-Z]')) &&
        pass.contains(RegExp(r'[0-9]'))) {
      strength = 4;
    }
    setState(() => _passwordStrength = strength);
  }

  // ── Device-level rate limiting ─────────────────────────────
  static const _maxAccountsPerDevice = 2;
  static const _cooldownSeconds = 60;

  Future<String?> _checkDeviceLimit() async {
    final prefs = await SharedPreferences.getInstance();
    final l = AppLocalizations.of(context);

    // Check cooldown (60s between attempts)
    final lastAttempt = prefs.getInt('reg_last_attempt') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - lastAttempt < _cooldownSeconds * 1000) {
      final remaining = _cooldownSeconds - ((now - lastAttempt) ~/ 1000);
      return (l?.tr('register_cooldown') ?? 'Veuillez patienter {remaining}s avant de r\u00e9essayer.').replaceAll('{remaining}', '$remaining');
    }

    // Check max accounts per device
    final count = prefs.getInt('reg_device_count') ?? 0;
    if (count >= _maxAccountsPerDevice) {
      return l?.tr('register_device_limit') ?? 'Limite de cr\u00e9ation de compte atteinte sur cet appareil.';
    }

    return null; // OK
  }

  Future<void> _incrementDeviceCount() async {
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt('reg_device_count') ?? 0;
    await prefs.setInt('reg_device_count', count + 1);
    await prefs.setInt('reg_last_attempt', DateTime.now().millisecondsSinceEpoch);
  }

  Future<void> _handleRegistration() async {
    final l = AppLocalizations.of(context);
    if (!_formKey.currentState!.validate()) return;
    if (!_acceptTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l?.tr('register_accept_terms') ?? 'Veuillez accepter les conditions')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // If the user already exists (came back from onboarding to edit),
      // skip re-registration and navigate forward directly.
      final existingUserId = ref.read(authServiceProvider).currentUserId;
      if (existingUserId != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const OwnerOnboardingStep1Screen(),
            ),
          );
        }
        return;
      }

      // Device-level rate limit check
      final limitError = await _checkDeviceLimit();
      if (limitError != null) {
        if (mounted) {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(limitError), backgroundColor: Colors.redAccent),
          );
        }
        return;
      }

      await ref.read(authServiceProvider).registerWithEmail(
            email: _emailController.text.trim(),
            password: _passwordController.text,
            fullName:
                '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}',
            phone: '',
            city: '',
            isClient: false,
          );

      // Registration succeeded — increment device counter
      await _incrementDeviceCount();

      if (mounted) {
        setState(() => _isLoading = false);
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const OwnerOnboardingStep1Screen(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        String message = l?.tr('register_error_generic') ?? 'Une erreur est survenue';
        final errorString = e.toString().toLowerCase();
        if (errorString.contains('email-already-in-use')) {
          message = l?.tr('register_error_email_in_use') ?? 'Cet email est d\u00e9j\u00e0 utilis\u00e9';
        } else if (errorString.contains('weak-password')) {
          message = l?.tr('register_error_weak_password') ?? 'Le mot de passe est trop faible';
        } else if (errorString.contains('invalid-email')) {
          message = l?.tr('register_error_invalid_email') ?? 'Email invalide';
        } else if (errorString.contains('network-request-failed')) {
          message = l?.tr('register_error_network') ?? 'Erreur r\u00e9seau, v\u00e9rifiez votre connexion';
        } else if (errorString.contains('blocking-function-error-response') ||
                   errorString.contains('resource-exhausted') ||
                   errorString.contains('permission-denied')) {
          message = l?.tr('register_error_rate_limit') ?? 'Trop de comptes cr\u00e9\u00e9s. R\u00e9essayez plus tard.';
        } else {
          message = e.toString();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 28),
                      _buildHeader(l),
                      const SizedBox(height: 32),

                      // ── Section : Informations personnelles
                      _buildSectionLabel(l?.tr('register_section_personal') ?? 'Informations personnelles'),
                      const SizedBox(height: 14),

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: CustomTextField(
                              label: l?.tr('register_first_name') ?? 'Pr\u00e9nom',
                              hintText: l?.tr('register_first_name_hint') ?? 'Karim',
                              controller: _firstNameController,
                              validator: (v) => v == null || v.isEmpty
                                  ? (l?.tr('register_first_name_required') ?? 'Pr\u00e9nom requis')
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: CustomTextField(
                              label: l?.tr('register_last_name') ?? 'Nom',
                              hintText: l?.tr('register_last_name_hint') ?? 'Benali',
                              controller: _lastNameController,
                              validator: (v) => v == null || v.isEmpty
                                  ? (l?.tr('register_last_name_required') ?? 'Nom requis')
                                  : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: l?.tr('register_email_label') ?? 'Adresse email',
                        hintText: l?.tr('register_email_hint') ?? 'karim@exemple.com',
                        icon: Icons.email_outlined,
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        validator: (v) {
                          if (v == null || v.isEmpty) return l?.tr('register_email_required') ?? 'Email requis';
                          if (!v.contains('@')) return l?.tr('register_email_invalid') ?? 'Email invalide';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),

                      const SizedBox(height: 28),

                      // ── Section : Sécurité
                      _buildSectionLabel(l?.tr('register_section_security') ?? 'S\u00e9curit\u00e9'),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: l?.tr('register_password_label') ?? 'Mot de passe',
                        hintText: l?.tr('register_password_hint') ?? '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                        controller: _passwordController,
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return l?.tr('register_password_required') ?? 'Mot de passe requis';
                          }
                          if (v.length < 6) return l?.tr('register_password_min_length') ?? 'Min. 6 caract\u00e8res';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      _buildPasswordStrength(l),
                      const SizedBox(height: 14),

                      CustomTextField(
                        label: l?.tr('register_confirm_password_label') ?? 'Confirmer le mot de passe',
                        hintText: l?.tr('register_password_hint') ?? '\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022\u2022',
                        icon: Icons.lock_outline_rounded,
                        isPassword: true,
                        controller: _confirmPasswordController,
                        validator: (v) {
                          if (v != _passwordController.text) {
                            return l?.tr('register_confirm_password_mismatch') ?? 'Les mots de passe ne correspondent pas';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 24),

                      // Terms
                      _buildTermsRow(l),
                      const SizedBox(height: 28),

                      CustomButton(
                        text: l?.tr('register_continue') ?? 'Continuer',
                        onPressed: _handleRegistration,
                        isLoading: _isLoading,
                        icon: Icons.arrow_forward_rounded,
                      ),
                      const SizedBox(height: 24),

                      Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              l?.tr('register_already_account') ?? 'D\u00e9j\u00e0 un compte ?',
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.secondary500,
                                fontSize: 14,
                              ),
                            ),
                            TextButton(
                              onPressed: () => Navigator.popUntil(
                                context,
                                (route) => route.isFirst,
                              ),
                              child: Text(
                                l?.tr('register_login') ?? 'Se connecter',
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
              final active = i <= 1; // steps 1 and 2 done/active
              final current = i == 1;
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                width: current ? 20 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active ? AppColors.brand600 : AppColors.secondary200,
                  borderRadius: BorderRadius.circular(4),
                ),
              );
            }),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildHeader(AppLocalizations? l) {
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
            widget.isClient
                ? (l?.tr('register_step_client') ?? '\u00c9tape 2 sur 3')
                : (l?.tr('register_step_owner') ?? '\u00c9tape 1 sur 6'),
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
          widget.isClient
              ? (l?.tr('register_title_client') ?? 'Cr\u00e9ez votre compte')
              : (l?.tr('register_title_owner') ?? 'Votre profil'),
          style: GoogleFonts.dmSans(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          widget.isClient
              ? (l?.tr('register_subtitle_client') ?? 'Quelques informations et c\'est parti !')
              : (l?.tr('register_subtitle_owner') ?? 'Ces informations serviront \u00e0 configurer votre salon.'),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.secondary500,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Row(
      children: [
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.secondary400,
            letterSpacing: 0.4,
          ),
        ),
        const SizedBox(width: 10),
        const Expanded(child: Divider(color: AppColors.secondary100)),
      ],
    );
  }

  Widget _buildPasswordStrength(AppLocalizations? l) {
    final labels = [
      '',
      l?.tr('register_password_weak') ?? 'Faible',
      l?.tr('register_password_medium') ?? 'Moyen',
      l?.tr('register_password_strong') ?? 'Fort',
      l?.tr('register_password_excellent') ?? 'Excellent',
    ];
    final colors = [
      AppColors.secondary200,
      Colors.red.shade400,
      Colors.orange.shade400,
      AppColors.brand400,
      Colors.green.shade500,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: List.generate(4, (i) {
            final filled = i < _passwordStrength;
            return Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                height: 4,
                margin: EdgeInsets.only(right: i < 3 ? 5 : 0),
                decoration: BoxDecoration(
                  color: filled
                      ? colors[_passwordStrength]
                      : AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }),
        ),
        if (_passwordStrength > 0) ...[
          const SizedBox(height: 5),
          Text(
            labels[_passwordStrength],
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors[_passwordStrength],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTermsRow(AppLocalizations? l) {
    return GestureDetector(
      onTap: () => setState(() => _acceptTerms = !_acceptTerms),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              color: _acceptTerms ? AppColors.brand600 : Colors.white,
              border: Border.all(
                color: _acceptTerms
                    ? AppColors.brand600
                    : AppColors.secondary300,
                width: 2,
              ),
            ),
            child: _acceptTerms
                ? const Icon(Icons.check_rounded,
                    color: Colors.white, size: 14)
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.secondary500,
                  height: 1.5,
                ),
                children: [
                  TextSpan(text: l?.tr('register_terms_prefix') ?? 'J\'accepte les '),
                  TextSpan(
                    text: l?.tr('register_terms_link') ?? 'Conditions d\'utilisation',
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
                  TextSpan(text: l?.tr('register_terms_separator') ?? ' et la '),
                  TextSpan(
                    text: l?.tr('register_privacy_link') ?? 'Politique de confidentialit\u00e9',
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
          ),
        ],
      ),
    );
  }

}
