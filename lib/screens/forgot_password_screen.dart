import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme/app_colors.dart';
import '../providers/auth_providers.dart';
import '../services/app_localizations.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  final String initialEmail;

  const ForgotPasswordScreen({super.key, this.initialEmail = ''});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  bool _isLoading = false;
  bool _emailSent = false;

  @override
  void initState() {
    super.initState();
    _emailController = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _sendResetEmail() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      await ref
          .read(authServiceProvider)
          .sendPasswordResetEmail(_emailController.text.trim());
      if (mounted) {
        setState(() {
          _isLoading = false;
          _emailSent = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        final l = AppLocalizations.of(context);
        final errorString = e.toString().toLowerCase();
        String message = l?.tr('login_error_generic') ?? 'Une erreur est survenue';
        if (errorString.contains('user-not-found')) {
          message = 'Aucun compte trouv\u00e9 avec cet email';
        } else if (errorString.contains('network-request-failed')) {
          message = l?.tr('login_error_network') ?? 'Erreur r\u00e9seau, v\u00e9rifiez votre connexion';
        } else if (errorString.contains('too-many-requests')) {
          message = l?.tr('login_error_too_many_attempts') ?? 'Trop de tentatives, r\u00e9essayez plus tard';
        } else if (errorString.contains('invalid-email')) {
          message = l?.tr('login_email_invalid') ?? 'Adresse email invalide';
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
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.brand950),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: _emailSent ? _buildSuccessView(l) : _buildFormView(l),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFormView(AppLocalizations? l) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Icon
          Center(
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: AppColors.brand50,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.lock_reset_rounded,
                size: 36,
                color: AppColors.brand600,
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Title
          Text(
            l?.tr('forgot_title') ?? 'Mot de passe oubli\u00e9',
            textAlign: TextAlign.center,
            style: GoogleFonts.playfairDisplay(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 10),

          // Subtitle
          Text(
            l?.tr('forgot_subtitle') ?? 'Entrez votre adresse email pour recevoir un lien de r\u00e9initialisation.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 14,
              color: AppColors.secondary500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 32),

          // Email label
          Text(
            l?.tr('forgot_email_label') ?? 'Email',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary700,
            ),
          ),
          const SizedBox(height: 8),

          // Email field
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 15,
              color: AppColors.brand950,
            ),
            decoration: InputDecoration(
              hintText: l?.tr('forgot_email_hint') ?? 'votre@email.com',
              hintStyle: GoogleFonts.plusJakartaSans(
                color: AppColors.secondary400,
                fontSize: 15,
              ),
              suffixIcon: const Icon(
                Icons.mail_outline_rounded,
                color: AppColors.secondary400,
              ),
              filled: true,
              fillColor: AppColors.secondary50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.brand500, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return l?.tr('login_email_required') ?? 'Veuillez entrer votre email';
              }
              if (!value.contains('@') || !value.contains('.')) {
                return l?.tr('login_email_invalid') ?? 'Veuillez entrer un email valide';
              }
              return null;
            },
          ),
          const SizedBox(height: 28),

          // Send button
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendResetEmail,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand600,
                disabledBackgroundColor: AppColors.brand300,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      l?.tr('forgot_send_button') ?? 'Envoyer le lien',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 16),

          // Back to login
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                l?.tr('forgot_back_to_login') ?? 'Retour \u00e0 la connexion',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessView(AppLocalizations? l) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Success icon
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFD1FAE5),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Icon(
              Icons.mark_email_read_rounded,
              size: 36,
              color: Color(0xFF059669),
            ),
          ),
        ),
        const SizedBox(height: 24),

        // Title
        Text(
          l?.tr('forgot_success_title') ?? 'Email envoy\u00e9 !',
          textAlign: TextAlign.center,
          style: GoogleFonts.playfairDisplay(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
          ),
        ),
        const SizedBox(height: 10),

        // Instructions
        Text(
          l?.tr('forgot_success_message') ?? 'Un lien de r\u00e9initialisation a \u00e9t\u00e9 envoy\u00e9 \u00e0',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.secondary500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _emailController.text.trim(),
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppColors.brand700,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          l?.tr('forgot_check_inbox') ?? 'V\u00e9rifiez votre bo\u00eete de r\u00e9ception et vos spams.',
          textAlign: TextAlign.center,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 14,
            color: AppColors.secondary500,
            height: 1.5,
          ),
        ),
        const SizedBox(height: 32),

        // Back to login button
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: Text(
              l?.tr('forgot_back_to_login') ?? 'Retour \u00e0 la connexion',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Resend
        Center(
          child: TextButton(
            onPressed: _isLoading
                ? null
                : () {
                    setState(() => _emailSent = false);
                  },
            child: Text(
              l?.tr('forgot_resend') ?? 'Renvoyer l\'email',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.brand600,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
