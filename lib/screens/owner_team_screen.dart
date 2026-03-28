import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/team_member_model.dart';
import '../models/salon_model.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/app_localizations.dart';
import '../services/database_service.dart';
import '../theme/app_colors.dart';

class OwnerTeamScreen extends ConsumerStatefulWidget {
  const OwnerTeamScreen({super.key});

  @override
  ConsumerState<OwnerTeamScreen> createState() => _OwnerTeamScreenState();
}

class _OwnerTeamScreenState extends ConsumerState<OwnerTeamScreen> {
  bool _showByService = false;
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final teamAsync = ref.watch(ownerTeamProvider);
    final salonAsync = ref.watch(ownerSalonProvider);
    final activeMember = ref.watch(activeTeamMemberProvider);
    final isGerant = activeMember?.role == 'gerant';

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: AppColors.brand950, size: 18),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              l?.tr('team_title') ?? 'Mon Équipe',
              style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold,
                color: AppColors.brand950,
                fontSize: 20,
              ),
            ),
            actions: [
              if (!isGerant)
                teamAsync.when(
                  data: (members) => IconButton(
                    icon: const Icon(Icons.person_add_outlined,
                        color: AppColors.brand600, size: 22),
                    onPressed: () => _showAddMemberSheet(
                        context, ref, salonAsync.value?.id,
                        salonAsync.value?.services ?? []),
                    tooltip: l?.tr('team_add_member') ?? 'Ajouter un membre',
                  ),
                  loading: () => const SizedBox(width: 48),
                  error: (_, _) => const SizedBox(width: 48),
                ),
              const SizedBox(width: 8),
            ],
          ),

          SliverToBoxAdapter(
            child: teamAsync.when(
              loading: () => const SizedBox(
                height: 200,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.brand500),
                ),
              ),
              error: (e, _) => Center(
                child: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e',
                    style: const TextStyle(color: AppColors.secondary500)),
              ),
              data: (members) {
                final activeCount =
                    members.where((m) => m.isActive).length;
                return Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Stats
                      Row(
                        children: [
                          Expanded(
                            child: _TeamStat(
                              icon: Icons.groups_outlined,
                              iconBg: AppColors.brand50,
                              iconColor: AppColors.brand600,
                              label: l?.tr('team_members_tab') ?? 'Membres',
                              value: '${members.length}',
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _TeamStat(
                              icon: Icons.calendar_today_outlined,
                              iconBg: const Color(0xFFF0FDF4),
                              iconColor: const Color(0xFF16A34A),
                              label: l?.tr('team_available_tab') ?? 'Disponibles',
                              value: '$activeCount',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),

                      // Toggle + Team/Service list
                      _TeamServiceToggle(
                        members: members,
                        salon: salonAsync.value,
                        isGerant: isGerant,
                        showByService: _showByService,
                        onToggle: (v) => setState(() => _showByService = v),
                        onAddMember: () => _showAddMemberSheet(
                            context, ref, salonAsync.value?.id,
                            salonAsync.value?.services ?? []),
                        onEditMember: (m) => _showEditMemberSheet(
                            context, ref, m, salonAsync.value?.id,
                            salonAsync.value?.services ?? []),
                        onDeleteMember: (m) => _confirmDelete(
                            context, ref, m, salonAsync.value?.id),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showAddMemberSheet(
      BuildContext context, WidgetRef ref, String? salonId,
      List<Map<String, dynamic>> services) {
    if (salonId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _MemberFormSheet(salonId: salonId, services: services),
    );
  }

  void _showEditMemberSheet(BuildContext context, WidgetRef ref,
      TeamMemberModel member, String? salonId,
      List<Map<String, dynamic>> services) {
    if (salonId == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _MemberFormSheet(
          salonId: salonId, existing: member, services: services),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref,
      TeamMemberModel member, String? salonId) {
    if (salonId == null) return;
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
            (l?.tr('team_delete_title') ?? 'Supprimer {name} ?').replaceAll('{name}', member.name),
            style: GoogleFonts.dmSans(
                fontWeight: FontWeight.bold, color: AppColors.brand950)),
        content: Text(
            l?.tr('team_delete_message_alt') ?? 'Cette action est irréversible. Le membre sera supprimé définitivement.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l?.tr('common_cancel') ?? 'Annuler',
                style: const TextStyle(color: AppColors.secondary500)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await DatabaseService().deleteTeamMember(salonId, member.id);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text((l?.tr('team_deleted') ?? '{name} supprimé').replaceAll('{name}', member.name)),
                    backgroundColor: AppColors.brand700,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l?.tr('common_delete') ?? 'Supprimer'),
          ),
        ],
      ),
    );
  }
}

// ─── Member Card ─────────────────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  const _MemberCard({
    required this.member,
    required this.isGerant,
    required this.salonId,
    required this.onEdit,
    required this.onDelete,
  });

  final TeamMemberModel member;
  final bool isGerant;
  final String salonId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  Color get _roleColor {
    switch (member.role) {
      case 'gerant':
        return const Color(0xFFEA580C);
      default:
        return AppColors.brand600;
    }
  }

  Color get _roleBg {
    switch (member.role) {
      case 'gerant':
        return const Color(0xFFFFF7ED);
      default:
        return AppColors.brand50;
    }
  }

  String _roleLabel(AppLocalizations? l) {
    switch (member.role) {
      case 'gerant':
        return l?.tr('team_role_manager') ?? 'Gérant(e)';
      default:
        return l?.tr('team_role_member') ?? 'Employé(e)';
    }
  }

  String get _initials {
    final parts = member.name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _roleBg,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                _initials,
                style: TextStyle(
                  color: _roleColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _roleBg,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _roleLabel(l),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _roleColor,
                        ),
                      ),
                    ),
                    if (member.phone != null &&
                        member.phone!.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Text(
                        member.phone!,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.secondary500,
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.assignedServiceNames.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ...member.assignedServiceNames.take(3).map(
                            (s) => Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.secondary50,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                    color: AppColors.secondary200),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.secondary600,
                                ),
                              ),
                            ),
                          ),
                      if (member.assignedServiceNames.length > 3)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.secondary50,
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: AppColors.secondary200),
                          ),
                          child: Text(
                            '+${member.assignedServiceNames.length - 3}',
                            style: const TextStyle(
                              fontSize: 10,
                              color: AppColors.secondary600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (!isGerant) ...[
            IconButton(
              icon: const Icon(Icons.edit_outlined,
                  size: 18, color: AppColors.secondary400),
              onPressed: onEdit,
              tooltip: l?.tr('common_edit') ?? 'Modifier',
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline,
                  size: 18, color: Color(0xFFDC2626)),
              onPressed: onDelete,
              tooltip: l?.tr('common_delete') ?? 'Supprimer',
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────

class _EmptyTeam extends StatelessWidget {
  const _EmptyTeam({required this.isGerant, required this.onAdd});
  final bool isGerant;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.secondary100),
      ),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.secondary50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.groups_outlined,
                size: 30, color: AppColors.secondary300),
          ),
          const SizedBox(height: 16),
          Text(
            l?.tr('team_empty_title') ?? 'Aucun membre pour l\'instant',
            style: GoogleFonts.dmSans(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l?.tr('team_empty_subtitle_alt') ?? 'Ajoutez les membres de votre équipe pour\ngérer leurs horaires et leurs services.',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.secondary400,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          if (!isGerant) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_outlined, size: 18),
              label: Text(l?.tr('team_add_member') ?? 'Ajouter un membre'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand700,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
                textStyle: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 13),
                elevation: 0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Add / Edit Member Bottom Sheet ──────────────────────────────────────────

class _MemberFormSheet extends StatefulWidget {
  const _MemberFormSheet(
      {required this.salonId,
      required this.services,
      this.existing});
  final String salonId;
  final List<Map<String, dynamic>> services;
  final TeamMemberModel? existing;

  @override
  State<_MemberFormSheet> createState() => _MemberFormSheetState();
}

class _MemberFormSheetState extends State<_MemberFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _pinCtrl;
  late final TextEditingController _pinConfirmCtrl;
  String _role = 'member';
  bool _saving = false;
  bool _showPin = false;
  bool _showPinConfirm = false;
  late Set<String> _selectedServices;
  bool _servicesError = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _phoneCtrl = TextEditingController(text: m?.phone ?? '');
    _pinCtrl = TextEditingController();
    _pinConfirmCtrl = TextEditingController();
    _role = m?.role ?? 'member';
    _selectedServices = Set<String>.from(m?.assignedServiceNames ?? []);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Validate services separately (not in Form validator)
    if (widget.services.isNotEmpty && _selectedServices.isEmpty) {
      setState(() => _servicesError = true);
      return;
    }
    setState(() => _saving = true);

    try {
      final db = DatabaseService();

      if (_isEditing) {
        final updates = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'role': _role,
          'phone': _phoneCtrl.text.trim(),
          'assignedServiceNames': _selectedServices.toList(),
        };
        // Only update pinHash for gérant if a new PIN was entered
        if (_role == 'gerant' && _pinCtrl.text.isNotEmpty) {
          updates['pinHash'] = hashPin(_pinCtrl.text.trim());
        } else if (_role == 'member') {
          updates['pinHash'] = ''; // employees have no PIN
        }
        await db.updateTeamMember(
            widget.salonId, widget.existing!.id, updates);
      } else {
        final member = TeamMemberModel(
          id: '',
          salonId: widget.salonId,
          name: _nameCtrl.text.trim(),
          role: _role,
          pinHash: _role == 'gerant'
              ? hashPin(_pinCtrl.text.trim())
              : '', // employees have no PIN
          phone: _phoneCtrl.text.trim().isEmpty
              ? null
              : _phoneCtrl.text.trim(),
          isActive: true,
          createdAt: DateTime.now(),
          assignedServiceNames: _selectedServices.toList(),
        );
        await db.addTeamMember(member);
      }

      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l?.tr('common_error_short') ?? 'Erreur'}: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
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
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
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
                  _isEditing
                      ? (l?.tr('team_edit_title') ?? 'Modifier le membre')
                      : (l?.tr('team_add_title') ?? 'Ajouter un membre'),
                  style: GoogleFonts.dmSans(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
                const SizedBox(height: 20),

                // Name
                _label(l?.tr('team_name_label') ?? 'Nom complet *'),
                TextFormField(
                  controller: _nameCtrl,
                  decoration: _inputDeco('Ex: Sophie Martin'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? (l?.tr('team_required') ?? 'Requis') : null,
                ),
                const SizedBox(height: 16),

                // Role
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
                  onChanged: (v) => setState(() => _role = v ?? 'member'),
                ),
                const SizedBox(height: 16),

                // Phone
                _label(l?.tr('team_phone_label') ?? 'Téléphone (optionnel)'),
                TextFormField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: _inputDeco('Ex: 06 12 34 56 78'),
                ),
                const SizedBox(height: 16),

                // PIN — only for gérant
                if (_role == 'gerant') ...[
                  _label(_isEditing
                      ? (l?.tr('team_pin_label_edit') ?? 'Nouveau PIN 6 chiffres (laisser vide = inchangé)')
                      : (l?.tr('team_pin_label_new') ?? 'PIN 6 chiffres *')),
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
                      if (_isEditing && (v == null || v.isEmpty)) return null;
                      if (v == null || v.length != 6) {
                        return l?.tr('team_pin_error_length') ?? 'Le PIN doit contenir exactement 6 chiffres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),

                  // Confirm PIN
                  _label(_isEditing
                      ? (l?.tr('team_pin_confirm_edit') ?? 'Confirmer le nouveau PIN')
                      : (l?.tr('team_pin_confirm_new') ?? 'Confirmer le PIN *')),
                  TextFormField(
                    controller: _pinConfirmCtrl,
                    obscureText: !_showPinConfirm,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: _inputDeco('••••••').copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_showPinConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(
                            () => _showPinConfirm = !_showPinConfirm),
                      ),
                    ),
                    validator: (v) {
                      if (_isEditing && _pinCtrl.text.isEmpty) return null;
                      if (v != _pinCtrl.text) {
                        return l?.tr('team_pin_error_mismatch') ?? 'Les PINs ne correspondent pas';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                // Services maîtrisés
                if (widget.services.isNotEmpty) ...[
                  Row(
                    children: [
                      _label(l?.tr('team_services_label') ?? 'Services maîtrisés *'),
                      if (_servicesError)
                        Padding(
                          padding: const EdgeInsets.only(left: 8, bottom: 6),
                          child: Text(
                            l?.tr('team_services_hint') ?? 'Sélectionnez au moins un service',
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFFDC2626)),
                          ),
                        ),
                    ],
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.secondary50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _servicesError
                            ? const Color(0xFFDC2626)
                            : AppColors.secondary200,
                      ),
                    ),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.services.map((s) {
                        final name = s['name'] as String? ?? '';
                        final selected = _selectedServices.contains(name);
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              if (selected) {
                                _selectedServices.remove(name);
                              } else {
                                _selectedServices.add(name);
                              }
                              _servicesError = false;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.brand600
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: selected
                                    ? AppColors.brand600
                                    : AppColors.secondary200,
                              ),
                            ),
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: selected
                                    ? Colors.white
                                    : AppColors.secondary600,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 4),

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
                        : Text(
                            _isEditing
                                ? (l?.tr('team_save') ?? 'Enregistrer')
                                : (l?.tr('team_add_button') ?? 'Ajouter le membre')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.secondary700,
        ),
      ),
    );
  }

  InputDecoration _inputDeco(String? hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.secondary400, fontSize: 13),
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
        borderSide: const BorderSide(color: AppColors.brand500, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDC2626)),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

