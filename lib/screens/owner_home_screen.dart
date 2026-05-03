import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';
import '../models/appointment_model.dart';
import '../models/salon_model.dart';
import '../models/team_member_model.dart';
import '../providers/auth_providers.dart';
import '../providers/owner_providers.dart';
import '../providers/team_providers.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../services/app_localizations.dart';
import '../services/message_service.dart';
import '../utils/currency_helper.dart';
import 'owner_subscription_screen.dart';
import 'conversations_screen.dart';
import '../widgets/owner_tasks_card.dart';
import '../widgets/owner_setup_card.dart';
import '../providers/owner_tasks_provider.dart';
import '../providers/setup_tasks_provider.dart';

class OwnerHomeScreen extends ConsumerWidget {
  const OwnerHomeScreen({super.key});

  static bool _isOpen(Map<String, dynamic> hours) {
    const dayNames = [
      'lundi', 'mardi', 'mercredi', 'jeudi',
      'vendredi', 'samedi', 'dimanche',
    ];
    final now = DateTime.now();
    final dayData = hours[dayNames[now.weekday - 1]] as Map<String, dynamic>?;
    if (dayData == null || dayData['isOpen'] != true) return false;
    try {
      final op = (dayData['open'] as String).split(':');
      final cl = (dayData['close'] as String).split(':');
      final nowMin = now.hour * 60 + now.minute;
      final openMin = int.parse(op[0]) * 60 + int.parse(op[1]);
      final closeMin = int.parse(cl[0]) * 60 + int.parse(cl[1]);
      return nowMin >= openMin && nowMin < closeMin;
    } catch (_) {
      return false;
    }
  }

  static bool _isToday(DateTime dt) {
    final n = DateTime.now();
    return dt.year == n.year && dt.month == n.month && dt.day == n.day;
  }

