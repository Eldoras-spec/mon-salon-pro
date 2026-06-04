import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/appointment_model.dart';
import '../models/team_member_model.dart';
import '../models/salon_model.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/app_localizations.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../services/database_service.dart';
import '../services/plan_config.dart';
import '../theme/app_colors.dart';
import 'owner_subscription_screen.dart';
import '../utils/media_compressor.dart';
import '../widgets/country_phone_field.dart';
import '../widgets/employee_code_widget.dart';
import '../widgets/member_avatar.dart';
import '../widgets/team_member_detail_sheet.dart';

// Agenda palette — kept in sync with `_memberColors` in owner_agenda_screen.dart.
// All light pastels for readability.
const _agendaPalette = [
  Color(0xFFFDE68A), // amber
  Color(0xFFA7F3D0), // emerald
  Color(0xFFBFDBFE), // blue
  Color(0xFFD9F99D), // lime
  Color(0xFFC4B5FD), // violet
  Color(0xFFFED7AA), // orange
  Color(0xFF99F6E4), // teal
  Color(0xFFFECDD3), // rose
  Color(0xFFFBCFE8), // pink
  Color(0xFFBAE6FD), // sky
  Color(0xFFC7D2FE), // indigo
  Color(0xFFF5D0FE), // fuchsia
  Color(0xFFE2E8F0), // slate
];

class OwnerTeamScreen extends ConsumerStatefulWidget {
  const OwnerTeamScreen({super.key, this.initialShowByService = false});

  final bool initialShowByService;

  @override
  ConsumerState<OwnerTeamScreen> createState() => _OwnerTeamScreenState();
}

