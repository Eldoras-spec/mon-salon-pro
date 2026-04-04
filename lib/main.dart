import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'screens/team_profile_selector_screen.dart';
import 'services/notification_service.dart';
import 'services/version_service.dart';
import 'services/app_localizations.dart';
import 'services/locale_service.dart';
import 'screens/force_update_screen.dart';
import 'providers/auth_providers.dart';
import 'providers/team_providers.dart';
import 'providers/locale_provider.dart';
import 'models/user_model.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock to portrait only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Initialize locale data for intl date formatting
  await initializeDateFormatting('fr_FR', null);
  await initializeDateFormatting('en_US', null);

  // Register background message handler before NotificationService init
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // Initialize push notifications
  await NotificationService().initialize();

  runApp(const ProviderScope(child: MonSalonProApp()));
}

class MonSalonProApp extends ConsumerWidget {
  const MonSalonProApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);
    final locale = ref.watch(localeProvider);

    // Reset profile selection on every new login (auth state null → user)
    ref.listen(authStateProvider, (previous, next) {
      final prevUser = previous?.value;
      final nextUser = next.value;
      if (prevUser == null && nextUser != null) {
        ref.read(profileSelectedProvider.notifier).state = false;
        ref.read(activeTeamMemberProvider.notifier).state = null;
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
          final userModelAsync = ref.watch(userModelProvider);
          return userModelAsync.when(
            data: (model) {
              if (model == null) {
                Future.delayed(const Duration(seconds: 3), () {
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

              // Owner flow: team profile selector → member or owner scaffold
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