  // Show the trial reminder UI when the salon is on Essentiel, still
  // inside trial, and within 7 days of expiry.
  static bool _shouldShowTrialBanner(SalonModel salon) {
    if (!salon.isEssentiel) return false;
    final end = salon.trialEndsAt;
    if (end == null) return false;
    final now = DateTime.now();
    if (end.isBefore(now)) return false;
    return end.difference(now).inDays <= 7;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(userModelProvider);
    final salonAsync = ref.watch(ownerSalonProvider);
    // Bounded last-7d + next-7d window — covers today's RDV, current
    // week stats and the recent-5 widget without scanning lifetime
    // appointments (saves N reads per dashboard open).
    final appointmentsAsync = ref.watch(ownerHomeAppointmentsProvider);
    final activeMember = ref.watch(activeTeamMemberProvider);

    return Scaffold(
      backgroundColor: AppColors.secondary50,
      body: userAsync.when(
        loading: () =>
            const Center(child: CircularProgressIndicator(color: AppColors.brand600)),
        error: (e, _) => Center(child: Text((AppLocalizations.of(context)?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e'))),
        data: (user) {
          final l = AppLocalizations.of(context);
          final userName = activeMember?.name ?? user?.fullName ?? (l?.tr('home_owner') ?? 'Propriétaire');
          final salon = salonAsync.value;
          final appointments = appointmentsAsync.value ?? [];

          final todayUpcoming = appointments
              .where((a) => _isToday(a.dateTime) && a.status == 'upcoming')
              .toList()
            ..sort((a, b) => a.dateTime.compareTo(b.dateTime));

          // Current-month revenue + completed count come from dedicated
          // server-side providers (see ownerCurrentMonth* providers).

          final recentAll = appointments.take(5).toList();

          // Weekly stats
          final now = DateTime.now();
          final weekStart = now.subtract(Duration(days: now.weekday - 1));
          final weekDayCounts = List.filled(7, 0);
          final weekDayRevenue = List.filled(7, 0.0);
          for (final a in appointments) {
            final diff = a.dateTime
                .difference(DateTime(
                    weekStart.year, weekStart.month, weekStart.day))
                .inDays;
            if (diff >= 0 && diff < 7) {
              weekDayCounts[diff]++;
              if (a.status == 'completed') weekDayRevenue[diff] += a.price;
            }
          }
          final weekRevenue =
              weekDayRevenue.fold<double>(0, (s, v) => s + v);
          final weekTotal =
              weekDayCounts.fold<int>(0, (s, v) => s + v);

          return RefreshIndicator(
            color: AppColors.brand600,
            onRefresh: () async {
              ref.invalidate(ownerSalonProvider);
              ref.invalidate(ownerHomeAppointmentsProvider);
              await Future.delayed(const Duration(milliseconds: 500));
            },
            child: CustomScrollView(
              slivers: [
                // ── Gradient header ────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          AppColors.brand900,
                          AppColors.brand700,
                          AppColors.brand600,
                        ],
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(0),
                        bottomRight: Radius.circular(0),
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Top row: title + actions
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l?.tr('home_hello') ?? 'Bonjour,',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.white
                                              .withValues(alpha: 0.7),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        userName,
                                        style: GoogleFonts.dmSans(
                                          fontSize: 24,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Profile switch — hidden when logged in via
                                // employee code (no other profile to switch to).
                                if (ref.watch(employeeSessionProvider).value == null) ...[
                                  GestureDetector(
                                    onTap: () {
                                      ref
                                          .read(activeTeamMemberProvider.notifier)
                                          .state = null;
                                      ref
                                          .read(profileSelectedProvider.notifier)
                                          .state = false;
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                          Icons.swap_horiz_rounded,
                                          size: 20,
                                          color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                // Security & Account
                                // Messages shortcut with unread badge
                                GestureDetector(
                                  onTap: () {
                                    final uid = ref.read(authStateProvider).value?.uid ?? '';
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => ConversationsScreen(
                                        currentUserId: uid,
                                        isClient: false,
                                        salonId: salon?.id,
                                      ),
                                    ));
                                  },
                                  child: StreamBuilder<QuerySnapshot>(
                                    stream: salon != null
                                        ? FirebaseFirestore.instance
                                            .collection('conversations')
                                            .where('salonId', isEqualTo: salon.id)
                                            .where('unreadByOwner', isGreaterThan: 0)
                                            .snapshots()
                                        : const Stream.empty(),
                                    builder: (context, snap) {
                                      final unreadCount = snap.data?.docs.length ?? 0;
                                      return Stack(
                                        clipBehavior: Clip.none,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(alpha: 0.15),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                                CupertinoIcons.chat_bubble_text_fill,
                                                size: 18,
                                                color: Colors.white),
                                          ),
                                          if (unreadCount > 0)
                                            Positioned(
                                              top: -4, right: -4,
                                              child: Container(
                                                padding: const EdgeInsets.all(4),
                                                decoration: const BoxDecoration(
                                                  color: Colors.red,
                                                  shape: BoxShape.circle,
                                                ),
                                                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                                                child: Text(
                                                  '$unreadCount',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ),
                                            ),
                                        ],
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                // Logout
                                GestureDetector(
                                  onTap: () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        backgroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(16)),
                                        title: Text(l?.tr('home_logout_title') ?? 'Déconnexion'),
                                        content: Text(
                                            l?.tr('home_logout_message') ?? 'Êtes-vous sûr de vouloir vous déconnecter ?'),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, false),
                                            child: Text(l?.tr('common_cancel') ?? 'Annuler'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(ctx, true),
                                            child: Text(l?.tr('profile_sign_out') ?? 'Se déconnecter',
                                                style: const TextStyle(
                                                    color: Colors.red)),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    await ref
                                        .read(authServiceProvider)
                                        .signOut();
                                    ref.invalidate(authStateProvider);
                                    ref.invalidate(userModelProvider);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color:
                                          Colors.white.withValues(alpha: 0.15),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                        Icons.power_settings_new_rounded,
                                        size: 18,
                                        color: Colors.white),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 6),
                            Text(
                              DateFormat("EEEE d MMMM yyyy", 'fr_FR')
                                  .format(DateTime.now()),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                            ),

                            const SizedBox(height: 20),

                            // ── Quick stats row ────────────────────────────
                            Row(
                              children: [
                                _GlassStat(
                                  value: appointmentsAsync.isLoading
                                      ? '…'
                                      : '${todayUpcoming.length}',
                                  label: l?.tr('home_today') ?? "Aujourd'hui",
                                  icon: Icons.calendar_today_rounded,
                                ),
                                const SizedBox(width: 10),
                                Consumer(
                                  builder: (context, ref, _) {
                                    final countAsync = ref.watch(
                                        ownerCurrentMonthCompletedCountProvider);
                                    return _GlassStat(
                                      value: countAsync.isLoading
                                          ? '…'
                                          : '${countAsync.value ?? 0}',
                                      label: l?.tr('home_completed_month') ??
                                          'Terminés ce mois',
                                      icon: Icons.check_circle_outline_rounded,
                                    );
                                  },
                                ),
                                const SizedBox(width: 10),
                                _GlassStat(
                                  value: salon?.rating != null
                                      ? salon!.rating.toStringAsFixed(1)
                                      : '—',
                                  label: l?.tr('home_rating') ?? 'Note',
                                  icon: Icons.star_rounded,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // ── Body ──────────────────────────────────────────────────
                SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Side-effect widget: checks trial countdown and pops
                      // a reminder dialog at most once per day during the
                      // last 7 days of Essentiel trial. Renders nothing.
                      if (salon != null) _TrialReminderWatcher(salon: salon),

                      const SizedBox(height: 16),

                      // ── Trial ends soon banner (≤ 7 days) ─────────────
                      // Persistent inline reminder — the popup above fires
                      // only once per day, the banner is always visible.
                      if (salon != null && _shouldShowTrialBanner(salon)) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _TrialEndingSoonBanner(salon: salon),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // ── Free team cap banners ─────────────────────────
                      // Either a countdown banner during the 30-day grace
                      // period, or a post-grace banner showing how many
                      // members were deactivated. Both send to the upgrade
                      // screen. Owner only — gerants/members don't see them.
                      if (salon != null && activeMember?.role != 'gerant')
                        Consumer(
                          builder: (context, ref, _) {
                            final team = ref.watch(ownerTeamProvider).value
                                ?? const <TeamMemberModel>[];
                            final now = DateTime.now();
                            final graceEnd = salon.freeCapGraceEndsAt;
                            final inGrace = salon.isFree &&
                                graceEnd != null &&
                                now.isBefore(graceEnd) &&
                                team.length > 2;
                            final deactivatedCount = team
                                .where((m) => m.isDeactivatedByCap)
                                .length;
                            if (inGrace) {
                              return Column(children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: _TeamCapGraceBanner(
                                    graceEnd: graceEnd,
                                    teamCount: team.length,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ]);
                            }
                            if (salon.isFree && deactivatedCount > 0) {
                              return Column(children: [
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20),
                                  child: _TeamCapDeactivatedBanner(
                                    deactivatedCount: deactivatedCount,
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ]);
                            }
                            return const SizedBox.shrink();
                          },
                        ),

                      // ── Salon web link ─────────────────────────────────
                      if (salon != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _SalonLinkCard(salon: salon),
                        ),
                      if (salon != null) const SizedBox(height: 16),

                      // Setup card — owner only. Gerants don't need the
                      // onboarding tasks (salon setup is owner's responsibility).
                      if (activeMember?.role != 'gerant') ...[
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: OwnerSetupCard(),
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final hasSetup =
                                ref.watch(setupTasksProvider).isNotEmpty;
                            return SizedBox(height: hasSetup ? 16 : 0);
                          },
                        ),
                      ],

                      // Tasks to do (hidden when empty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20),
                        child: OwnerTasksCard(),
                      ),
                      Consumer(
                        builder: (context, ref, _) {
                          final hasTasks =
                              ref.watch(ownerTasksProvider).isNotEmpty;
                          return SizedBox(height: hasTasks ? 16 : 0);
                        },
                      ),

                      // Revenue card (current month)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Consumer(
                          builder: (context, ref, _) {
                            final revenueAsync =
                                ref.watch(ownerCurrentMonthRevenueProvider);
                            return _RevenueCard(
                              monthlyRevenue: revenueAsync.value ?? 0,
                              salon: salon,
                              loading: revenueAsync.isLoading,
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Weekly chart ─────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _WeeklyChart(
                          dayCounts: weekDayCounts,
                          weekTotal: weekTotal,
                          weekRevenue: weekRevenue,
                          currency: salon?.currency ?? 'MAD',
                        ),
                      ),

                      const SizedBox(height: 20),

                      // ── AI Summary (hidden for new salons with no appointments) ──
                      if (salon != null && appointments.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _AISummaryCard(salonId: salon.id),
                        ),
                      if (salon != null && appointments.isNotEmpty) const SizedBox(height: 20),

                      // ── Messages ─────────────────────────────────────────
                      if (salon != null && user != null)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: _MessagesWidget(
                            salonId: salon.id,
                            ownerId: user.id,
                          ),
                        ),
                      if (salon != null && user != null)
                        const SizedBox(height: 20),

                      // ── Today's appointments ────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _SectionHeader(
                          title: l?.tr('home_today_appointments') ?? "Rendez-vous d'aujourd'hui",
                          count: todayUpcoming.length,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (appointmentsAsync.isLoading)
                        const _LoadingCard()
                      else if (todayUpcoming.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyCard(
                            icon: Icons.calendar_today_outlined,
                            message:
                                l?.tr('home_no_appointments_today') ?? "Aucun rendez-vous prévu aujourd'hui",
                          ),
                        )
                      else
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                children: todayUpcoming
                                    .map((a) => _AppointmentCard(
                                        appointment: a,
                                        showDate: false,
                                        currency: salon?.currency ?? 'MAD'))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 24),

                      // ── Recent appointments ─────────────────────────────
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child:
                            _SectionHeader(title: l?.tr('home_recent_appointments') ?? 'Rendez-vous récents'),
                      ),
                      const SizedBox(height: 12),
                      if (appointmentsAsync.isLoading)
                        const _LoadingCard()
                      else if (recentAll.isEmpty)
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: _EmptyCard(
                            icon: Icons.history_rounded,
                            message:
                                l?.tr('home_no_appointments_yet') ?? "Aucun rendez-vous pour l'instant",
                          ),
                        )
                      else
                        Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 20),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black
                                      .withValues(alpha: 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: Column(
                                children: recentAll
                                    .map((a) => _AppointmentCard(
                                        appointment: a,
                                        showDate: true,
                                        currency: salon?.currency ?? 'MAD'))
                                    .toList(),
                              ),
                            ),
                          ),
                        ),

                      const SizedBox(height: 28),

                      // ── Add-on services (premium Mon Salon offerings) ───
                      const _AddOnServicesSection(),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─── Add-on services section ─────────────────────────────────────────────────
//
// Horizontal carousel of premium services offered by Mon Salon to salon owners.
// Each tap opens WhatsApp on +212 663 32 24 29 with a pre-filled message
// identifying which service the owner is interested in.

class _AddOnServicesSection extends StatelessWidget {
  const _AddOnServicesSection();

  static const String _phone = '212663322429';

  Future<void> _open(String message) async {
    final url = Uri.parse(
      'https://wa.me/$_phone?text=${Uri.encodeComponent(message)}',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    final services = <_AddOnService>[
      _AddOnService(
        icon: Icons.campaign_rounded,
        gradient: const [Color(0xFF7C3AED), Color(0xFFEC4899)],
        title: l?.tr('addon_social_campaign_title') ?? 'Campagne social media',
        subtitle: l?.tr('addon_social_campaign_sub') ??
            'Instagram & TikTok clé en main',
        message: l?.tr('addon_social_campaign_msg') ??
            "Bonjour, je souhaite être accompagné pour créer une campagne publicitaire Instagram/TikTok pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.language_rounded,
        gradient: const [Color(0xFF0EA5E9), Color(0xFF06B6D4)],
        title: l?.tr('addon_custom_website_title') ?? 'Site web sur mesure',
        subtitle: l?.tr('addon_custom_website_sub') ??
            'Vitrine pro & booking intégré',
        message: l?.tr('addon_custom_website_msg') ??
            "Bonjour, je suis intéressé par la création d'un site web personnalisé pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.tune_rounded,
        gradient: const [Color(0xFF10B981), Color(0xFF84CC16)],
        title: l?.tr('addon_custom_option_title') ?? 'Option sur mesure',
        subtitle: l?.tr('addon_custom_option_sub') ??
            'Feature dédiée pour votre salon',
        message: l?.tr('addon_custom_option_msg') ??
            "Bonjour, j'aimerais discuter d'une option sur mesure pour mon salon (intégration, feature spécifique…).",
      ),
      _AddOnService(
        icon: Icons.photo_camera_rounded,
        gradient: const [Color(0xFFF59E0B), Color(0xFFEF4444)],
        title: l?.tr('addon_photo_title') ?? 'Shooting photo pro',
        subtitle: l?.tr('addon_photo_sub') ?? 'Salon, équipe & prestations',
        message: l?.tr('addon_photo_msg') ??
            "Bonjour, je souhaite faire un shooting photo professionnel de mon salon et de mes prestations.",
      ),
      _AddOnService(
        icon: Icons.movie_creation_rounded,
        gradient: const [Color(0xFFEF4444), Color(0xFFEC4899)],
        title: l?.tr('addon_video_title') ?? 'Vidéos TikTok / Reels',
        subtitle: l?.tr('addon_video_sub') ?? 'Contenu régulier viral',
        message: l?.tr('addon_video_msg') ??
            "Bonjour, je cherche un accompagnement pour créer du contenu vidéo (TikTok/Reels) pour mon salon.",
      ),
      _AddOnService(
        icon: Icons.location_on_rounded,
        gradient: const [Color(0xFF2563EB), Color(0xFF8B5CF6)],
        title: l?.tr('addon_google_seo_title') ?? 'Google & SEO local',
        subtitle: l?.tr('addon_google_seo_sub') ??
            'Fiche Google + gestion des avis',
        message: l?.tr('addon_google_seo_msg') ??
            "Bonjour, j'aimerais optimiser ma fiche Google + gérer les avis pour attirer plus de clients locaux.",
      ),
      _AddOnService(
        icon: Icons.school_rounded,
        gradient: const [Color(0xFF6366F1), Color(0xFFA855F7)],
        title: l?.tr('addon_training_title') ?? 'Formation équipe',
        subtitle: l?.tr('addon_training_sub') ??
            'Service client & techniques de vente',
        message: l?.tr('addon_training_msg') ??
            "Bonjour, je suis intéressé par une formation pour mon équipe (service client, techniques de vente).",
      ),
      _AddOnService(
        icon: Icons.palette_rounded,
        gradient: const [Color(0xFFEC4899), Color(0xFFF97316)],
        title: l?.tr('addon_branding_title') ?? 'Logo & identité visuelle',
        subtitle: l?.tr('addon_branding_sub') ??
            'Création ou rebranding complet',
        message: l?.tr('addon_branding_msg') ??
            "Bonjour, je souhaite créer/refaire le logo et l'identité visuelle de mon salon.",
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with title + subtitle
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF558148), Color(0xFF84CC16)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome_rounded,
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l?.tr('addon_section_title') ??
                          'Propulsez votre salon',
                      style: GoogleFonts.dmSans(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppColors.brand950,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l?.tr('addon_section_subtitle') ??
                          'Services premium Mon Salon',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Horizontal carousel
        SizedBox(
          height: 168,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: services.length,
            itemBuilder: (_, i) => _AddOnCard(
              service: services[i],
              onTap: () => _open(services[i].message),
            ),
          ),
        ),
      ],
    );
  }
}

class _AddOnService {
  const _AddOnService({
    required this.icon,
    required this.gradient,
    required this.title,
    required this.subtitle,
    required this.message,
  });
  final IconData icon;
  final List<Color> gradient;
  final String title;
  final String subtitle;
  final String message;
}

class _AddOnCard extends StatefulWidget {
  const _AddOnCard({required this.service, required this.onTap});
  final _AddOnService service;
  final VoidCallback onTap;

  @override
  State<_AddOnCard> createState() => _AddOnCardState();
}

class _AddOnCardState extends State<_AddOnCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final s = widget.service;
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 196,
          margin: const EdgeInsets.only(right: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: s.gradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: s.gradient.first.withValues(alpha: 0.28),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Decorative background bubble (subtle depth)
              Positioned(
                top: -24,
                right: -24,
                child: Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(s.icon, color: Colors.white, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    s.title,
                    style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.88),
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          l?.tr('addon_cta') ?? 'Discuter',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: s.gradient.last,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded,
                            size: 12, color: s.gradient.last),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Salon web link card ──────────────────────────────────────────────────────

class _SalonLinkCard extends StatefulWidget {
  const _SalonLinkCard({required this.salon});
  final SalonModel salon;

  @override
  State<_SalonLinkCard> createState() => _SalonLinkCardState();
}

class _SalonLinkCardState extends State<_SalonLinkCard> {
  String? _generatedSlug;
  bool _showBookingLink = false;

  SalonModel get salon => widget.salon;

  String get _salonUrl {
    final slug = _generatedSlug ?? salon.slug;
    if (slug != null && slug.isNotEmpty) {
      return 'https://monsalon.web.app/s/$slug';
    }
    return 'https://monsalon.web.app/salon.html?id=${salon.id}';
  }

  String get _bookingUrl {
    final slug = _generatedSlug ?? salon.slug;
    if (slug != null && slug.isNotEmpty) {
      return 'https://monsalon.web.app/booking.html?slug=$slug';
    }
    return 'https://monsalon.web.app/booking.html?id=${salon.id}';
  }

  String get _currentUrl => _showBookingLink ? _bookingUrl : _salonUrl;

  @override
  void initState() {
    super.initState();
    if (salon.slug == null || salon.slug!.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSlug());
    }
  }

  Future<void> _ensureSlug() async {
    try {
      final slug = await DatabaseService().ensureSalonSlug(
        salon.id,
        salon.name,
        salon.city,
      );
      if (mounted) setState(() => _generatedSlug = slug);
    } catch (e) {
      debugPrint('[SalonLink] ERROR generating slug: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
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
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.brand50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.link_rounded, color: AppColors.brand600, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _showBookingLink
                      ? (l?.tr('home_booking_link') ?? 'Lien de réservation')
                      : (l?.tr('home_salon_link') ?? 'Lien de votre salon'),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.secondary900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _currentUrl,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.secondary400,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Swap button
          GestureDetector(
            onTap: () => setState(() => _showBookingLink = !_showBookingLink),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.secondary50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                color: AppColors.brand600,
                size: 18,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // Copy button
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: _currentUrl));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l?.tr('home_link_copied') ?? 'Lien copié !'),
                  backgroundColor: AppColors.brand600,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  duration: const Duration(seconds: 3),
                ),
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.brand600,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                l?.tr('home_copy') ?? 'Copier',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Glass stat (header) ──────────────────────────────────────────────────────

class _GlassStat extends StatelessWidget {
  const _GlassStat({
    required this.value,
    required this.label,
    required this.icon,
  });
  final String value;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border:
              Border.all(color: Colors.white.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withValues(alpha: 0.65),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Revenue card ─────────────────────────────────────────────────────────────

class _RevenueCard extends StatelessWidget {
  const _RevenueCard({
    required this.monthlyRevenue,
    required this.salon,
    required this.loading,
  });
  final double monthlyRevenue;
  final SalonModel? salon;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final currency = salon?.currency ?? 'MAD';
    final revenueStr = monthlyRevenue >= 1000
        ? '${(monthlyRevenue / 1000).toStringAsFixed(1)}k ${CurrencyHelper.symbol(currency)}'
        : CurrencyHelper.format(monthlyRevenue, currency);

    final open =
        salon != null ? OwnerHomeScreen._isOpen(salon!.workingHours) : false;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          // Revenue
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.trending_up_rounded,
                          size: 16, color: Color(0xFF059669)),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l?.tr('home_monthly_revenue') ?? 'Revenus du mois',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.secondary500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  loading ? '…' : revenueStr,
                  style: GoogleFonts.dmSans(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand950,
                  ),
                ),
              ],
            ),
          ),

          // Salon status
          if (salon != null)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Logo
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: salon!.logoUrl != null
                      ? Image.network(
                          salon!.logoUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _placeholder(),
                        )
                      : _placeholder(),
                ),
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: open
                        ? const Color(0xFFDCFCE7)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: open
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        open ? (l?.tr('home_open') ?? 'Ouvert') : (l?.tr('home_closed') ?? 'Fermé'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: open
                              ? const Color(0xFF16A34A)
                              : const Color(0xFFDC2626),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.brand50,
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.storefront_outlined,
            color: AppColors.brand400, size: 20),
      );
}

// ── Weekly chart ─────────────────────────────────────────────────────────────

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({
    required this.dayCounts,
    required this.weekTotal,
    required this.weekRevenue,
    this.currency = 'MAD',
  });

  final List<int> dayCounts;
  final int weekTotal;
  final double weekRevenue;
  final String currency;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final maxCount = dayCounts.reduce((a, b) => a > b ? a : b);
    final todayIndex = DateTime.now().weekday - 1;

    final revenueStr = weekRevenue >= 1000
        ? '${(weekRevenue / 1000).toStringAsFixed(1)}k ${CurrencyHelper.symbol(currency)}'
        : CurrencyHelper.format(weekRevenue, currency);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Text(
                l?.tr('home_this_week') ?? 'Cette semaine',
                style: GoogleFonts.dmSans(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950,
                ),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.brand50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$weekTotal RDV',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.brand600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFD1FAE5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  revenueStr,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF059669),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // Bar chart
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(7, (i) {
              final ratio =
                  maxCount > 0 ? dayCounts[i] / maxCount : 0.0;
              final isToday = i == todayIndex;
              final barHeight = 6.0 + (ratio * 70);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (dayCounts[i] > 0)
                        Text(
                          '${dayCounts[i]}',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isToday
                                ? AppColors.brand700
                                : AppColors.secondary400,
                          ),
                        ),
                      const SizedBox(height: 4),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: barHeight,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          gradient: isToday
                              ? const LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    AppColors.brand600,
                                    AppColors.brand400,
                                  ],
                                )
                              : null,
                          color: isToday
                              ? null
                              : (dayCounts[i] > 0
                                  ? AppColors.brand100
                                  : AppColors.secondary100),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: isToday
                              ? AppColors.brand600
                              : Colors.transparent,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            _dayLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isToday
                                  ? FontWeight.bold
                                  : FontWeight.w500,
                              color: isToday
                                  ? Colors.white
                                  : AppColors.secondary400,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

// ── Appointment card ────────────────────────────────────────────────────────

class _AppointmentCard extends StatefulWidget {
  const _AppointmentCard({
    required this.appointment,
    required this.showDate,
    this.currency = 'MAD',
  });
  final AppointmentModel appointment;
  final bool showDate;
  final String currency;

  @override
  State<_AppointmentCard> createState() => _AppointmentCardState();
}

class _AppointmentCardState extends State<_AppointmentCard> {
  String _clientName = '…';

  @override
  void initState() {
    super.initState();
    final a = widget.appointment;
    final storedName = a.clientName?.trim();
    if (storedName != null && storedName.isNotEmpty) {
      _clientName = storedName;
      return;
    }
    if (a.clientId == 'walk-in') {
      _clientName = 'Client sans compte';
      return;
    }
    DatabaseService().getClientName(a.clientId).then((name) {
      if (mounted) setState(() => _clientName = name);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final a = widget.appointment;
    if (a.clientId == 'walk-in' && a.clientName == null) {
      _clientName = l?.tr('appointments_walk_in_client') ?? 'Client sans compte';
    }

    final timeStr = DateFormat('HH:mm').format(a.dateTime);
    final dateStr = widget.showDate
        ? DateFormat('d MMM', 'fr_FR').format(a.dateTime)
        : null;

    final (statusLabel, statusBg, statusFg) = switch (a.status) {
      'completed' => (
          l?.tr('appointments_status_completed') ?? 'Terminé',
          const Color(0xFFDCFCE7),
          const Color(0xFF16A34A)
        ),
      'cancelled' => (
          l?.tr('appointments_status_cancelled') ?? 'Annulé',
          const Color(0xFFFEE2E2),
          const Color(0xFFDC2626)
        ),
      _ => (l?.tr('appointments_status_upcoming') ?? 'À venir', const Color(0xFFEFF6FF), const Color(0xFF2563EB)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Color(0xFFF1F5F9), width: 1),
        ),
      ),
      child: Row(
        children: [
          // Time badge
          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: a.status == 'upcoming'
                  ? AppColors.brand50
                  : AppColors.secondary50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  timeStr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: a.status == 'upcoming'
                        ? AppColors.brand700
                        : AppColors.secondary500,
                  ),
                ),
                if (dateStr != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    dateStr,
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.secondary400,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  a.serviceName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: AppColors.brand950,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.person_outline_rounded,
                        size: 12, color: AppColors.secondary400),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _clientName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.secondary500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 8),

          // Right: price + status
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyHelper.format(a.price, widget.currency),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.brand950,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: statusFg,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Section header ──────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.count});
  final String title;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: GoogleFonts.dmSans(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: AppColors.brand950,
          ),
        ),
        if (count != null && count! > 0) ...[
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brand600,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ── Empty / Loading cards ───────────────────────────────────────────────────

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.message});
  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              color: AppColors.secondary50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 24, color: AppColors.secondary300),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
                color: AppColors.secondary400, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.symmetric(vertical: 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: CircularProgressIndicator(
            color: AppColors.brand600, strokeWidth: 2),
      ),
    );
  }
}