class _OwnerTeamScreenState extends ConsumerState<OwnerTeamScreen> {
  late bool _showByService = widget.initialShowByService;
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
                        context, ref, salonAsync.value,
                        salonAsync.value?.services ?? [],
                        members.length),
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
                            context, ref, salonAsync.value,
                            salonAsync.value?.services ?? [],
                            members.length),
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
      BuildContext context, WidgetRef ref, SalonModel? salon,
      List<Map<String, dynamic>> services, int currentCount) {
    if (salon == null) return;
    // Free plan team cap: block at `freeTeamMemberCap` members, redirect
    // to the subscription screen so owner can upgrade.
    if (salon.isFree && currentCount >= PlanConfig.freeTeamMemberCap) {
      _showTeamCapDialog(context);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _MemberFormSheet(salonId: salon.id, services: services),
    );
  }

  void _showTeamCapDialog(BuildContext context) {
    final l = AppLocalizations.of(context);
    showDialog(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56, height: 56,
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
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dCtx);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const OwnerSubscriptionScreen(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
            ),
            child: Text(l?.tr('team_cap_upgrade_cta') ?? 'Passer en Essentiel'),
          ),
        ],
      ),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref,
      TeamMemberModel member, String? salonId) async {
    if (salonId == null) return;
    final l = AppLocalizations.of(context);

    // Show loading dialog while we check for active appointments
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.brand500),
      ),
    );

    final upcoming = await DatabaseService()
        .getUpcomingAppointmentsForMember(salonId, member.id);
    final allMembers = ref.read(ownerTeamProvider).value ?? [];
    final otherMembers =
        allMembers.where((m) => m.id != member.id && m.isActive).toList();

    if (!context.mounted) return;
    Navigator.pop(context); // close loading

    // No active appointments → simple delete confirm
    if (upcoming.isEmpty) {
      _showSimpleDeleteConfirm(context, member, salonId, l);
      return;
    }

    // Check for services this member is the only one assigned to (among RDV services)
    final blockedAppointments = <AppointmentModel>[];
    final blockedServices = <String>{};

    for (final appt in upcoming) {
      final eligible = otherMembers
          .where((m) => (m.assignedServiceNames).contains(appt.serviceName))
          .toList();
      if (eligible.isEmpty) {
        blockedAppointments.add(appt);
        blockedServices.add(appt.serviceName);
      }
    }

    if (blockedAppointments.isNotEmpty) {
      _showBlockedDialog(context, member, blockedServices, blockedAppointments.length, l);
      return;
    }

    _showReassignChoiceDialog(
        context, ref, member, salonId, upcoming, otherMembers, l);
  }

  void _showSimpleDeleteConfirm(BuildContext context, TeamMemberModel member,
      String salonId, AppLocalizations? l) {
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

  void _showBlockedDialog(BuildContext context, TeamMemberModel member,
      Set<String> blockedServices, int blockedCount, AppLocalizations? l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l?.tr('team_delete_blocked_title') ?? 'Suppression impossible',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.bold, color: AppColors.brand950, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              (l?.tr('team_delete_blocked_message') ??
                      '{name} a {count} rendez-vous pour des prestations dont il/elle est le/la seul·e à les pratiquer. Attribuez d\'abord ces prestations à un·e autre employé·e, puis revenez supprimer.')
                  .replaceAll('{name}', member.name)
                  .replaceAll('{count}', '$blockedCount'),
              style: const TextStyle(color: AppColors.secondary600, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 12),
            Text(
              l?.tr('team_delete_blocked_services') ?? 'Prestations concernées :',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.brand950),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: blockedServices
                  .map((s) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(s,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFFDC2626))),
                      ))
                  .toList(),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: Text(l?.tr('common_understood') ?? 'Compris'),
          ),
        ],
      ),
    );
  }

  void _showReassignChoiceDialog(
      BuildContext context,
      WidgetRef ref,
      TeamMemberModel member,
      String salonId,
      List<AppointmentModel> upcoming,
      List<TeamMemberModel> otherMembers,
      AppLocalizations? l) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.event_busy_outlined, color: Color(0xFFEA580C), size: 24),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l?.tr('team_delete_reassign_title') ?? 'Rendez-vous actifs',
                style: GoogleFonts.dmSans(
                    fontWeight: FontWeight.bold, color: AppColors.brand950, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Text(
          (l?.tr('team_delete_reassign_message') ??
                  '{name} a {count} rendez-vous à venir. Comment souhaitez-vous les réassigner avant la suppression ?')
              .replaceAll('{name}', member.name)
              .replaceAll('{count}', '${upcoming.length}'),
          style: const TextStyle(color: AppColors.secondary600, fontSize: 14, height: 1.5),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        actions: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _performAutoReassignAndDelete(
                        context, ref, member, salonId, upcoming, otherMembers, l);
                  },
                  icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                  label: Text(l?.tr('team_delete_reassign_auto') ?? 'Réassigner automatiquement'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.brand600,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const Icon(Icons.edit_calendar_outlined, size: 18),
                  label: Text(l?.tr('team_delete_reassign_manual') ?? 'Réassigner manuellement'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.brand600,
                    side: const BorderSide(color: AppColors.brand300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(l?.tr('common_cancel') ?? 'Annuler',
                    style: const TextStyle(color: AppColors.secondary500)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _performAutoReassignAndDelete(
      BuildContext context,
      WidgetRef ref,
      TeamMemberModel member,
      String salonId,
      List<AppointmentModel> upcoming,
      List<TeamMemberModel> otherMembers,
      AppLocalizations? l) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: CircularProgressIndicator(color: AppColors.brand500),
      ),
    );

    try {
      // Salon services (needed to read memberPriority per service)
      final salon = ref.read(ownerSalonProvider).value;
      final services = salon?.services ?? const <Map<String, dynamic>>[];

      // All upcoming RDV for the salon, minus the ones being reassigned.
      // Tracked as (start, end) ranges per member for conflict detection.
      final allUpcoming = await DatabaseService()
          .getUpcomingAppointmentsForSalon(salonId);
      final reassigningIds = upcoming.map((a) => a.id).toSet();
      final busyRanges = <String, List<List<DateTime>>>{};
      for (final a in allUpcoming) {
        if (reassigningIds.contains(a.id)) continue;
        final mid = a.assignedMemberId;
        if (mid == null || mid.isEmpty) continue;
        final end = a.dateTime.add(Duration(minutes: a.durationMinutes));
        busyRanges.putIfAbsent(mid, () => []).add([a.dateTime, end]);
      }

      bool conflicts(String memberId, DateTime start, int duration) {
        final end = start.add(Duration(minutes: duration));
        final list = busyRanges[memberId] ?? const [];
        return list.any((r) => start.isBefore(r[1]) && end.isAfter(r[0]));
      }

      final Map<String, Map<String, String>> assignments = {};
      // Process RDV in chronological order so earlier RDV get priority on busy slots.
      upcoming.sort((a, b) => a.dateTime.compareTo(b.dateTime));

      for (final appt in upcoming) {
        // Candidates = other members who can perform this service
        var candidates = otherMembers
            .where((m) => m.assignedServiceNames.contains(appt.serviceName))
            .toList();
        if (candidates.isEmpty) continue; // blocker — already filtered earlier

        // Sort by memberPriority defined on the service
        final svcData = services.firstWhere(
          (s) => (s['name'] ?? s['title']) == appt.serviceName,
          orElse: () => <String, dynamic>{},
        );
        final priority = List<String>.from(svcData['memberPriority'] ?? []);
        if (priority.isNotEmpty) {
          candidates.sort((a, b) {
            final ai = priority.indexOf(a.id);
            final bi = priority.indexOf(b.id);
            if (ai >= 0 && bi >= 0) return ai.compareTo(bi);
            if (ai >= 0) return -1;
            if (bi >= 0) return 1;
            return 0;
          });
        }

        final duration = appt.durationMinutes;

        // Pick first non-conflicting candidate; fall back to top priority if all busy.
        TeamMemberModel picked = candidates.first;
        for (final m in candidates) {
          if (!conflicts(m.id, appt.dateTime, duration)) {
            picked = m;
            break;
          }
        }

        // Track this assignment so the next RDV sees it as a conflict source
        busyRanges
            .putIfAbsent(picked.id, () => [])
            .add([appt.dateTime, appt.dateTime.add(Duration(minutes: duration))]);

        assignments[appt.id] = {
          'memberId': picked.id,
          'memberName': picked.name,
        };
      }

      if (assignments.isNotEmpty) {
        await DatabaseService().reassignAppointments(assignments);
      }

      await DatabaseService().deleteTeamMember(salonId, member.id);

      if (!context.mounted) return;
      Navigator.pop(context); // close loading

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (l?.tr('team_delete_reassign_success') ??
                    '{name} supprimé·e. {count} rendez-vous réassignés.')
                .replaceAll('{name}', member.name)
                .replaceAll('{count}', '${assignments.length}'),
          ),
          backgroundColor: AppColors.brand700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      Navigator.pop(context); // close loading
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            (l?.tr('team_delete_reassign_error') ?? 'Erreur : {error}')
                .replaceAll('{error}', '$e'),
          ),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
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
    this.onTap,
  });

  final TeamMemberModel member;
  final bool isGerant;
  final String salonId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onTap;

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

  Future<void> _pickMemberPhoto(BuildContext context) async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !context.mounted) return;

    final overlay = MediaCompressor.showCompressionOverlay(context, isVideo: false);
    final result = await MediaCompressor.compressImage(File(picked.path));
    overlay.remove();
    if (!context.mounted) return;
    if (result == null) {
      await MediaCompressor.showSizeErrorDialog(context, isVideo: false, afterCompression: false);
      return;
    }

    try {
      final ref = FirebaseStorage.instance.ref()
          .child('salons/$salonId/team/${member.id}_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await ref.putFile(
        result.file,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      final url = await ref.getDownloadURL();

      // Delete old photo if exists
      if (member.photoUrl != null && member.photoUrl!.isNotEmpty) {
        try { await FirebaseStorage.instance.refFromURL(member.photoUrl!).delete(); } catch (_) {}
      }

      await DatabaseService().updateTeamMember(salonId, member.id, {'photoUrl': url});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Photo mise à jour'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
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
    final isCapDeactivated = member.isDeactivatedByCap;
    return Opacity(
      opacity: isCapDeactivated ? 0.55 : 1.0,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: (isCapDeactivated || onTap == null) ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCapDeactivated ? const Color(0xFFF9FAFB) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCapDeactivated
              ? const Color(0xFFE5E7EB)
              : AppColors.secondary100,
        ),
        boxShadow: isCapDeactivated
            ? null
            : [
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
          Row(
        children: [
          // Avatar with photo support (disabled when cap-deactivated)
          GestureDetector(
            onTap: isCapDeactivated ? null : () => _pickMemberPhoto(context),
            child: Stack(
              children: [
                MemberAvatar(
                  name: member.name,
                  photoUrl: member.photoUrl,
                  radius: 24,
                  backgroundColor: _roleBg,
                ),
                if (!isCapDeactivated)
                  Positioned(
                    bottom: 0, right: 0,
                    child: Container(
                      width: 18, height: 18,
                      decoration: BoxDecoration(
                        color: AppColors.brand600,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: const Icon(Icons.camera_alt, size: 10, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppColors.brand950,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCapDeactivated) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Text(
                          l?.tr('team_member_deactivated_badge') ??
                              'Désactivé · Free',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ],
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
                      Flexible(
                        child: Text(
                          member.phone!,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.secondary500,
                          ),
                          overflow: TextOverflow.ellipsis,
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
          // Share login code — owner-only action (hidden for gérant viewers
          // and cap-deactivated members), surfaced directly on the card so
          // it's more discoverable than only on the profile selector.
          if (!isGerant && !isCapDeactivated) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => showEmployeeCodeSheet(
                  context: context,
                  salonId: salonId,
                  memberId: member.id,
                  memberName: member.name,
                  initialCode: member.loginCode,
                  employeeWhatsapp: member.phone,
                ),
                icon: const Icon(Icons.key_rounded, size: 16),
                label: Text(
                  l?.tr('selector_share_code') ??
                      'Partager le code de connexion',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.brand600,
                  side: BorderSide(
                      color: AppColors.brand600.withValues(alpha: 0.4),
                      width: 1),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
              ),
            ),
          ],
        ],
      ),
      ),
        ),
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
  /// E.164 phone emitted by [CountryPhoneField] (e.g. "+212612345678").
  /// `null` when the local part is empty — saved as null on the doc.
  String? _phoneE164;
  String _role = 'member';
  bool _saving = false;
  late Set<String> _selectedServices;
  bool _servicesError = false;
  int? _agendaColorIndex;
  String? _serviceCategoryFilter; // null = all categories

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existing;
    _nameCtrl = TextEditingController(text: m?.name ?? '');
    _phoneE164 = (m?.phone != null && m!.phone!.trim().isNotEmpty)
        ? m.phone!.trim()
        : null;
    _role = m?.role ?? 'member';
    _selectedServices = Set<String>.from(m?.assignedServiceNames ?? []);
    _agendaColorIndex = m?.agendaColorIndex;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    // Validate services separately (not in Form validator)
    if (widget.services.isNotEmpty && _selectedServices.isEmpty) {
      setState(() => _servicesError = true);
      return;
    }
    // WhatsApp number is mandatory when CREATING a member (so we can
    // send them their login code via wa.me on the spot). Editing keeps
    // the field optional — legacy members may not have one yet, and
    // forcing it would block name/role updates for them.
    if (!_isEditing && (_phoneE164 == null || _phoneE164!.length < 6)) {
      final l = AppLocalizations.of(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(l?.tr('team_phone_required') ??
            'Le numéro WhatsApp est obligatoire pour envoyer le code de connexion à l\'employé.'),
        backgroundColor: Colors.redAccent,
      ));
      return;
    }
    setState(() => _saving = true);

    try {
      final db = DatabaseService();

      if (_isEditing) {
        final updates = <String, dynamic>{
          'name': _nameCtrl.text.trim(),
          'role': _role,
          'phone': _phoneE164 ?? '',
          'assignedServiceNames': _selectedServices.toList(),
          'agendaColorIndex': _agendaColorIndex,
        };
        // Both gérant and member now authenticate via WhatsApp login
        // code; no PIN is collected at edit time.
        updates['pinHash'] = '';
        await db.updateTeamMember(
            widget.salonId, widget.existing!.id, updates);
      } else {
        final member = TeamMemberModel(
          id: '',
          salonId: widget.salonId,
          name: _nameCtrl.text.trim(),
          role: _role,
          pinHash: '', // both roles authenticate via the WhatsApp login code
          phone: _phoneE164,
          isActive: true,
          createdAt: DateTime.now(),
          assignedServiceNames: _selectedServices.toList(),
          agendaColorIndex: _agendaColorIndex,
        );
        final created = await db.addTeamMember(member);

        // Show the login code sheet so the owner can share it immediately.
        // The employee's WhatsApp is now mandatory at creation, so we
        // also auto-launch wa.me with the code pre-filled — owner just
        // hits Send.
        if (mounted) {
          Navigator.pop(context);
          await showEmployeeCodeSheet(
            context: context,
            salonId: widget.salonId,
            memberId: created.id,
            memberName: created.name,
            employeeWhatsapp: _phoneE164,
          );
          return;
        }
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

                // Phone — uses the same country-code picker widget as the
                // owner's WhatsApp signup so the saved value is always
                // E.164 ("+212612345678"), regardless of how the owner
                // typed it. Required at creation (used to wa.me the
                // login code), optional on edit.
                _label(_isEditing
                    ? (l?.tr('team_phone_label_edit') ?? 'Téléphone WhatsApp (optionnel)')
                    : (l?.tr('team_phone_label_create') ?? 'Téléphone WhatsApp *')),
                CountryPhoneField(
                  initialE164: _phoneE164,
                  hintText: '612345678',
                  onChanged: (e164) => setState(() => _phoneE164 = e164),
                ),
                if (!_isEditing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      l?.tr('team_phone_helper_create') ??
                          'On enverra automatiquement le code de connexion par WhatsApp.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ),
                const SizedBox(height: 16),

                // PIN removed — gérants now authenticate on their own device
                // via the WhatsApp login code (same flow as members). The
                // legacy PIN-on-owner-device flow is kept backward-compatible
                // in the profile selector (PIN dialog still shows for old
                // gérants whose `pinHash` is non-empty), but new accounts no
                // longer need one.

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
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l?.tr('team_services_description') ??
                          'Sélectionnez les services que ce membre peut réaliser. Ils lui seront automatiquement attribués lors des réservations clients.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary400,
                        height: 1.4,
                      ),
                    ),
                  ),
                  Builder(builder: (ctx) {
                    final categories = widget.services
                        .map((s) => (s['category'] as String? ?? '').trim())
                        .where((c) => c.isNotEmpty)
                        .toSet()
                        .toList()
                      ..sort();
                    final visibleServices = widget.services.where((s) {
                      if (_serviceCategoryFilter == null) return true;
                      final cat = (s['category'] as String? ?? '').trim();
                      return cat == _serviceCategoryFilter;
                    }).toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (categories.length > 1) ...[
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(children: [
                              _categoryChip(
                                l?.tr('common_all') ?? 'Tous',
                                _serviceCategoryFilter == null,
                                () => setState(() => _serviceCategoryFilter = null),
                              ),
                              ...categories.map((c) => _categoryChip(
                                    c,
                                    _serviceCategoryFilter == c,
                                    () => setState(() => _serviceCategoryFilter = c),
                                  )),
                            ]),
                          ),
                          const SizedBox(height: 8),
                        ],
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
                            children: visibleServices.map((s) {
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
                      ],
                    );
                  }),
                  const SizedBox(height: 16),
                ],

                // Agenda color — horizontal scrollable palette
                _label(l?.tr('team_agenda_color_label') ?? 'Couleur agenda'),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.secondary50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.secondary200),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => setState(() => _agendaColorIndex = null),
                          child: Container(
                            width: 36,
                            height: 36,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _agendaColorIndex == null
                                    ? AppColors.brand700
                                    : AppColors.secondary200,
                                width: _agendaColorIndex == null ? 3 : 1,
                              ),
                            ),
                            child: const Icon(Icons.auto_awesome_rounded,
                                size: 16, color: AppColors.secondary400),
                          ),
                        ),
                        for (int i = 0; i < _agendaPalette.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _agendaColorIndex = i),
                            child: Container(
                              width: 36,
                              height: 36,
                              margin: const EdgeInsets.only(right: 10),
                              decoration: BoxDecoration(
                                color: _agendaPalette[i],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _agendaColorIndex == i
                                      ? AppColors.brand700
                                      : Colors.transparent,
                                  width: 3,
                                ),
                              ),
                              child: _agendaColorIndex == i
                                  ? const Icon(Icons.check_rounded,
                                      size: 18, color: Colors.black54)
                                  : null,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
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

  Widget _categoryChip(String label, bool selected, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.brand600 : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? AppColors.brand600 : AppColors.secondary200,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : AppColors.brand950,
            ),
          ),
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
                onTap: widget.salon == null || widget.isGerant
                    ? null
                    : () => showTeamMemberDetailSheet(
                          context,
                          member: m,
                          salon: widget.salon!,
                          onEdit: () => widget.onEditMember(m),
                          onDelete: () => widget.onDeleteMember(m),
                        ),
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
