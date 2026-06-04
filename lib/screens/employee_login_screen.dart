import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../providers/auth_providers.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

/// Screen where an employee pastes the 8-char code ("XK3F-9B2M") the owner
/// gave them, and gets authenticated as that team member.
class EmployeeLoginScreen extends ConsumerStatefulWidget {
  const EmployeeLoginScreen({super.key});

  @override
  ConsumerState<EmployeeLoginScreen> createState() => _EmployeeLoginScreenState();
}

class _EmployeeLoginScreenState extends ConsumerState<EmployeeLoginScreen> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l = AppLocalizations.of(context);
    FocusScope.of(context).unfocus();
    final raw = _ctrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _error = l?.tr('emp_login_error_empty') ?? 'Entrez votre code');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final callable = FirebaseFunctions.instance.httpsCallable('exchangeEmployeeCodeForToken');
      final res = await callable.call<Map<String, dynamic>>({'code': raw});
      final data = res.data;
      final token = data['token'] as String?;
      final salonId = data['salonId'] as String?;
      final memberId = data['memberId'] as String?;
      if (token == null || salonId == null || memberId == null) {
        throw Exception('bad-response');
      }

      await FirebaseAuth.instance.signInWithCustomToken(token);
      // Force-refresh the ID token so the custom claims (employee,
      // salonId, memberId) are present on the next Firestore request.
      // Without this, the SDK can use a stale token and the
      // teamMembers update gets PERMISSION_DENIED.
      await FirebaseAuth.instance.currentUser?.getIdToken(true);

      // Drop every auth-derived provider so leftover owner-scoped listeners
      // (appointments/*/private/contact, ownerSalonProvider, etc.) stop
      // querying under the employee's auth — they don't have the owner
      // claim and would flood the logs with PERMISSION_DENIED until the
      // app is hot-restarted.
      //
      // IMPORTANT: do NOT invalidate `authStateProvider` here. The
      // FlutterFire `authStateChanges()` stream emits the new user
      // naturally after `signInWithCustomToken`; re-subscribing would
      // force the StreamProvider through `isLoading` → null before the
      // new user shows up, which would briefly make
      // `employeeSessionProvider` see `auth.value == null`, return null,
      // and trigger main.dart's orphan-auth branch (signOutAll → kicked
      // back to the LoginScreen).
      ref.invalidate(userModelProvider);
      ref.invalidate(userStreamProvider);
      ref.invalidate(employeeSessionProvider);
      invalidateOwnerScopedProviders(ref);

      // Pop FIRST so the screen disappears immediately — main.dart router
      // will detect the employee claim and route to the right screen.
      // The FCM token update runs fire-and-forget below; if it hangs or
      // fails (rule denial during the brief auth-propagation window), we
      // don't want to keep the login button spinning forever.
      if (!mounted) return;
      Navigator.of(context).popUntil((r) => r.isFirst);

      // Save FCM token for push notifications per employee — fire-and-forget.
      // Token write happens after navigation so a slow Firestore round-trip
      // doesn't block the route change.
      // ignore: unawaited_futures
      () async {
        try {
          final fcm = await FirebaseMessaging.instance.getToken();
          if (fcm != null) {
            await FirebaseFirestore.instance
                .collection('salons')
                .doc(salonId)
                .collection('teamMembers')
                .doc(memberId)
                .update({
              'fcmToken': fcm,
              'fcmTokenUpdatedAt': FieldValue.serverTimestamp(),
              'lastSeenAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (_) {
          // non-fatal — owner's app will refresh the token on next session
        }
      }();
    } on FirebaseFunctionsException catch (e) {
      setState(() {
        _loading = false;
        _error = _mapErr(l, e.code);
      });
    } catch (_) {
      setState(() {
        _loading = false;
        _error = l?.tr('emp_login_error_generic') ?? 'Code invalide, vérifiez et réessayez';
      });
    }
  }

  String _mapErr(AppLocalizations? l, String code) {
    switch (code) {
      case 'not-found':
        return l?.tr('emp_login_error_not_found') ?? 'Code invalide';
      case 'resource-exhausted':
        return l?.tr('emp_login_error_rate_limit') ?? 'Trop de tentatives, réessayez plus tard';
      case 'failed-precondition':
        return l?.tr('emp_login_error_disabled') ?? 'Ce compte est désactivé';
      default:
        return l?.tr('emp_login_error_generic') ?? 'Code invalide, vérifiez et réessayez';
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
        iconTheme: const IconThemeData(color: AppColors.brand950),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 24),
              Container(
                width: 80,
                height: 80,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.badge_outlined, size: 40, color: AppColors.brand600),
              ),
              const SizedBox(height: 24),
              Text(
                l?.tr('emp_login_title') ?? 'Connexion employé',
                textAlign: TextAlign.center,
                style: GoogleFonts.dmSans(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                l?.tr('emp_login_subtitle') ?? 'Entrez le code à 8 caractères que votre propriétaire vous a donné.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color: AppColors.secondary500,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textAlign: TextAlign.center,
                style: GoogleFonts.robotoMono(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: AppColors.brand950,
                  letterSpacing: 4,
                ),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(9), // 8 chars + dash
                  _CodeFormatter(),
                ],
                decoration: InputDecoration(
                  hintText: 'XXXX-0000',
                  hintStyle: GoogleFonts.robotoMono(
                    color: AppColors.secondary300,
                    letterSpacing: 4,
                  ),
                  filled: true,
                  fillColor: AppColors.brand50,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.brand600, width: 2),
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 20),
                  errorText: _error,
                ),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : Text(
                          l?.tr('emp_login_submit') ?? 'Se connecter',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                l?.tr('emp_login_help') ?? 'Vous n\'avez pas de code ? Demandez-le à votre propriétaire depuis son interface.',
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.secondary400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Formats the code as "XXXX-0000" live as the user types.
class _CodeFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    var text = newValue.text.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    if (text.length > 8) text = text.substring(0, 8);
    final buf = StringBuffer();
    for (var i = 0; i < text.length; i++) {
      if (i == 4) buf.write('-');
      buf.write(text[i]);
    }
    final formatted = buf.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
