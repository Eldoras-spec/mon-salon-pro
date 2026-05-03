import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'theme/app_colors.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/welcome_screen.dart';
import 'screens/main_app_scaffold.dart';
import 'screens/member_home_screen.dart';
import 'screens/owner_onboarding_step1_screen.dart';
import 'screens/team_profile_selector_screen.dart';
import 'services/notification_service.dart';
import 'services/revenue_cat_service.dart';
import 'services/version_service.dart';
import 'services/app_localizations.dart';
import 'services/locale_service.dart';
import 'screens/force_update_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/owner_providers.dart';
import 'providers/team_providers.dart';
import 'providers/locale_provider.dart';
import 'models/user_model.dart';
import 'models/team_member_model.dart';
import 'services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Allow all orientations first, then lock portrait on phones after first frame
  await SystemChrome.setPreferredOrientations(DeviceOrientation.values);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // App Check — attests requests originate from the genuine app.
  // - Debug builds use DebugProvider: prints a token on first launch that
  //   must be registered at Firebase Console → App Check → Apps → ⋮ →
  //   Manage debug tokens.
  // - Release builds use Play Integrity (Android) + DeviceCheck (iOS),
  //   both backed by OS-level attestation.
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider: kDebugMode
          ? AndroidProvider.debug
          : AndroidProvider.playIntegrity,
      appleProvider: kDebugMode
          ? AppleProvider.debug
          : AppleProvider.appAttestWithDeviceCheckFallback,
    );
  } catch (_) { /* non-fatal — monitoring only until enforcement is on */ }

  // Initialize locale data for intl date formatting
  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('en_US', null);

  // Register background message handler before NotificationService init
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize push notifications (don't block app launch if it fails)
  try {
    await NotificationService().initialize().timeout(
      const Duration(seconds: 5),
    );
  } catch (_) {}

  // RevenueCat — configure the SDK and rehydrate the current user's
  // identity. Non-fatal on failure (the app still runs, IAP will just
  // be unavailable until the next app start).
  try {
    await RevenueCatService.initialize();
    await RevenueCatService.syncCurrentUser();
  } catch (_) {}

  runApp(const ProviderScope(child: MonSalonProApp()));
}

class MonSalonProApp extends ConsumerWidget {
  const MonSalonProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final locale = ref.watch(localeProvider);

    // Reset profile selection on every new login (auth state null → user)
    // and sync RevenueCat subscriber identity with the Firebase UID so the
    // webhook can map purchases to `salons/{uid}` server-side.
    ref.listen(authStateProvider, (previous, next) {
      final prevUser = previous?.value;
      final nextUser = next.value;
      if (prevUser == null && nextUser != null) {
        ref.read(profileSelectedProvider.notifier).state = false;
        ref.read(activeTeamMemberProvider.notifier).state = null;
        RevenueCatService.loginUser(nextUser.uid);
      } else if (prevUser != null && nextUser == null) {
        RevenueCatService.logoutUser();
      }
    });

