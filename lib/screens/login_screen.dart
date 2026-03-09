import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import '../models/user_model.dart';
import '../widgets/custom_button.dart';
import '../widgets/custom_text_field.dart';
import '../providers/auth_providers.dart';
import 'basic_registration_screen.dart';
import 'forgot_password_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    _loadSavedEmail();
  }

  @override
  void dispose() {
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
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Ce compte est un compte client. Veuillez utiliser l\'application Mon Salon.'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }

        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) {
        String message = 'Une erreur est survenue';
        final errorString = e.toString().toLowerCase();

        if (errorString.contains('user-not-found') ||
            errorString.contains('wrong-password') ||
            errorString.contains('invalid-credential')) {
          message = 'Email ou mot de passe incorrect';
        } else if (errorString.contains('network-request-failed')) {
          message = 'Erreur réseau, vérifiez votre connexion';
        } else if (errorString.contains('too-many-requests')) {
          message = 'Trop de tentatives, réessayez plus tard';
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
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo mark
                    Center(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Image.asset(
                          'assets/icone.png',
                          width: 60,
                          height: 60,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Heading
                    Text(
                      'Mon Salon Pro',
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
                      'Connectez-vous pour gérer votre salon.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        color: AppColors.secondary500,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Email
                    CustomTextField(
                      label: 'Email',
                      hintText: 'karim@exemple.com',
                      controller: _emailController,
                      icon: Icons.email_outlined,
                      keyboardType: TextInputType.emailAddress,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre email';
                        }
                        if (!value.contains('@')) {
                          return 'Veuillez entrer un email valide';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // Password
                    CustomTextField(
                      label: 'Mot de passe',
                      hintText: '••••••••••••',
                      controller: _passwordController,
                      isPassword: true,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Veuillez entrer votre mot de passe';
                        }
                        if (value.length < 6) {
                          return 'Le mot de passe doit faire au moins 6 caractères';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),

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
                                      ? AppColors.brand600
                                      : Colors.white,
                                  border: Border.all(
                                    color: _rememberMe
                                        ? AppColors.brand600
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
                                'Se souvenir de moi',
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
                            'Mot de passe oublié ?',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: AppColors.brand700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // CTA
                    CustomButton(
                      text: 'Se connecter',
                      onPressed: _handleLogin,
                      isLoading: _isLoading,
                      icon: Icons.arrow_forward_rounded,
                    ),
                    const SizedBox(height: 20),

                    // Create account link
                    Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Pas encore de compte ?',
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
                              'Créer un compte',
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

                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
