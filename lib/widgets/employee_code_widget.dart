import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_localizations.dart';
import '../theme/app_colors.dart';

/// Localized fallback message used when the owner copies / shares the code
/// manually (e.g. n8n was down). The auto-send path uses the i18n message
/// stored on the Cloud Functions side. `{code}` is replaced with the code.
String employeeCodeShareMessage(BuildContext context, String code) {
  final l = AppLocalizations.of(context);
  return (l?.tr('emp_code_share_message') ??
          'Voici votre code pour vous connecter à Mon Salon Pro en tant qu\'employé :\n\n{code}\n\nOuvrez l\'application, choisissez "Je suis un employé" et entrez ce code.')
      .replaceAll('{code}', code);
}

/// Bottom sheet that shows the employee login code. The code is auto-sent
/// to the employee's WhatsApp by the Cloud Function (`generateEmployeeLoginCode`)
/// via the n8n WhatsApp server — the owner doesn't need to do anything else.
///
/// Copy / Share / Regenerate buttons remain as fallback if the auto-send
/// fails (n8n down, invalid number, etc.).
///
/// [code] is the current code stored in `teamMembers/{memberId}.loginCode`.
/// If null, a code will be generated on open.
/// [employeeWhatsapp] is the E.164 WhatsApp number the CF will send to.
Future<void> showEmployeeCodeSheet({
  required BuildContext context,
  required String salonId,
  required String memberId,
  required String memberName,
  String? initialCode,
  String? employeeWhatsapp,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => _EmployeeCodeSheet(
      salonId: salonId,
      memberId: memberId,
      memberName: memberName,
      initialCode: initialCode,
      employeeWhatsapp: employeeWhatsapp,
    ),
  );
}

class _EmployeeCodeSheet extends StatefulWidget {
  const _EmployeeCodeSheet({
    required this.salonId,
    required this.memberId,
    required this.memberName,
    this.initialCode,
    this.employeeWhatsapp,
  });
  final String salonId;
  final String memberId;
  final String memberName;
  final String? initialCode;
  final String? employeeWhatsapp;

  @override
  State<_EmployeeCodeSheet> createState() => _EmployeeCodeSheetState();
}

class _EmployeeCodeSheetState extends State<_EmployeeCodeSheet> {
  String? _code;
  bool _loading = false;
  bool? _waSent; // null = unknown, true = sent, false = failed/no number

  @override
  void initState() {
    super.initState();
    _code = widget.initialCode;
    if (_code == null || _code!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _generate());
    }
  }

  Future<void> _generate() async {
    setState(() => _loading = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('generateEmployeeLoginCode')
          .call<Map<String, dynamic>>({
        'salonId': widget.salonId,
        'memberId': widget.memberId,
        if ((widget.employeeWhatsapp ?? '').isNotEmpty)
          'employeeWhatsapp': widget.employeeWhatsapp,
      });
      if (!mounted) return;
      final data = res.data;
      setState(() {
        _code = data['code'] as String?;
        _waSent = data['waSent'] as bool?;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('emp_code_generate_error') ?? 'Impossible de générer le code'),
        backgroundColor: Colors.redAccent,
      ));
    }
  }

  Future<void> _copy() async {
    if (_code == null) return;
    await Clipboard.setData(ClipboardData(text: _code!));
    if (!mounted) return;
    final l = AppLocalizations.of(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(l?.tr('emp_code_copied') ?? 'Code copié'),
      backgroundColor: AppColors.brand700,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _regenerate() async {
    final l = AppLocalizations.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l?.tr('emp_code_regen_title') ?? 'Régénérer le code ?'),
        content: Text(l?.tr('emp_code_regen_body') ?? 'L\'ancien code ne fonctionnera plus. L\'employé devra utiliser le nouveau code pour se reconnecter.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(l?.tr('cancel') ?? 'Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: Text(l?.tr('emp_code_regen_confirm') ?? 'Régénérer'),
          ),
        ],
      ),
    );
    if (confirm == true) await _generate();
  }

  Widget _buildSendStatus() {
    final l = AppLocalizations.of(context);
    final hasNumber = (widget.employeeWhatsapp ?? '').isNotEmpty;
    if (!hasNumber || _waSent == null || _loading) return const SizedBox.shrink();

    final ok = _waSent == true;
    final icon = ok ? Icons.check_circle_rounded : Icons.error_outline_rounded;
    final color = ok ? AppColors.brand700 : Colors.redAccent;
    final text = ok
        ? (l?.tr('emp_code_wa_auto_sent') ?? 'Code envoyé automatiquement sur WhatsApp')
        : (l?.tr('emp_code_wa_auto_failed') ?? 'Envoi WhatsApp échoué — partagez le code manuellement');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style: GoogleFonts.plusJakartaSans(fontSize: 12, color: color, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppColors.secondary200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            l?.tr('emp_code_title') ?? 'Code de connexion',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${l?.tr('emp_code_for') ?? 'Pour'} ${widget.memberName}',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              color: AppColors.secondary500,
            ),
          ),
          const SizedBox(height: 20),

          // Code display
          Container(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.brand200),
            ),
            child: Center(
              child: _loading
                  ? const SizedBox(
                      height: 32,
                      width: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: AppColors.brand600,
                      ),
                    )
                  : Text(
                      _code ?? '----',
                      style: GoogleFonts.robotoMono(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950,
                        letterSpacing: 6,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),

          _buildSendStatus(),

          Text(
            l?.tr('emp_code_help') ?? 'Le code est envoyé automatiquement à votre employé sur WhatsApp. Vous pouvez aussi le copier ou le partager si besoin.',
            textAlign: TextAlign.center,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              color: AppColors.secondary500,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),

          Row(
            children: [
              Expanded(
                child: _ActionBtn(
                  icon: Icons.copy_rounded,
                  label: l?.tr('emp_code_copy') ?? 'Copier',
                  onTap: _code == null ? null : _copy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ActionBtn(
                  icon: Icons.check_circle_rounded,
                  label: l?.tr('emp_code_close') ?? 'Fermer',
                  onTap: () => Navigator.of(context).pop(),
                  primary: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: _loading ? null : _regenerate,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(l?.tr('emp_code_regenerate') ?? 'Régénérer un nouveau code'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.secondary500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label, style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w600)),
        style: ElevatedButton.styleFrom(
          backgroundColor: primary ? AppColors.brand600 : Colors.white,
          foregroundColor: primary ? Colors.white : AppColors.brand700,
          elevation: 0,
          side: primary ? null : const BorderSide(color: AppColors.brand600, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}
