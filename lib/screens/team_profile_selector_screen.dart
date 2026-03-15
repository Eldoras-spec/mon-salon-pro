import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/team_member_model.dart';
import '../models/user_model.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

class TeamProfileSelectorScreen extends ConsumerWidget {
  const TeamProfileSelectorScreen({super.key, required this.userModel});
  final UserModel userModel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final teamAsync = ref.watch(ownerTeamProvider);
    final hasPinSet = userModel.pinHash != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 48),
              Text(
                l?.tr('selector_title') ?? 'Qui êtes-vous ?',
                style: GoogleFonts.dmSans(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l?.tr('selector_subtitle') ?? 'Sélectionnez votre profil pour continuer',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 48),

              // Owner tile — PIN requis si défini
              _OwnerTile(
                userModel: userModel,
                onEnter: () {
                  ref.read(activeTeamMemberProvider.notifier).state = null;
                  ref.read(profileSelectedProvider.notifier).state = true;
                },
              ),
              const SizedBox(height: 16),

              // Team member tiles
              teamAsync.when(
                loading: () => const CircularProgressIndicator(
                    color: AppColors.brand500),
                error: (_, _) => const SizedBox.shrink(),
                data: (members) => members.isEmpty
                    ? const SizedBox.shrink()
                    : Column(
                        children: members
                            .map((m) => Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: _MemberTile(member: m),
                                ))
                            .toList(),
                      ),
              ),

              const Spacer(),

              // Skip button — masqué si le propriétaire a un PIN
              if (!hasPinSet)
                TextButton(
                  onPressed: () {
                    ref.read(activeTeamMemberProvider.notifier).state = null;
                    ref.read(profileSelectedProvider.notifier).state = true;
                  },
                  child: Text(
                    l?.tr('selector_continue_owner') ?? 'Continuer en tant que propriétaire',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Owner Tile ───────────────────────────────────────────────────────────────

class _OwnerTile extends ConsumerWidget {
  const _OwnerTile({required this.userModel, required this.onEnter});
  final UserModel userModel;
  final VoidCallback onEnter;

  String get _initials {
    final parts = userModel.fullName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return userModel.fullName.isNotEmpty
        ? userModel.fullName[0].toUpperCase()
        : 'P';
  }

  void _onTap(BuildContext context) {
    if (userModel.pinHash != null) {
      showDialog(
        context: context,
        builder: (ctx) => _PinDialog(
          memberName: userModel.fullName,
          expectedHash: userModel.pinHash!,
          isOwner: true,
          userId: userModel.id,
          onSuccess: () {
            Navigator.pop(ctx);
            onEnter();
          },
        ),
      );
    } else {
      onEnter();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    final hasPinSet = userModel.pinHash != null;
    return GestureDetector(
      onTap: () => _onTap(context),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2333),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: AppColors.brand600.withValues(alpha: 0.5), width: 1.5),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.brand500, AppColors.brand700],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  _initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    userModel.fullName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.brand600.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      l?.tr('selector_owner') ?? 'Propriétaire',
                      style: const TextStyle(
                        color: AppColors.brand400,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            hasPinSet
                ? Icon(Icons.lock_outline_rounded,
                    color: AppColors.brand400.withValues(alpha: 0.8), size: 18)
                : const Icon(Icons.arrow_forward_ios_rounded,
                    color: AppColors.brand400, size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── Member Tile ──────────────────────────────────────────────────────────────

class _MemberTile extends ConsumerWidget {
  const _MemberTile({required this.member});
  final TeamMemberModel member;

  String get _initials {
    final parts = member.name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
  }

  Color get _avatarColor =>
      member.role == 'gerant' ? const Color(0xFFEA580C) : AppColors.brand600;

  Color get _avatarBg => member.role == 'gerant'
      ? const Color(0xFFFFF7ED).withValues(alpha: 0.15)
      : AppColors.brand50.withValues(alpha: 0.15);

  String _roleLabel(BuildContext context) {
    final l = AppLocalizations.of(context);
    return member.role == 'gerant'
        ? (l?.tr('selector_manager') ?? 'Gérant(e)')
        : (l?.tr('selector_employee') ?? 'Employé(e)');
  }

  void _showPinDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => _PinDialog(
        memberName: member.name,
        expectedHash: member.pinHash,
        onSuccess: () {
          Navigator.pop(ctx);
          ref.read(activeTeamMemberProvider.notifier).state = member;
          ref.read(profileSelectedProvider.notifier).state = true;
        },
      ),
    );
  }

  void _enterDirectly(WidgetRef ref) {
    ref.read(activeTeamMemberProvider.notifier).state = member;
    ref.read(profileSelectedProvider.notifier).state = true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requiresPin = member.role == 'gerant';
    return GestureDetector(
      onTap: requiresPin
          ? () => _showPinDialog(context, ref)
          : () => _enterDirectly(ref),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: const Color(0xFF1C2333),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
              color: Colors.white.withValues(alpha: 0.08), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: _avatarBg,
                shape: BoxShape.circle,
                border: Border.all(
                    color: _avatarColor.withValues(alpha: 0.4), width: 1.5),
              ),
              child: Center(
                child: Text(
                  _initials,
                  style: TextStyle(
                    color: _avatarColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    member.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _roleLabel(context),
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            requiresPin
                ? Icon(Icons.lock_outline_rounded,
                    color: Colors.white.withValues(alpha: 0.3), size: 18)
                : Icon(Icons.arrow_forward_ios_rounded,
                    color: Colors.white.withValues(alpha: 0.3), size: 16),
          ],
        ),
      ),
    );
  }
}

// ─── PIN Dialog ───────────────────────────────────────────────────────────────

class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.memberName,
    required this.expectedHash,
    required this.onSuccess,
    this.isOwner = false,
    this.userId,
  });
  final String memberName;
  final String expectedHash;
  final VoidCallback onSuccess;
  final bool isOwner;
  final String? userId;

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog>
    with SingleTickerProviderStateMixin {
  final _pinCtrl = TextEditingController();
  bool _wrong = false;
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _shakeAnim = Tween<double>(begin: 0, end: 10).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticIn),
    );
  }

  @override
  void dispose() {
    _pinCtrl.dispose();
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _verify() {
    final entered = hashPin(_pinCtrl.text.trim());
    if (entered == widget.expectedHash) {
      widget.onSuccess();
    } else {
      setState(() => _wrong = true);
      _pinCtrl.clear();
      _shakeCtrl.forward(from: 0);
    }
  }

  void _showForgotPin() {
    final l = AppLocalizations.of(context);
    final emailCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) {
        bool loading = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Column(
              children: [
                const Icon(Icons.lock_reset_rounded, color: AppColors.brand600, size: 32),
                const SizedBox(height: 8),
                Text(
                  l?.tr('selector_forgot_pin_title') ?? 'PIN oublié ?',
                  style: GoogleFonts.dmSans(fontWeight: FontWeight.bold, color: AppColors.brand950, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  l?.tr('selector_forgot_pin_subtitle') ?? 'Connectez-vous avec votre email et mot de passe pour supprimer le PIN.',
                  style: const TextStyle(fontSize: 12, color: AppColors.secondary500, fontWeight: FontWeight.normal),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l?.tr('login_email_label') ?? 'Email',
                    filled: true,
                    fillColor: AppColors.secondary50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.secondary200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand500, width: 1.5)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l?.tr('login_password_label') ?? 'Mot de passe',
                    filled: true,
                    fillColor: AppColors.secondary50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.secondary200)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand500, width: 1.5)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l?.tr('selector_cancel') ?? 'Annuler', style: const TextStyle(color: AppColors.secondary500)),
              ),
              ElevatedButton(
                onPressed: loading ? null : () async {
                  setDialogState(() => loading = true);
                  try {
                    final user = FirebaseAuth.instance.currentUser;
                    if (user == null || user.email == null) throw Exception('No user');

                    final credential = EmailAuthProvider.credential(
                      email: emailCtrl.text.trim(),
                      password: passwordCtrl.text.trim(),
                    );
                    await user.reauthenticateWithCredential(credential);

                    // Re-auth successful — remove PIN
                    await FirebaseFirestore.instance
                        .collection('users')
                        .doc(widget.userId)
                        .update({'pinHash': FieldValue.delete()});

                    if (ctx.mounted) Navigator.pop(ctx); // close forgot dialog
                    // onSuccess will pop the PIN dialog and call onEnter()
                    widget.onSuccess();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(l?.tr('selector_pin_removed') ?? 'PIN supprimé. Vous pouvez en définir un nouveau depuis votre profil.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } on FirebaseAuthException catch (e) {
                    setDialogState(() => loading = false);
                    final msg = e.code == 'wrong-password' || e.code == 'invalid-credential'
                        ? (l?.tr('selector_wrong_credentials') ?? 'Email ou mot de passe incorrect')
                        : (l?.tr('common_error_short') ?? 'Erreur');
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text(msg), backgroundColor: Colors.red),
                      );
                    }
                  } catch (e) {
                    setDialogState(() => loading = false);
                    if (ctx.mounted) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        SnackBar(content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand700,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: loading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(l?.tr('selector_confirm') ?? 'Confirmer'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Column(
        children: [
          const Icon(Icons.lock_outline_rounded,
              color: AppColors.brand600, size: 32),
          const SizedBox(height: 8),
          Text(
            widget.memberName,
            style: GoogleFonts.dmSans(
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
              fontSize: 18,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('selector_enter_pin') ?? 'Entrez votre PIN à 6 chiffres',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.secondary500,
              fontWeight: FontWeight.normal,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _shakeAnim,
            builder: (ctx, child) => Transform.translate(
              offset: Offset(
                  _shakeAnim.value * (_shakeCtrl.value < 0.5 ? 1 : -1), 0),
              child: child,
            ),
            child: TextField(
              controller: _pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _verify(),
              decoration: InputDecoration(
                counterText: '',
                hintText: '••••••',
                hintStyle: const TextStyle(
                    color: AppColors.secondary300, letterSpacing: 8),
                errorText: _wrong ? (l?.tr('selector_pin_incorrect') ?? 'PIN incorrect') : null,
                filled: true,
                fillColor: AppColors.secondary50,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.secondary200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: _wrong
                        ? const Color(0xFFDC2626)
                        : AppColors.secondary200,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.brand500, width: 1.5),
                ),
              ),
            ),
          ),
          if (widget.isOwner) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: _showForgotPin,
                child: Text(
                  l?.tr('selector_forgot_pin') ?? 'PIN oublié ?',
                  style: const TextStyle(
                    color: AppColors.brand500,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l?.tr('selector_cancel') ?? 'Annuler',
              style: const TextStyle(color: AppColors.secondary500)),
        ),
        ElevatedButton(
          onPressed: _verify,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand700,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(l?.tr('selector_enter') ?? 'Entrer'),
        ),
      ],
    );
  }
}