// ── AI Summary card ──────────────────────────────────────────────────────────

class _AISummaryCard extends StatefulWidget {
  const _AISummaryCard({required this.salonId});
  final String salonId;

  @override
  State<_AISummaryCard> createState() => _AISummaryCardState();
}

class _AISummaryCardState extends State<_AISummaryCard> {
  String? _summary;
  List<String> _noShowAlerts = [];
  List<String> _priceSuggestions = [];
  List<String> _actionSuggestions = [];
  String? _monthlyComparison;
  String? _financialInsights;
  bool _loading = false;
  bool _error = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _loadCachedOrFetch();
  }

  Future<void> _loadCachedOrFetch() async {
    setState(() { _loading = true; _error = false; });
    try {
      final doc = await FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .get();
      final data = doc.data();
      final cachedDate = data?['aiSummaryDate'] as String?;
      final today = DateTime.now().toIso8601String().substring(0, 10);

      if (!mounted) return;
      final cachedLang = data?['aiSummaryLang'] as String?;
      final currentLang = Localizations.localeOf(context).languageCode;
      if (cachedDate == today && data?['aiSummary'] != null && cachedLang == currentLang) {
        _applyCache(data!);
        return;
      }
      await _fetchFromGemini();
    } catch (e) {
      await _fetchFromGemini();
    }
  }

  void _applyCache(Map<String, dynamic> data) {
    setState(() {
      _summary = data['aiSummary'] as String?;
      _noShowAlerts = List<String>.from(data['aiNoShowAlerts'] ?? []);
      _priceSuggestions = List<String>.from(data['aiPriceSuggestions'] ?? []);
      _actionSuggestions = List<String>.from(data['aiActionSuggestions'] ?? []);
      _monthlyComparison = data['aiMonthlyComparison'] as String?;
      _financialInsights = data['aiFinancialInsights'] as String?;
      _loading = false;
    });
  }

  Future<void> _fetchFromGemini() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = false; });
    try {
      final callable = FirebaseFunctions.instance.httpsCallable(
        'generateDailySummary',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
      );
      final lang = Localizations.localeOf(context).languageCode;
      final result = await callable.call({'salonId': widget.salonId, 'lang': lang});
      if (!mounted) return;
      final data = result.data as Map<String, dynamic>;

      setState(() {
        _summary = data['summary'] as String?;
        _noShowAlerts = List<String>.from(data['noShowAlerts'] ?? []);
        _priceSuggestions = List<String>.from(data['priceSuggestions'] ?? []);
        _actionSuggestions = List<String>.from(data['actionSuggestions'] ?? []);
        _monthlyComparison = data['monthlyComparison'] as String?;
        _financialInsights = data['financialInsights'] as String?;
        _loading = false;
      });

      // Cache all sections in Firestore
      final today = DateTime.now().toIso8601String().substring(0, 10);
      FirebaseFirestore.instance
          .collection('salons')
          .doc(widget.salonId)
          .update({
        'aiSummary': _summary,
        'aiSummaryDate': today,
        'aiSummaryLang': lang,
        'aiNoShowAlerts': _noShowAlerts,
        'aiPriceSuggestions': _priceSuggestions,
        'aiActionSuggestions': _actionSuggestions,
        'aiMonthlyComparison': _monthlyComparison,
        'aiFinancialInsights': _financialInsights,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = true; });
    }
  }

  bool get _hasSections =>
      _noShowAlerts.isNotEmpty ||
      _priceSuggestions.isNotEmpty ||
      _actionSuggestions.isNotEmpty ||
      (_monthlyComparison ?? '').isNotEmpty ||
      (_financialInsights ?? '').isNotEmpty;

  bool get _isEn => Localizations.localeOf(context).languageCode == 'en';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.brand50, const Color(0xFFFFFFFF)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.brand100, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.brand100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.auto_awesome, size: 18, color: AppColors.brand600),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isEn ? 'AI Assistant' : 'Assistant IA',
                  style: GoogleFonts.dmSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.brand950,
                  ),
                ),
              ),
              if (!_loading)
                GestureDetector(
                  onTap: _fetchFromGemini,
                  child: const Icon(Icons.refresh_rounded, size: 20, color: AppColors.secondary400),
                ),
            ],
          ),
          const SizedBox(height: 14),

          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(color: AppColors.brand600, strokeWidth: 2),
                ),
              ),
            )
          else if (_error)
            GestureDetector(
              onTap: _fetchFromGemini,
              child: Text(
                _isEn ? 'Unable to generate summary. Tap to retry.' : 'Impossible de générer le résumé. Appuie pour réessayer.',
                style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: AppColors.secondary400, height: 1.5),
              ),
            )
          else if (_summary != null) ...[
            // ── Summary section ──
            _AISectionRow(
              icon: Icons.summarize_rounded,
              color: AppColors.brand600,
              text: _summary!,
            ),

            // ── No-show alerts ──
            if (_noShowAlerts.isNotEmpty) ...[
              const SizedBox(height: 14),
              _AISectionHeader(icon: Icons.warning_amber_rounded, color: const Color(0xFFEA580C), label: _isEn ? 'No-show risk' : 'Risque no-show'),
              for (final alert in _noShowAlerts)
                _AISectionRow(icon: Icons.person_off_rounded, color: const Color(0xFFEA580C), text: alert),
            ],

            // ── Expandable sections ──
            if (_hasSections && !_expanded) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isEn ? 'See more' : 'Voir plus', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: AppColors.brand600),
                  ],
                ),
              ),
            ],

            if (_expanded) ...[
              // ── Action suggestions ──
              if (_actionSuggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionHeader(icon: Icons.lightbulb_outline_rounded, color: const Color(0xFF0891B2), label: _isEn ? 'Suggestions' : 'Suggestions'),
                for (final s in _actionSuggestions)
                  _AISectionRow(icon: Icons.arrow_right_rounded, color: const Color(0xFF0891B2), text: s),
              ],

              // ── Price suggestions ──
              if (_priceSuggestions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionHeader(icon: Icons.monetization_on_outlined, color: const Color(0xFF059669), label: _isEn ? 'Price suggestions' : 'Suggestions de prix'),
                for (final s in _priceSuggestions)
                  _AISectionRow(icon: Icons.arrow_right_rounded, color: const Color(0xFF059669), text: s),
              ],

              // ── Monthly comparison ──
              if ((_monthlyComparison ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionRow(
                  icon: Icons.compare_arrows_rounded,
                  color: AppColors.brand600,
                  text: _monthlyComparison!,
                  label: _isEn ? 'Monthly comparison' : 'Comparaison mensuelle',
                ),
              ],

              // ── Financial insights ──
              if ((_financialInsights ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                _AISectionRow(
                  icon: Icons.insights_rounded,
                  color: const Color(0xFF0369A1),
                  text: _financialInsights!,
                  label: _isEn ? 'Financial insights' : 'Insights financiers',
                ),
              ],

              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => setState(() => _expanded = false),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(_isEn ? 'See less' : 'Voir moins', style: GoogleFonts.plusJakartaSans(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.brand600)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_up_rounded, size: 18, color: AppColors.brand600),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _AISectionHeader extends StatelessWidget {
  const _AISectionHeader({required this.icon, required this.color, required this.label});
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: color),
          ),
        ],
      ),
    );
  }
}

