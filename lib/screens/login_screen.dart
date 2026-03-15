import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../models/user_model.dart';
import '../widgets/custom_text_field.dart';
import '../providers/auth_providers.dart';
import '../services/app_localizations.dart';
import 'basic_registration_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _rememberMe = false;

  late AnimationController _animController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnim = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOut,
    ));
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedEmail() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_role_switch');

      final savedEmail = prefs.getString('remembered_email');
      if (savedEmail != null && mounted) {
        setState(() {
          _emailController.text = savedEmail;
          _rememberMe = true;
        });
      }
    } catch (e) {
      debugPrint('Error loading saved email: $e');
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final authService = ref.read(authServiceProvider);

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString('remembered_email', _emailController.text.trim());
      } else {
        await prefs.remove('remembered_email');
      }

      final credential = await authService.signInWithEmail(
        _emailController.text.trim(),
        _passwordController.text,
      );

      if (credential != null && credential.user != null) {
        final userModel = await authService.getUserModel(credential.user!.uid);

        // Block client accounts from logging into the Pro app
        if (userModel != null && userModel.userType == UserType.client) {
          await authService.signOut();
          if (mounted) {
            final l = AppLocalizations.of(context);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l?.tr('login_client_account_error') ?? 'Ce compte est un compte client. Veuillez utiliser l\'application Mon Salon pour vous connecter.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        // Auth state changed → main.dart will rebuild via authStateProvider.
        // Pop this screen if it was pushed (e.g. from WelcomeScreen).
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        String message = l?.tr('login_error_generic') ?? 'Une erreur est survenue';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('user-not-found') ||
            errorString.contains('wrong-password') ||
            errorString.contains('invalid-credential')) {
          message = l?.tr('login_error_wrong_credentials') ?? 'Email ou mot de passe incorrect';
        } else if (errorString.contains('network-request-failed')) {
          message = l?.tr('login_error_network') ?? 'Erreur réseau, vérifiez votre connexion';
        } else if (errorString.contains('too-many-requests')) {
          message = l?.tr('login_error_too_many_attempts') ?? 'Trop de tentatives, réessayez plus tard';
        } else {
          message = e.toString();
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _handleForgotPassword() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ForgotPasswordScreen(
          initialEmail: _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFF3E8FF), // light purple
              Colors.white,
              Colors.white,
            ],
            stops: [0.0, 0.4, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: FadeTransition(
                opacity: _fadeAnim,
                child: SlideTransition(
                  position: _slideAnim,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo
                        Center(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: Image.asset(
                              'assets/icone.png',
                              width: 72,
                              height: 72,
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // Heading
                        Text(
                          l?.tr('login_title') ?? 'Mon Salon Pro',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.dmSans(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: AppColors.brand950,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l?.tr('login_subtitle') ?? 'Connectez-vous pour gérer votre salon.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14,
                            color: AppColors.secondary500,
                            height: 1.5,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Form card
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.secondary100,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withValues(alpha: 0.06),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // Email
                                CustomTextField(
                                  label: l?.tr('login_email_label') ?? 'Email',
                                  hintText: l?.tr('login_email_hint') ?? 'karim@exemple.com',
                                  controller: _emailController,
                                  icon: Icons.email_outlined,
                                  keyboardType: TextInputType.emailAddress,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l?.tr('login_email_required') ?? 'Veuillez entrer votre email';
                                    }
                                    if (!value.contains('@')) {
                                      return l?.tr('login_email_invalid') ?? 'Veuillez entrer un email valide';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 16),

                                // Password
                                CustomTextField(
                                  label: l?.tr('login_password_label') ?? 'Mot de passe',
                                  hintText: l?.tr('login_password_hint') ?? '••••••••••••',
                                  controller: _passwordController,
                                  isPassword: true,
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return l?.tr('login_password_required') ?? 'Veuillez entrer votre mot de passe';
                                    }
                                    if (value.length < 6) {
                                      return l?.tr('login_password_min_length') ?? 'Le mot de passe doit faire au moins 6 caractères';
                                    }
                                    return null;
                                  },
                                ),
                                const SizedBox(height: 14),

                                // Remember & Forgot Password
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    GestureDetector(
                                      onTap: () =>
                                          setState(() => _rememberMe = !_rememberMe),
                                      child: Row(
                                        children: [
                                          AnimatedContainer(
                                            duration: const Duration(milliseconds: 200),
                                            width: 20,
                                            height: 20,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(5),
                                              color: _rememberMe
                                                  ? const Color(0xFF7C3AED)
                                                  : Colors.white,
                                              border: Border.all(
                                                color: _rememberMe
                                                    ? const Color(0xFF7C3AED)
                                                    : AppColors.secondary300,
                                                width: 2,
                                              ),
                                            ),
                                            child: _rememberMe
                                                ? const Icon(
                                                    Icons.check_rounded,
                                                    color: Colors.white,
                                                    size: 13,
                                                  )
                                                : null,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            l?.tr('login_remember_me') ?? 'Se souvenir de moi',
                                            style: GoogleFonts.plusJakartaSans(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.secondary600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      onPressed: _handleForgotPassword,
                                      style: TextButton.styleFrom(padding: EdgeInsets.zero),
                                      child: Text(
                                        l?.tr('login_forgot_password') ?? 'Mot de passe oublié ?',
                                        style: GoogleFonts.plusJakartaSans(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: const Color(0xFF7C3AED),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 28),

                        // CTA
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                                blurRadius: 15,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        l?.tr('login_button') ?? 'Se connecter',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(Icons.arrow_forward_rounded, size: 18, color: Colors.white),
                                    ],
                                  ),
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Create account link
                        Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                l?.tr('login_no_account') ?? 'Pas encore de compte ?',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.secondary500,
                                  fontSize: 14,
                                ),
                              ),
                              TextButton(
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          const BasicRegistrationScreen(isClient: false),
                                    ),
                                  );
                                },
                                child: Text(
                                  l?.tr('login_create_account') ?? 'Créer un compte',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: const Color(0xFF7C3AED),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
