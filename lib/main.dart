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
import 'screens/owner_onboarding_plan_screen.dart';
import 'screens/owner_onboarding_step2_screen.dart';
import 'screens/owner_onboarding_step3_screen.dart';
import 'screens/owner_onboarding_step5_screen.dart';
import 'services/onboarding_progress.dart';
import 'screens/team_profile_selector_screen.dart';
import 'services/fb_events_service.dart';
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
  await initializeDateFormatting('es_ES', null);
  await initializeDateFormatting('ar', null);

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

  // Facebook App Events — install + activation tracking for Meta Ads
  // campaigns. iOS ATT prompt is deferred to after first frame (see
  // _MonSalonProAppState.initState) because requesting ATT before the
  // app is in `UIApplicationStateActive` causes iOS to silently deny
  // without showing any UI.

  runApp(const ProviderScope(child: MonSalonProApp()));
}

class MonSalonProApp extends ConsumerStatefulWidget {
  const MonSalonProApp({super.key});

  @override
  ConsumerState<MonSalonProApp> createState() => _MonSalonProAppState();
}

class _MonSalonProAppState extends ConsumerState<MonSalonProApp> {
  // Memoize the force-update check Future so it's evaluated once per app
  // launch instead of on every build. Without this, any rebuild of MyApp
  // (e.g. ownerSalonProvider re-emit during a Firestore optimistic write)
  // creates a new Future, the FutureBuilder transitions back to waiting,
  // and the entire MainAppScaffold subtree is unmounted/remounted with
  // fresh State — which silently sent the user back to the Home tab from
  // wherever they were.
  late final Future<bool> _needsForceUpdate = VersionService.needsForceUpdate();