class _AISectionRow extends StatelessWidget {
  const _AISectionRow({required this.icon, required this.color, required this.text, this.label});
  final IconData icon;
  final Color color;
  final String text;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: color),
                  const SizedBox(width: 6),
                  Text(label!, style: GoogleFonts.dmSans(fontSize: 13, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label == null) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(icon, size: 14, color: color.withValues(alpha: 0.6)),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  text,
                  style: GoogleFonts.plusJakartaSans(fontSize: 13.5, color: AppColors.secondary600, height: 1.5),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Messages widget ─────────────────────────────────────────────────────────

class _MessagesWidget extends StatelessWidget {
  const _MessagesWidget({required this.salonId, required this.ownerId});
  final String salonId;
  final String ownerId;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return StreamBuilder<List<dynamic>>(
      stream: MessageService().getOwnerConversations(salonId),
      builder: (context, snap) {
        final convs = (snap.data ?? []);
        final unread = convs.fold<int>(
          0,
          (acc, c) => acc + ((c.unreadByOwner ?? 0) as int),
        );
        final hasUnread = unread > 0;
        final preview = convs.isNotEmpty ? convs.first : null;

        return GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ConversationsScreen(
                currentUserId: ownerId,
                isClient: false,
                salonId: salonId,
              ),
            ),
          ),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color:
                    hasUnread ? AppColors.brand200 : AppColors.secondary100,
                width: hasUnread ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: hasUnread
                        ? AppColors.brand50
                        : AppColors.secondary50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.chat_bubble_outline_rounded,
                    color: hasUnread
                        ? AppColors.brand600
                        : AppColors.secondary400,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l?.tr('home_messages') ?? 'Messages',
                        style: GoogleFonts.dmSans(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.brand950,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        preview != null
                            ? (preview.lastMessage as String).isNotEmpty
                                ? '${preview.clientName} : ${preview.lastMessage}'
                                : (l?.tr('home_conversations_count') ?? '{count} conversation{plural}').replaceAll('{count}', '${convs.length}').replaceAll('{plural}', convs.length > 1 ? 's' : '')
                            : l?.tr('home_no_messages_yet') ?? 'Aucun message pour l\'instant',
                        style: TextStyle(
                          fontSize: 12,
                          color: hasUnread
                              ? AppColors.secondary700
                              : AppColors.secondary400,
                          fontWeight: hasUnread
                              ? FontWeight.w500
                              : FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (hasUnread)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.brand600,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$unread',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  )
                else
                  const Icon(Icons.chevron_right_rounded,
                      color: AppColors.secondary300, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Owner Security & Account Sheet ───────────────────────────────────────────

class _OwnerSecuritySheet extends StatefulWidget {
  const _OwnerSecuritySheet({
    required this.userEmail,
    required this.onAccountDeleted,
  });
  final String userEmail;
  final VoidCallback onAccountDeleted;

  @override
  State<_OwnerSecuritySheet> createState() => _OwnerSecuritySheetState();
}

class _OwnerSecuritySheetState extends State<_OwnerSecuritySheet> {
  bool _loading = false;
  bool _sent = false;

  Future<void> _resetPassword() async {
    setState(() => _loading = true);
    try {
      await AuthService().sendPasswordResetEmail(widget.userEmail);
      if (mounted) setState(() { _sent = true; _loading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text((AppLocalizations.of(context)?.tr('common_error') ?? 'Erreur : {error}').replaceAll('{error}', '$e')), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                  color: AppColors.secondary200,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          Text(l?.tr('profile_security_title') ?? 'Sécurité',
              style: GoogleFonts.dmSans(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppColors.brand950)),
          const SizedBox(height: 20),

          // Reset password
          if (_sent) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded,
                      color: Color(0xFF16A34A), size: 20),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      (l?.tr('profile_security_reset_sent') ?? 'Un email de réinitialisation a été envoyé à {email}').replaceAll('{email}', widget.userEmail),
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF166534)),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: AppColors.secondary50,
                  borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      color: AppColors.secondary500, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      (l?.tr('profile_security_reset_hint') ?? 'Un lien de réinitialisation sera envoyé à\n{email}').replaceAll('{email}', widget.userEmail),
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.secondary600),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _loading ? null : _resetPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand600,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : Text(l?.tr('profile_security_reset_button') ?? 'Réinitialiser le mot de passe',
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15)),
              ),
            ),
          ],

        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// Trial reminder side-effect: once per day during the last 7 days
// of Essentiel trial, pops a blocking dialog asking the owner to
// upgrade before downgrade. `salon.lastTrialReminderAt` records
// the last firing so we don't spam.
// ═══════════════════════════════════════════════════════════════
class _TrialReminderWatcher extends ConsumerStatefulWidget {
  final SalonModel salon;
  const _TrialReminderWatcher({required this.salon});

  @override
  ConsumerState<_TrialReminderWatcher> createState() =>
      _TrialReminderWatcherState();
}

class _TrialReminderWatcherState
    extends ConsumerState<_TrialReminderWatcher> {
  bool _checked = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShow());
  }

  Future<void> _maybeShow() async {
    if (!mounted) return;
    final salon = widget.salon;
    if (!OwnerHomeScreen._shouldShowTrialBanner(salon)) return;

    // Fetch latest lastTrialReminderAt to avoid showing twice when the
    // home rebuilds (stream update comes after we wrote the field).
    final doc = await FirebaseFirestore.instance
        .collection('salons')
        .doc(salon.id)
        .get();
    final last = doc.data()?['lastTrialReminderAt'];
    final lastDt = last is Timestamp ? last.toDate() : null;
    if (lastDt != null && OwnerHomeScreen._isToday(lastDt)) return;
    if (!mounted) return;

    final l = AppLocalizations.of(context);
    final daysLeft =
        salon.trialEndsAt!.difference(DateTime.now()).inDays;
    final proceed = await showDialog<bool>(
      context: context,
      builder: (dCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            shape: BoxShape.circle,
          ),
          child: Icon(Icons.timer_outlined,
              color: Colors.amber.shade800, size: 28),
        ),
        title: Text(
          (l?.tr('trial_reminder_title') ??
                  'Plus que {days} jours d\'essai gratuit')
              .replaceAll('{days}', daysLeft.toString()),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        content: Text(
          l?.tr('trial_reminder_body') ??
              'Après cette date, votre salon passera automatiquement en Free (équipe limitée à 2 membres). Passez en Essentiel dès maintenant pour ne pas être interrompu.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, color: AppColors.secondary600),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx, false),
            child: Text(l?.tr('trial_reminder_later') ?? 'Plus tard'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand600,
              foregroundColor: Colors.white,
            ),
            child: Text(l?.tr('trial_reminder_manage') ??
                'Gérer mon abonnement'),
          ),
        ],
      ),
    );

    // Stamp the flag regardless of the choice — we fired once today.
    try {
      await FirebaseFirestore.instance
          .collection('salons')
          .doc(salon.id)
          .update({
        'lastTrialReminderAt': FieldValue.serverTimestamp(),
      });
    } catch (_) { /* best effort */ }

    if (proceed == true && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const OwnerSubscriptionScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ═══════════════════════════════════════════════════════════════
// Inline banner (always visible) for the last 7 days of trial.
// Complements the daily popup — user can tap "Gérer" to go to the
// subscription screen anytime without waiting for next-day reminder.
// ═══════════════════════════════════════════════════════════════
class _TrialEndingSoonBanner extends StatelessWidget {
  final SalonModel salon;
  const _TrialEndingSoonBanner({required this.salon});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daysLeft = salon.trialEndsAt!
        .difference(DateTime.now())
        .inDays;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.brand50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.brand200),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined,
              size: 22, color: AppColors.brand700),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l?.tr('trial_banner_title') ??
                          'Plus que {days}j de trial Essentiel')
                      .replaceAll('{days}', daysLeft.toString()),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.brand950),
                ),
                const SizedBox(height: 2),
                Text(
                  l?.tr('trial_banner_body') ??
                      'Passez en Essentiel pour éviter le downgrade en Free.',
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.secondary500,
                      height: 1.3),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const OwnerSubscriptionScreen(),
              ),
            ),
            child: Text(l?.tr('trial_banner_cta') ?? 'Gérer'),
          ),
        ],
      ),
    );
  }
}

