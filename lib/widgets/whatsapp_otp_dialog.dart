import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_colors.dart';

/// Result returned by [WhatsappOtpDialog.show] when the user successfully
/// validates a code. The caller has the proven WhatsApp number and can
/// proceed with linking it to the user doc.
class WhatsappOtpResult {
  WhatsappOtpResult({required this.whatsapp});
  final String whatsapp;
}

/// Blocking dialog that handles the WhatsApp OTP flow:
/// - Sends a code via the `requestWhatsappOtp` Cloud Function on mount.
/// - User types the 6-digit code received on WhatsApp.
/// - Validates via `verifyWhatsappOtp` Cloud Function.
/// - Returns [WhatsappOtpResult] on success, null on cancel/exhaustion.
///
/// Pass [salonId] when triggering an OTP for a walk-in booking — the CF
/// short-circuits and returns `sent: false` for non-Business salons. In
/// that case [show] resolves with a result of "skipped" handled by the
/// caller (we throw a special error to let the caller distinguish).
class WhatsappOtpDialog extends StatefulWidget {
  const WhatsappOtpDialog._({
    required this.whatsapp,
    this.salonId,
    this.claim = false,
  });
  final String whatsapp;
  final String? salonId;

  /// When true, the verify step calls `claimWhatsappOwnership` instead
  /// of `verifyWhatsappOtp`. The CF atomically verifies the OTP,
  /// releases the WA from any other user doc, re-keys walk-in
  /// appointments, and writes the WA on the caller's user doc.
  /// Requires the user to be authenticated.
  final bool claim;

  static Future<WhatsappOtpResult?> show(
    BuildContext context,
    String whatsapp, {
    String? salonId,
  }) {
    return showDialog<WhatsappOtpResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) =>
          WhatsappOtpDialog._(whatsapp: whatsapp, salonId: salonId),
    );
  }

  /// Authenticated claim flow used by profile edit. The CF persists
  /// the WA on the caller's user doc atomically — caller does not
  /// need to write `whatsapp` itself.
  static Future<WhatsappOtpResult?> showForClaim(
    BuildContext context,
    String whatsapp,
  ) {
    return showDialog<WhatsappOtpResult>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) =>
          WhatsappOtpDialog._(whatsapp: whatsapp, claim: true),
    );
  }

  @override
  State<WhatsappOtpDialog> createState() => _WhatsappOtpDialogState();
}

class _WhatsappOtpDialogState extends State<WhatsappOtpDialog> {
  static const int _resendCooldown = 60;
  static const int _maxAttempts = 5;

  final _inputControllers = List.generate(6, (_) => TextEditingController());
  final _inputFocusNodes = List.generate(6, (_) => FocusNode());

  bool _sending = true;
  bool _verifying = false;
  String? _errorText;
  int _attempts = 0;
  int _resendTimer = _resendCooldown;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _sendCode();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    for (final c in _inputControllers) {
      c.dispose();
    }
    for (final f in _inputFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!mounted) return;
    setState(() {
      _sending = true;
      _errorText = null;
    });

    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('requestWhatsappOtp')
          .call({
        'whatsapp': widget.whatsapp,
        if (widget.salonId != null) 'salonId': widget.salonId,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      if (data['sent'] == false) {
        // Walk-in path on a non-Business salon — caller signaled to skip
        // OTP. Close with a synthetic OK result so caller treats this as
        // "verified without OTP" (the WA number is collected as-is).
        if (!mounted) return;
        Navigator.of(context).pop(
          WhatsappOtpResult(whatsapp: widget.whatsapp),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _sending = false;
      });
      _startCooldown();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _inputFocusNodes[0].requestFocus();
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.message ?? 'Erreur lors de l\'envoi du code WhatsApp.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorText =
            'Impossible d\'envoyer le code WhatsApp. Réessayez plus tard.';
      });
    }
  }

  void _startCooldown() {
    _ticker?.cancel();
    setState(() => _resendTimer = _resendCooldown);
    _ticker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendTimer--;
        if (_resendTimer <= 0) t.cancel();
      });
    });
  }

  String _code() => _inputControllers.map((c) => c.text).join();

  Future<void> _verify() async {
    final code = _code();
    if (code.length != 6) return;

    setState(() {
      _verifying = true;
      _errorText = null;
    });

    try {
      final endpoint = widget.claim
          ? 'claimWhatsappOwnership'
          : 'verifyWhatsappOtp';
      final res = await FirebaseFunctions.instance
          .httpsCallable(endpoint)
          .call({
        'whatsapp': widget.whatsapp,
        'code': code,
      });
      final data = res.data is Map ? Map<String, dynamic>.from(res.data) : {};
      if (data['ok'] == true) {
        if (!mounted) return;
        Navigator.of(context).pop(
          WhatsappOtpResult(whatsapp: widget.whatsapp),
        );
      } else {
        setState(() {
          _verifying = false;
          _errorText = 'Réponse inattendue. Réessayez.';
        });
      }
    } on FirebaseFunctionsException catch (e) {
      _attempts++;
      if (!mounted) return;
      if (_attempts >= _maxAttempts) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trop de tentatives échouées.'),
            backgroundColor: Colors.redAccent,
          ),
        );
        return;
      }
      setState(() {
        _verifying = false;
        _errorText = e.message ?? 'Code incorrect.';
      });
      // Clear the inputs so the user can re-enter cleanly.
      for (final c in _inputControllers) {
        c.clear();
      }
      _inputFocusNodes[0].requestFocus();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _verifying = false;
        _errorText = 'Erreur: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canResend = !_sending && _resendTimer <= 0;
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFE7F8EE),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline,
                color: Color(0xFF25D366),
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Vérification WhatsApp',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Entrez le code à 6 chiffres envoyé à\n${widget.whatsapp}',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.secondary500,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (_sending)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (i) {
                  return SizedBox(
                    width: 44,
                    child: TextField(
                      controller: _inputControllers[i],
                      focusNode: _inputFocusNodes[i],
                      enabled: !_verifying,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(1),
                      ],
                      style: const TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w600),
                      decoration: InputDecoration(
                        counterText: '',
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: _errorText != null
                                  ? Colors.redAccent
                                  : AppColors.secondary200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(
                              color: _errorText != null
                                  ? Colors.redAccent
                                  : AppColors.secondary200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                              color: AppColors.brand500, width: 2),
                        ),
                      ),
                      onChanged: (v) {
                        if (v.isNotEmpty && i < 5) {
                          _inputFocusNodes[i + 1].requestFocus();
                        } else if (v.isEmpty && i > 0) {
                          _inputFocusNodes[i - 1].requestFocus();
                        }
                        if (i == 5 && v.isNotEmpty && _code().length == 6) {
                          _verify();
                        }
                      },
                    ),
                  );
                }),
              ),
            if (_errorText != null) ...[
              const SizedBox(height: 12),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 16),
            TextButton(
              onPressed: canResend ? () => _sendCode(resend: true) : null,
              child: Text(
                canResend
                    ? 'Renvoyer le code'
                    : 'Renvoyer dans ${_resendTimer}s',
                style: TextStyle(
                  color: canResend
                      ? AppColors.brand600
                      : AppColors.secondary400,
                  fontSize: 13,
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _verifying
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Annuler',
                  style: TextStyle(color: AppColors.secondary500)),
            ),
          ],
        ),
      ),
    );
  }
}