  @override
  void initState() {
    super.initState();
    // Defer FB SDK init until the app is on screen and active. Calling
    // ATT before the app reaches UIApplicationStateActive causes iOS to
    // silently deny the request without ever showing the system prompt.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Small delay so the notification permission prompt (which is
      // requested earlier) has time to settle before we stack ATT on top.
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      try {
        await FbEventsService.initialize();
      } catch (_) {}
    });
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final locale = ref.watch(localeProvider);

    // Reset profile selection on every new login (auth state null → user)
    // and sync RevenueCat subscriber identity with the Firebase UID so the
    // webhook can map purchases to `salons/{uid}` server-side.
    ref.listen(authStateProvider, (previous, next) {
      final prevUser = previous?.value;
      final nextUser = next.value;
      if (prevUser == null && nextUser != null) {
        // Open straight on the owner home (employees log in via their own
        // account now). The selector only appears when the owner taps the
        // profile-switcher button, which flips this back to false.
        ref.read(profileSelectedProvider.notifier).state = true;
        ref.read(activeTeamMemberProvider.notifier).state = null;
        // Drop any cached `null` from a previous orphan-user session.
        // userModelAsync.when uses skipLoadingOnReload, so without this
        // invalidate the new login briefly keeps the previous `null`,
        // which triggers the orphan-signout branch and bounces the user
        // back to LoginScreen.
        ref.invalidate(userModelProvider);
        RevenueCatService.loginUser(nextUser.uid);
        FbEventsService.setUserId(nextUser.uid);
      } else if (prevUser != null && nextUser == null) {
        RevenueCatService.logoutUser();
        FbEventsService.setUserId(null);
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
        future: _needsForceUpdate,
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
          //
          // CRITICAL: wait for the FutureProvider to settle for the current
          // user before deciding the route. Without this, when a new
          // employee signs in via custom token, employeeSessionProvider
          // briefly transitions through isLoading with .value == null;
          // the router would fall through to userModelProvider, which
          // tries to load users/{emp_X_Y}, fails after 9s of retries,
          // and the orphan-auth branch below force-signs-out the user —
          // making employee login appear broken right after owner logout.
          final employeeAsync = ref.watch(employeeSessionProvider);
          if (employeeAsync.isLoading) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(color: AppColors.brand600),
              ),
            );
          }
          final employeeSession = employeeAsync.value;
          if (employeeSession != null) {
            return _EmployeeHome(session: employeeSession);
          }

          final userModelAsync = ref.watch(userModelProvider);
          return userModelAsync.when(
            // Keep showing the current MainAppScaffold during reloads —
            // otherwise an authStateChanges re-emit (triggered by Android
            // activity pause/resume during long awaits like gallery image
            // upload/delete) re-evaluates userModelProvider, transitions to
            // loading, swaps the body for Scaffold(loading), and unmounts
            // MainAppScaffold. The remount resets `_currentIndex` to 0 so
            // the user is sent back to the Home tab from wherever they were.
            skipLoadingOnReload: true,
            data: (model) {
              if (model == null) {
                // Employees have no `users/{uid}` doc by design — their
                // identity lives in their custom claims + the team member
                // doc. If the auth user's uid starts with `emp_`, the
                // employee claim is still propagating (token refresh in
                // flight inside `employeeSessionProvider`). Show a spinner
                // instead of triggering signOut, otherwise we'd kick the
                // freshly-signed-in employee right back to the LoginScreen.
                if (user.uid.startsWith('emp_')) {
                  return const Scaffold(
                    body: Center(
                      child: CircularProgressIndicator(color: AppColors.brand600),
                    ),
                  );
                }
                // Orphan auth user — `users/{uid}` doesn't exist after the
                // 3-retry / 9s wait inside userModelProvider. Sign out
                // immediately so the user lands cleanly on the login screen
                // instead of staring at "Profil introuvable" for 3 more secs.
                Future.microtask(() {
                  if (ref.read(authStateProvider).value != null) {
                    signOutAll(ref);
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
                  // Same rationale as userModelAsync above — `ref.invalidate(
                  // ownerSalonProvider)` (cover photo update) re-runs the
                  // stream and would otherwise unmount MainAppScaffold during
                  // the brief loading state, losing tab position.
                  skipLoadingOnReload: true,
                  data: (salon) {
                    if (salon == null) {
                      // No salon → resume the onboarding flow. Read the saved
                      // draft so the owner lands on the step they left off at,
                      // with their data re-filled. Falls back to step 1.
                      final draftAsync = ref.watch(onboardingDraftProvider);
                      return draftAsync.when(
                        skipLoadingOnReload: true,
                        loading: () => const Scaffold(
                          body: Center(
                            child: CircularProgressIndicator(
                                color: AppColors.brand600),
                          ),
                        ),
                        error: (_, __) => const OwnerOnboardingStep1Screen(),
                        data: (draft) {
                          if (draft == null) {
                            return const OwnerOnboardingStep1Screen();
                          }
                          final step = (draft['step'] as num?)?.toInt() ?? 1;
                          final data = (draft['data'] is Map)
                              ? Map<String, dynamic>.from(draft['data'] as Map)
                              : null;
                          final step1Raw = (draft['step1Raw'] is Map)
                              ? Map<String, dynamic>.from(
                                  draft['step1Raw'] as Map)
                              : null;
                          if (data != null) {
                            if (step == 2) {
                              return OwnerOnboardingPlanScreen(salonData: data);
                            }
                            if (step == 3) {
                              return OwnerOnboardingStep2Screen(salonData: data);
                            }
                            if (step == 4) {
                              return OwnerOnboardingStep3Screen(salonData: data);
                            }
                            if (step >= 5) {
                              return OwnerOnboardingStep5Screen(salonData: data);
                            }
                          }
                          return OwnerOnboardingStep1Screen(
                              initialData: step1Raw);
                        },
                      );
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
                        onPressed: () => signOutAll(ref),
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
    // The team-member doc is the source of truth for revocation. The
    // owner's UserModel (`users/{ownerUid}`) is ONLY needed when the
    // employee is a `gerant` and we render `MainAppScaffold` — a `member`
    // routes to `MemberHomeScreen` and doesn't need it. We used to fetch
    // both in parallel, but since the `users` rule was tightened to only
    // allow self-read (2026-05-27), an employee can no longer read the
    // owner's user doc — that would short-circuit to the "revoked" branch
    // for every employee, even active ones. Fetch the member first; only
    // fetch the owner's UserModel when actually needed.
    return FutureBuilder<TeamMemberModel?>(
      future: TeamMembersRepo.fetchOne(session.salonId, session.memberId),
      builder: (context, memberSnap) {
        if (memberSnap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator(color: AppColors.brand600)),
          );
        }
        final member = memberSnap.data;
        if (member == null) {
          // Team member doc gone — owner deleted the employee. Real revocation.
          Future.microtask(() => signOutAll(ref));
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
        // Gerant path — needs the owner's UserModel for the dashboard.
        // The rule denies cross-user reads, so this is best-effort and
        // depends on either a future rule relaxation for in-salon employees
        // or a CF-backed fetch. For now, surface a clear error if it fails.
        return FutureBuilder<UserModel?>(
          future: AuthService().getUserModel(session.salonId),
          builder: (context, ownerSnap) {
            if (ownerSnap.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator(color: AppColors.brand600)),
              );
            }
            final ownerModel = ownerSnap.data;
            if (ownerModel == null) {
              Future.microtask(() => signOutAll(ref));
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
            return MainAppScaffold(userModel: ownerModel);
          },
        );
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