// Orange warning banner shown on the owner home during the 30-day grace
// period following a downgrade to Free while the team still has >2 members.
// Displays a countdown and a CTA to the subscription screen.
class _TeamCapGraceBanner extends StatelessWidget {
  final DateTime graceEnd;
  final int teamCount;
  const _TeamCapGraceBanner({
    required this.graceEnd,
    required this.teamCount,
  });

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final daysLeft = graceEnd.difference(DateTime.now()).inDays;
    final excess = teamCount - 2;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFCD34D),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.timer_outlined,
                color: Color(0xFF92400E), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l?.tr('team_cap_grace_title') ??
                          'Plan Free : {days} jour(s) avant désactivation')
                      .replaceAll('{days}', daysLeft.toString()),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF78350F),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  (l?.tr('team_cap_grace_body') ??
                          'Équipe limitée à 2 membres sur Free. {excess} membre(s) seront désactivés à la fin du délai. Passez en Essentiel pour tout conserver.')
                      .replaceAll('{excess}', excess.toString()),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF92400E),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerSubscriptionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_upward, size: 14),
                  label: Text(
                    l?.tr('team_cap_grace_cta') ?? 'Passer en Essentiel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF92400E),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// Red banner shown on the owner home after the Free plan grace period
// expired and CF `enforceFreeTeamCap` deactivated the excess members.
// Indicates the count and pitches the upgrade to reactivate them.
class _TeamCapDeactivatedBanner extends StatelessWidget {
  final int deactivatedCount;
  const _TeamCapDeactivatedBanner({required this.deactivatedCount});

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEE2E2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFCA5A5),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.person_off_outlined,
                color: Color(0xFF7F1D1D), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (l?.tr('team_cap_deactivated_title') ??
                          '{count} membre(s) désactivé(s)')
                      .replaceAll('{count}', deactivatedCount.toString()),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7F1D1D),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l?.tr('team_cap_deactivated_body') ??
                      'Limite Free atteinte. Leurs données sont conservées. Passez en Essentiel pour les réactiver instantanément.',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFF991B1B),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const OwnerSubscriptionScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.restart_alt_rounded, size: 14),
                  label: Text(
                    l?.tr('team_cap_deactivated_cta') ??
                        'Réactiver via Essentiel',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7F1D1D),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