// ─── Stat Card ────────────────────────────────────────────────────────────────

class _TeamStat extends StatelessWidget {
  const _TeamStat({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppColors.secondary500)),
        ],
      ),
    );
  }
}

// ─── Toggle: Members view / Service priority view ─────────────────────────────

class _TeamServiceToggle extends StatefulWidget {
  const _TeamServiceToggle({
    required this.members,
    required this.salon,
    required this.isGerant,
    required this.showByService,
    required this.onToggle,
    required this.onAddMember,
    required this.onEditMember,
    required this.onDeleteMember,
  });
  final List<TeamMemberModel> members;
  final SalonModel? salon;
  final bool isGerant;
  final bool showByService;
  final void Function(bool) onToggle;
  final VoidCallback onAddMember;
  final void Function(TeamMemberModel) onEditMember;
  final void Function(TeamMemberModel) onDeleteMember;

  @override
  State<_TeamServiceToggle> createState() => _TeamServiceToggleState();
}

class _TeamServiceToggleState extends State<_TeamServiceToggle> {
  List<Map<String, dynamic>>? _localServices;
  bool _hasPendingChanges = false;

  bool get _showByService => widget.showByService;

  List<Map<String, dynamic>> get _services {
    if (_localServices != null) return _localServices!.where((s) => s['visibleTo'] == null).toList();
    return (widget.salon?.services ?? []).cast<Map<String, dynamic>>().where((s) => s['visibleTo'] == null).toList();
  }