    return MaterialApp(
      title: 'Mon Salon Pro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      locale: locale,
      supportedLocales: LocaleService.supportedLocales,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: FutureBuilder<bool>(
        future: VersionService.needsForceUpdate(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.brand600),
              ),
            );
          }
          if (snapshot.data == true) {
            return const ForceUpdateScreen();
          }
          return _buildAuthHome(context, authState, ref);
        },
      ),
    );
  }

  Widget _buildOwnerHome(BuildContext context, WidgetRef ref, UserModel model) {
    final profileSelected = ref.watch(profileSelectedProvider);
    final activeMemberRole = ref.watch(
      activeTeamMemberProvider.select((m) => m?.role),
    );
    if (!profileSelected) {
      return TeamProfileSelectorScreen(userModel: model);
    }
    if (activeMemberRole == 'member') {
      return const MemberHomeScreen();
    }
    return MainAppScaffold(userModel: model);
  }

  Widget _buildAuthHome(BuildContext context, AsyncValue authState, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return authState.when(
        data: (user) {
          if (user == null) {
            return FutureBuilder<bool>(
              future: SharedPreferences.getInstance().then(
                (prefs) => prefs.getBool('has_launched_before') ?? false,
              ),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: AppColors.brand600),
                    ),
                  );
                }
                final hasLaunchedBefore = snap.data ?? false;
                if (!hasLaunchedBefore) {
                  // First launch → registration
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setBool('has_launched_before', true),
                  );
                  return const WelcomeScreen();
                }
                return const LoginScreen();
              },
            );
          }
          // Employee session check (user authenticated via code exchange).
          // Employees don't have a `users/{uid}` doc; they have custom claims
          // { employee: true, salonId, memberId, role } on their Firebase Auth token.
          final employeeAsync = ref.watch(employeeSessionProvider);
          final employeeSession = employeeAsync.value;
          if (employeeSession != null) {
            return _EmployeeHome(session: employeeSession);
          }

          final userModelAsync = ref.watch(userModelProvider);
          return userModelAsync.when(
            data: (model) {
              if (model == null) {
                // Orphan auth user — `users/{uid}` doesn't exist after the
                // 3-retry / 9s wait inside userModelProvider. Sign out
                // immediately so the user lands cleanly on the login screen
                // instead of staring at "Profil introuvable" for 3 more secs.
                Future.microtask(() {
                  if (ref.read(authStateProvider).value != null) {
                    ref.read(authServiceProvider).signOut();
                    ref.invalidate(authStateProvider);
                    ref.invalidate(userModelProvider);
                  }
                });

                return Scaffold(
                  body: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.person_off,
                          size: 60,
                          color: Colors.orange,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l?.tr('main_profile_not_found') ?? 'Profil introuvable.',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(l?.tr('main_redirecting') ?? 'Redirection vers la connexion...'),
                        const SizedBox(height: 24),
                        const CircularProgressIndicator(
                          color: AppColors.brand600,
                        ),
                      ],
                    ),
                  ),
                );
              }

              // Save FCM token for push notifications
              NotificationService().saveTokenForUser(user.uid);

              // Owners always need a salon doc to access the dashboard.
              // If `salons/{uid}` is missing, route to the onboarding flow
              // — covers both fresh signups AND the edge case where a
              // user's salon doc was deleted manually but `users/{uid}`
              // remained (orphan state). Whatsapp-verified status only
              // controls *which* onboarding step we land on, not whether
              // we route at all.
              if (model.userType == UserType.owner) {
                final salonAsync = ref.watch(ownerSalonProvider);
                return salonAsync.when(
                  data: (salon) {
                    if (salon == null) {
                      // No salon → resume onboarding from step 1. The screen
                      // handles already-verified-WhatsApp by skipping the OTP
                      // check, so it works for both fresh and orphan users.
                      return const OwnerOnboardingStep1Screen();
                    }
                    return _buildOwnerHome(context, ref, model);
                  },
                  loading: () => const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: AppColors.brand600),
                    ),
                  ),
                  error: (_, __) => _buildOwnerHome(context, ref, model),
                );
              }

              return _buildOwnerHome(context, ref, model);

            },
            loading: () => Scaffold(
              body: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: AppColors.brand600),
                    const SizedBox(height: 20),
                    Text(l?.tr('main_loading_profile') ?? 'Chargement du profil...'),
                  ],
                ),
              ),
            ),
            error: (err, stack) {
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.red,
                        size: 60,
                      ),
                      const SizedBox(height: 16),
                      Text((l?.tr('main_connection_error') ?? 'Erreur de connexion : {error}').replaceAll('{error}', err.toString())),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () => ref.invalidate(userModelProvider),
                        child: Text(l?.tr('main_retry') ?? 'Réessayer'),
                      ),
                      TextButton(
                        onPressed: () =>
                            ref.read(authServiceProvider).signOut(),
                        child: Text(l?.tr('main_logout') ?? 'Se déconnecter'),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(color: AppColors.brand600),
          ),
        ),
        error: (err, stack) {
          return Scaffold(
            body: Center(child: Text((l?.tr('main_auth_error') ?? 'Erreur d\'authentification: {error}').replaceAll('{error}', err.toString()))),
          );
        },
      );
  }
}

// ─── Employee session router ───────────────────────────────────────────
// Loads the team member doc + owner's UserModel, then routes to the
// correct screen based on role. If the team member doc is gone (owner
// deleted the member) we force a signOut.
class _EmployeeHome extends ConsumerWidget {
  const _EmployeeHome({required this.session});
  final EmployeeSession session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = AppLocalizations.of(context);
    return FutureBuilder<List<dynamic>>(
      future: Future.wait<dynamic>([
        // Owner UserModel (used by MainAppScaffold for salonId).
        AuthService().getUserModel(session.salonId),
        // Team member doc (to detect revocation + seed activeTeamMemberProvider).
        TeamMembersRepo.fetchOne(session.salonId, session.memberId),
      ]),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.brand600)),
          );
        }
        final ownerModel = snap.data?[0] as UserModel?;
        final member = snap.data?[1];
        if (ownerModel == null || member == null) {
          // Member revoked or data missing → force logout.
          Future.microtask(() async {
            await ref.read(authServiceProvider).signOut();
            ref.invalidate(authStateProvider);
            ref.invalidate(employeeSessionProvider);
          });
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l?.tr('emp_session_revoked') ??
                      'Votre accès a été retiré. Contactez votre propriétaire.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        // Seed the active member + profile selected providers so existing
        // screens (MemberHomeScreen etc.) find the current member.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ref.read(activeTeamMemberProvider) == null) {
            ref.read(activeTeamMemberProvider.notifier).state = member;
          }
          if (!ref.read(profileSelectedProvider)) {
            ref.read(profileSelectedProvider.notifier).state = true;
          }
        });

        if (session.role == 'member') {
          return const MemberHomeScreen();
        }
        return MainAppScaffold(userModel: ownerModel);
      },
    );
  }
}

// Small static helper to fetch a single team member doc without pulling
// in the whole DatabaseService graph here.
class TeamMembersRepo {
  static Future<TeamMemberModel?> fetchOne(String salonId, String memberId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('salons')
          .doc(salonId)
          .collection('teamMembers')
          .doc(memberId)
          .get();
      if (!doc.exists) return null;
      return TeamMemberModel.fromFirestore(doc);
    } catch (_) {
      return null;
    }
  }
}
