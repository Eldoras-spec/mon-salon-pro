import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/team_member_model.dart';
import '../providers/team_providers.dart';
import '../services/database_service.dart';
import '../services/onboarding_progress.dart';
import '../services/plan_config.dart';
import '../theme/app_colors.dart';
import '../services/app_localizations.dart';
import '../widgets/country_phone_field.dart';
import '../widgets/employee_code_widget.dart';
import '../widgets/member_avatar.dart';
import 'owner_onboarding_step4_screen.dart';

class OwnerOnboardingStep5Screen extends StatefulWidget {
  const OwnerOnboardingStep5Screen({super.key, required this.salonData});
  final Map<String, dynamic> salonData;

  @override
  State<OwnerOnboardingStep5Screen> createState() =>
      _OwnerOnboardingStep5ScreenState();
}

class _OwnerOnboardingStep5ScreenState
    extends State<OwnerOnboardingStep5Screen> {
  final List<TeamMemberModel> _members = [];
  bool _loading = true;

  String get _salonId =>
      (widget.salonData['ownerId'] as String?) ?? '';

  String get _plan =>
      (widget.salonData['plan'] as String?) ?? PlanConfig.planFree;

  bool get _isFreePlan => _plan == PlanConfig.planFree;

  bool get _atFreeCap =>
      _isFreePlan && _members.length >= PlanConfig.freeTeamMemberCap;

  @override
  void initState() {
    super.initState();
    _loadExistingMembers();
  }

  Future<void> _loadExistingMembers() async {
    try {
      if (_salonId.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final existing = await DatabaseService().getTeamMembers(_salonId).first;
      if (mounted) {
        setState(() {
          _members.clear();
          _members.addAll(existing);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _goToServices() {
    if (_members.isEmpty) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l?.tr('onboarding_step5_error_empty') ?? 'Veuillez ajouter au moins un employé'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    OnboardingProgress.save(
        step: 6, stepName: 'services', data: widget.salonData);
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => OwnerOnboardingStep4Screen(
          salonData: widget.salonData,
          teamMembers: _members,
        ),
      ),
    );
  }

  void _showAddMemberSheet() {
    if (_atFreeCap) {
      _showFreeCapDialog();
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _OnboardingMemberSheet(
        salonId: _salonId,
        onAdded: (member) {
          setState(() => _members.add(member));
        },
      ),
    );
  }

  void _showFreeCapDialog() {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.group_add_outlined,
              color: Colors.amber.shade800, size: 28),
        ),
        title: Text(
          l?.tr('team_cap_title') ?? 'Limite du plan Free',
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          l?.tr('team_cap_body') ??
              'Le plan Free autorise jusqu\'à 2 employés. Passez au plan Essentiel pour une équipe illimitée (3 mois offerts).',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.secondary600),
        ),
        actions: [
          Center(
            child: TextButton(
              onPressed: () => Navigator.pop(dCtx),
              child: Text(l?.tr('common_ok') ?? 'OK'),
            ),
          ),
        ],
      ),
    );
  }

  void _deleteMember(int index) async {
    final member = _members[index];
    try {
      if (member.id.isNotEmpty) {
        await DatabaseService()
            .deleteTeamMember(_salonId, member.id);
      }
      setState(() => _members.removeAt(index));
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'))),
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
            // Progress bar
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios_new_rounded,
                            size: 18, color: AppColors.brand950),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                      const Spacer(),
                      Text(
                        l?.tr('onboarding_step5_step') ?? 'Étape 5 sur 6',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary400,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: 0.8,
                      minHeight: 5,
                      backgroundColor: AppColors.secondary100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.brand600),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    Text(
                      l?.tr('onboarding_step5_title') ?? 'Votre Équipe',
                      style: GoogleFonts.dmSans(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: AppColors.brand950,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l?.tr('onboarding_step5_subtitle') ?? 'Ajoutez au moins un membre de votre équipe.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.secondary500,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Members list
                    if (_loading)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(32),
                        child: CircularProgressIndicator(color: AppColors.brand600),
                      ))
                    else if (_members.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 32, horizontal: 24),
                        decoration: BoxDecoration(
                          color: AppColors.secondary50,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.secondary200),
                        ),
                        child: Column(
                          children: [
                            const Icon(Icons.groups_outlined,
                                size: 40, color: AppColors.secondary300),
                            const SizedBox(height: 12),
                            Text(
                              l?.tr('onboarding_step5_empty_title') ?? 'Aucun membre ajouté',
                              style: const TextStyle(
                                color: AppColors.secondary400,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l?.tr('onboarding_step5_empty_subtitle') ?? 'Au moins un employé est requis pour continuer',
                              style: TextStyle(
                                color: AppColors.secondary400,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      )
                    else
                      ..._members.asMap().entries.map(
                        (entry) {
                          final i = entry.key;
                          final m = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: AppColors.secondary200),
                            ),
                            child: Row(
                              children: [
                                MemberAvatar(
                                  name: m.name,
                                  photoUrl: m.photoUrl,
                                  radius: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        m.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                          color: AppColors.brand950,
                                        ),
                                      ),
                                      Text(
                                        m.role == 'gerant'
                                            ? (l?.tr('team_role_manager') ?? 'Gérant(e)')
                                            : (l?.tr('team_role_member') ?? 'Employé(e)'),
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: AppColors.secondary500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close,
                                      size: 18,
                                      color: AppColors.secondary400),
                                  onPressed: () => _deleteMember(i),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),

                    const SizedBox(height: 20),

                    // Add member button
                    OutlinedButton.icon(
                      onPressed: _showAddMemberSheet,
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: Text(l?.tr('onboarding_step5_add') ?? 'Ajouter un membre'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.brand600,
                        side: const BorderSide(color: AppColors.brand300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _goToServices,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _members.isEmpty
                        ? AppColors.secondary200
                        : AppColors.brand700,
                    foregroundColor: _members.isEmpty
                        ? AppColors.secondary400
                        : Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  child: Text(l?.tr('onboarding_step5_continue') ?? 'Continuer vers les services'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inline Form Sheet for Onboarding ────────────────────────────────────────

class _OnboardingMemberSheet extends StatefulWidget {
  const _OnboardingMemberSheet(
      {required this.salonId, required this.onAdded});
  final String salonId;
  final void Function(TeamMemberModel) onAdded;

  @override
  State<_OnboardingMemberSheet> createState() =>
      _OnboardingMemberSheetState();
}

class _OnboardingMemberSheetState extends State<_OnboardingMemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _pinConfirmCtrl = TextEditingController();
  String? _phoneE164;
  String? _phoneError;
  String _role = 'member';
  bool _saving = false;
  bool _showPin = false;

  bool get _needsPin => _role == 'gerant';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // WhatsApp number is mandatory at creation — we use it to wa.me the
    // login code immediately after the member is saved.
    if (_phoneE164 == null || _phoneE164!.length < 6) {
      // Show the error INSIDE the sheet — a SnackBar from the parent
      // ScaffoldMessenger renders BEHIND the modal bottom sheet and is
      // invisible, so the owner saw nothing happen on tap.
      final l = AppLocalizations.of(context);
      setState(() => _phoneError = l?.tr('team_phone_required') ??
          'Le numéro WhatsApp est obligatoire pour envoyer le code de connexion à l\'employé.');
      return;
    }
    setState(() => _saving = true);
    try {
      final draft = TeamMemberModel(
        id: '',
        salonId: widget.salonId,
        name: _nameCtrl.text.trim(),
        role: _role,
        pinHash: _needsPin ? hashPin(_pinCtrl.text.trim()) : '',
        phone: _phoneE164,
        isActive: true,
        createdAt: DateTime.now(),
      );
      final saved = await DatabaseService().addTeamMember(draft);
      widget.onAdded(saved);
      // Auto-launch WhatsApp with the login code pre-filled. Owner
      // just hits Send. Best-effort: if the platform refuses to launch
      // wa.me (e.g. WhatsApp not installed on a tablet), the owner can
      // still copy/share the code via the existing UI from the team
      // screen. We don't block onboarding flow.
      if (mounted) {
        await showEmployeeCodeSheet(
          context: context,
          salonId: widget.salonId,
          memberId: saved.id,
          memberName: saved.name,
          employeeWhatsapp: _phoneE164,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text((l?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e')),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.secondary200,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  l?.tr('onboarding_step5_sheet_title') ?? 'Ajouter un membre',
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 20),
                _label(l?.tr('team_name_label') ?? 'Nom complet *'),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDeco('Ex: Sophie Martin'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? (l?.tr('common_required') ?? 'Requis') : null,
                ),
                const SizedBox(height: 14),
                _label(l?.tr('team_role_label') ?? 'Rôle *'),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: _inputDeco(null),
                  items: [
                    DropdownMenuItem(
                        value: 'member', child: Text(l?.tr('team_role_member') ?? 'Employé(e)')),
                    DropdownMenuItem(
                        value: 'gerant', child: Text(l?.tr('team_role_manager') ?? 'Gérant(e)')),
                  ],
                  onChanged: (v) => setState(() {
                    _role = v ?? 'member';
                    if (!_needsPin) {
                      _pinCtrl.clear();
                      _pinConfirmCtrl.clear();
                    }
                  }),
                ),
                const SizedBox(height: 14),
                _label(l?.tr('team_phone_label_create') ?? 'Téléphone WhatsApp *'),
                CountryPhoneField(
                  initialE164: _phoneE164,
                  hintText: '612345678',
                  onChanged: (e164) => setState(() {
                    _phoneE164 = e164;
                    _phoneError = null; // clear the error as soon as they type
                  }),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _phoneError ??
                        (l?.tr('team_phone_helper_create') ??
                            'On enverra automatiquement le code de connexion par WhatsApp.'),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      color: _phoneError != null
                          ? Colors.redAccent
                          : AppColors.secondary500,
                    ),
                  ),
                ),
                // PIN fields only for gérant
                if (_needsPin) ...[
                  const SizedBox(height: 14),
                  _label(l?.tr('team_pin_label_new') ?? 'PIN 6 chiffres *'),
                  TextFormField(
                    controller: _pinCtrl,
                    obscureText: !_showPin,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: _inputDeco('••••••').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_showPin
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _showPin = !_showPin),
                      ),
                    ),
                    validator: (v) {
                      if (!_needsPin) return null;
                      if (v == null || v.length != 6) {
                        return l?.tr('team_pin_error_length') ?? 'Le PIN doit contenir exactement 6 chiffres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  _label(l?.tr('team_pin_confirm_new') ?? 'Confirmer le PIN *'),
                  TextFormField(
                    controller: _pinConfirmCtrl,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: _inputDeco('••••••'),
                    validator: (v) {
                      if (!_needsPin) return null;
                      if (v != _pinCtrl.text) {
                        return l?.tr('team_pin_error_mismatch') ?? 'Les PINs ne correspondent pas';
                      }
                      return null;
                    },
                  ),
                ],
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand700,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      textStyle: const TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : Text(l?.tr('onboarding_step5_add_button') ?? 'Ajouter le membre'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppColors.secondary700,
            )),
      );

  InputDecoration _inputDeco(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle:
            const TextStyle(color: AppColors.secondary400, fontSize: 13),
        filled: true,
        fillColor: AppColors.secondary50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.secondary200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              const BorderSide(color: AppColors.brand500, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDC2626)),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      );
}