  @override
  void didUpdateWidget(covariant _TeamServiceToggle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.salon?.id != oldWidget.salon?.id) {
      _localServices = null;
    }
    // Save when toggling away from service view
    if (oldWidget.showByService && !widget.showByService) {
      _savePendingChanges();
    }
  }

  @override
  void dispose() {
    _savePendingChanges();
    super.dispose();
  }

  void _savePendingChanges() {
    if (!_hasPendingChanges || _localServices == null) return;
    final salonId = widget.salon?.id;
    if (salonId != null) {
      DatabaseService().updateSalonField(salonId, 'services', _localServices!);
    }
    _hasPendingChanges = false;
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.secondary100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              _buildTab(
                icon: Icons.people_outline,
                label: l?.tr('team_by_member') ?? 'Par membre',
                isActive: !_showByService,
                onTap: () => widget.onToggle(false),
              ),
              _buildTab(
                icon: Icons.content_cut,
                label: l?.tr('team_by_service') ?? 'Par service',
                isActive: _showByService,
                onTap: () => widget.onToggle(true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        if (!_showByService) ...[
          // Members view
          Text(
            l?.tr('team_section_title') ?? 'Membres de l\'équipe',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 16),
          if (widget.members.isEmpty)
            _EmptyTeam(
              isGerant: widget.isGerant,
              onAdd: widget.onAddMember,
            )
          else
            ...widget.members.map((m) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MemberCard(
                member: m,
                isGerant: widget.isGerant,
                salonId: widget.salon?.id ?? '',
                onEdit: () => widget.onEditMember(m),
                onDelete: () => widget.onDeleteMember(m),
              ),
            )),
        ] else ...[
          // Service priority view
          Text(
            l?.tr('team_priority_title') ?? 'Priorité par service',
            style: GoogleFonts.dmSans(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppColors.brand950,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l?.tr('team_priority_hint') ?? 'Classez les employés par ordre de priorité pour l\'auto-assignation.',
            style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
          ),
          const SizedBox(height: 16),
          ..._buildServicePriorityList(l),
        ],
      ],
    );
  }

  Widget _buildTab({
    required IconData icon,
    required String label,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isActive
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 4, offset: const Offset(0, 1))]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: isActive ? AppColors.brand600 : AppColors.secondary400),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? AppColors.brand600 : AppColors.secondary400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildServicePriorityList(AppLocalizations? l) {
    final services = _services;
    if (services.isEmpty) {
      return [
        Center(
          child: Text(
            l?.tr('team_no_services') ?? 'Aucun service',
            style: const TextStyle(color: AppColors.secondary400, fontSize: 14),
          ),
        ),
      ];
    }

    return services.cast<Map<String, dynamic>>().map((svc) {
      final svcName = (svc['name'] ?? svc['title'] ?? '') as String;
      final duration = svc['duration'] ?? 30;
      final category = svc['category'] ?? '';

      // Get members assigned to this service
      final assignedMembers = widget.members
          .where((m) => m.isActive && (m.assignedServiceNames).contains(svcName))
          .toList();

      if (assignedMembers.isEmpty) return const SizedBox.shrink();

      // Get priority order from Firestore (stored in service map)
      final priorityList = List<String>.from(svc['memberPriority'] ?? []);

      // Sort members by priority: those in priorityList first (in order), then the rest
      final sortedMembers = List<TeamMemberModel>.from(assignedMembers);
      sortedMembers.sort((a, b) {
        final aIdx = priorityList.indexOf(a.id);
        final bIdx = priorityList.indexOf(b.id);
        if (aIdx >= 0 && bIdx >= 0) return aIdx.compareTo(bIdx);
        if (aIdx >= 0) return -1;
        if (bIdx >= 0) return 1;
        return 0;
      });

      return Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Service header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        svcName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.brand950,
                        ),
                      ),
                      Text(
                        '$category · $duration min',
                        style: const TextStyle(fontSize: 12, color: AppColors.secondary400),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.brand50,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${sortedMembers.length}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.brand600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Members with priority arrows
            ...sortedMembers.asMap().entries.map((entry) {
              final idx = entry.key;
              final member = entry.value;
              final isFirst = idx == 0;
              final isLast = idx == sortedMembers.length - 1;

              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    // Priority number
                    Container(
                      width: 24, height: 24,
                      decoration: BoxDecoration(
                        color: isFirst ? AppColors.brand600 : AppColors.secondary100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          '${idx + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isFirst ? Colors.white : AppColors.secondary500,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Member name
                    Expanded(
                      child: Text(
                        member.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isFirst ? FontWeight.w600 : FontWeight.normal,
                          color: AppColors.brand950,
                        ),
                      ),
                    ),
                    // Up arrow
                    if (!isFirst)
                      GestureDetector(
                        onTap: () => _moveMember(svcName, sortedMembers, idx, -1),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.keyboard_arrow_up, size: 20, color: AppColors.secondary500),
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                    // Down arrow
                    if (!isLast)
                      GestureDetector(
                        onTap: () => _moveMember(svcName, sortedMembers, idx, 1),
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.keyboard_arrow_down, size: 20, color: AppColors.secondary500),
                        ),
                      )
                    else
                      const SizedBox(width: 28),
                  ],
                ),
              );
            }),
          ],
        ),
      );
    }).toList();
  }

  Future<void> _moveMember(String serviceName, List<TeamMemberModel> currentOrder, int fromIdx, int direction) async {
    final toIdx = fromIdx + direction;
    if (toIdx < 0 || toIdx >= currentOrder.length) return;

    // Swap
    final temp = currentOrder[fromIdx];
    currentOrder[fromIdx] = currentOrder[toIdx];
    currentOrder[toIdx] = temp;

    final newPriority = currentOrder.map((m) => m.id).toList();

    // Update local state immediately
    final services = List<Map<String, dynamic>>.from(
      _services.map((s) => Map<String, dynamic>.from(s)),
    );

    for (final svc in services) {
      final name = (svc['name'] ?? svc['title'] ?? '') as String;
      if (name == serviceName) {
        svc['memberPriority'] = newPriority;
        break;
      }
    }

    setState(() => _localServices = services);

    // Don't save to Firestore here — save when leaving the view
    // to avoid stream rebuild that resets scroll position
    _hasPendingChanges = true;
  }
}
