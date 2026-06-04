import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user_model.dart';
import 'messaging_providers.dart';
import 'owner_providers.dart';
import 'owner_tasks_provider.dart';
import 'team_providers.dart';

/// Provider for the [AuthService] instance.
final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// Provider that listens to Firebase Auth state changes.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.authStateChanges();
});

/// Provider for the current [UserModel] from Firestore.
/// It automatically updates whenever the [authStateProvider] changes.
/// Retries up to 3 times to handle the race condition where Firebase Auth
/// fires its state change before the Firestore user document is written
/// (e.g., during registration).
final userModelProvider = FutureProvider<UserModel?>((ref) async {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;

  // Force fresh ID-token before the first Firestore read — without this,
  // a `users/{newUid}` read right after switching accounts can attach
  // with a stale token and the server returns PERMISSION_DENIED.
  try { await user.getIdToken(); } catch (_) {}

  final authService = ref.read(authServiceProvider);

  for (int attempt = 0; attempt < 3; attempt++) {
    if (attempt > 0) await Future.delayed(const Duration(seconds: 3));
    final model = await authService.getUserModel(user.uid);
    if (model != null) return model;
  }

  return null; // Profile genuinely not found after 3 attempts
});

/// Live stream of the current user document — updates automatically when
/// Firestore data changes (e.g. favorites, profile edits).
///
/// When logged in via employee code, there's no `users/{uid}` doc. Instead
/// we synthesise a [UserModel] from the team member document so screens
/// that expect a UserModel (profile tab, etc.) still render correctly.
///
/// Async-generator on purpose: when transitioning between accounts (sign-out
/// of A then sign-in as B), `authStateProvider` flips uid before the Firebase
/// Auth ID-token has propagated through FlutterFire's Firestore channel. The
/// listener then attaches with a stale/null token and the server returns
/// PERMISSION_DENIED on `users/{newUid}` (rule: `request.auth.uid == userId`).
/// Awaiting `user.getIdToken()` forces the SDK to resolve a fresh token before
/// the Firestore snapshot subscription opens.
final userStreamProvider = StreamProvider<UserModel?>((ref) async* {
  final employee = ref.watch(employeeSessionProvider).value;
  if (employee != null) {
    yield* FirebaseFirestore.instance
        .collection('salons')
        .doc(employee.salonId)
        .collection('teamMembers')
        .doc(employee.memberId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      final data = snap.data() ?? {};
      return UserModel(
        id: employee.memberId,
        email: '',
        fullName: (data['name'] as String?) ?? '',
        whatsapp: (data['whatsapp'] as String?) ?? (data['phone'] as String?) ?? '',
        city: '',
        userType: UserType.owner,
        profileImageUrl: data['photoUrl'] as String?,
        fcmToken: data['fcmToken'] as String?,
        whatsappVerified: true,
        createdAt: (data['createdAt'] is Timestamp)
            ? (data['createdAt'] as Timestamp).toDate()
            : DateTime.now(),
      );
    });
    return;
  }
  final user = ref.watch(authStateProvider).value;
  if (user == null) {
    yield null;
    return;
  }
  try { await user.getIdToken(); } catch (_) { /* best-effort */ }
  yield* DatabaseService().getUserStream(user.uid);
});

/// Provider to check if the current user is a Client.
final isClientProvider = Provider<bool>((ref) {
  final userModel = ref.watch(userModelProvider).value;
  return userModel?.userType == UserType.client;
});

/// An authenticated employee session — populated when the current Firebase
/// Auth user has an `employee` custom claim (signed in via code).
class EmployeeSession {
  final String salonId;
  final String memberId;
  final String role; // 'member' | 'gerant'
  final String? name;

  const EmployeeSession({
    required this.salonId,
    required this.memberId,
    required this.role,
    this.name,
  });
}

/// Provider that reads the current auth user's custom claims and, if
/// `employee == true`, exposes the employee context. Null for owners / logged-out.
final employeeSessionProvider = FutureProvider<EmployeeSession?>((ref) async {
  // Watch authStateProvider so this re-evaluates on every auth flip, but
  // read FirebaseAuth.instance.currentUser directly to dodge a race where
  // the StreamProvider's `.value` lags behind the actual auth state right
  // after signInWithCustomToken (the stream emit is async, currentUser is
  // synchronous and reflects the latest state).
  ref.watch(authStateProvider);
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  try {
    final tokenResult = await user.getIdTokenResult();
    final claims = tokenResult.claims;
    if (claims == null || claims['employee'] != true) return null;
    final salonId = claims['salonId'] as String?;
    final memberId = claims['memberId'] as String?;
    if (salonId == null || memberId == null) return null;
    return EmployeeSession(
      salonId: salonId,
      memberId: memberId,
      role: (claims['role'] as String?) ?? 'member',
    );
  } catch (_) {
    return null;
  }
});

/// Full signOut: signs out of FirebaseAuth, clears caches, invalidates
/// all auth-derived providers, and resets the team profile selector
/// state. Use this anywhere a user transitions to "logged out" so the
/// next sign-in (owner OR employee) starts from a clean slate.
///
/// Without this, signing out then signing in as the other auth mode
/// (e.g. owner → employee code) leaves stale FutureProvider values
/// and stale StateProvider state, which can either route the new user
/// to the wrong home or trigger the orphan-auth branch in main.dart
/// and force-sign-out the new session ~9s after login.
Future<void> signOutAll(WidgetRef ref) async {
  await ref.read(authServiceProvider).signOut();
  ref.invalidate(authStateProvider);
  ref.invalidate(userModelProvider);
  ref.invalidate(userStreamProvider);
  ref.invalidate(employeeSessionProvider);
  invalidateOwnerScopedProviders(ref);
  ref.read(activeTeamMemberProvider.notifier).state = null;
  ref.read(profileSelectedProvider.notifier).state = false;
}

/// Tear down every non-autoDispose owner-scoped provider. They keep their
/// Firestore subscription alive even after the owner main scaffold unmounts
/// (Riverpod 2 default behavior), so when the auth state flips (sign-out,
/// switch to employee), those listeners keep firing under the new auth and
/// flood the logs with PERMISSION_DENIED. Call this on every sign-out and
/// before signing in as an employee.
void invalidateOwnerScopedProviders(WidgetRef ref) {
  ref.invalidate(currentSalonIdProvider);
  ref.invalidate(ownerSalonProvider);
  ref.invalidate(ownerAppointmentsProvider);
  ref.invalidate(ownerHomeAppointmentsProvider);
  ref.invalidate(ownerNoShowWindowAppointmentsProvider);
  ref.invalidate(ownerCurrentMonthAppointmentsProvider);
  ref.invalidate(ownerInventoryProvider);
  ref.invalidate(ownerPromotionsProvider);
  ref.invalidate(ownerTeamProvider);
  ref.invalidate(ownerBeforeAfterProvider);
  ref.invalidate(ownerProductsProvider);
  ref.invalidate(ownerOrdersProvider);
  ref.invalidate(ownerCurrentMonthRevenueProvider);
  ref.invalidate(ownerCurrentMonthCompletedCountProvider);
  ref.invalidate(ownerStatisticsAppointmentsProvider);
  ref.invalidate(ownerClientSummariesProvider);
  ref.invalidate(unreadMessagesCountProvider);
  ref.invalidate(badReviewsCountProvider);
  ref.invalidate(pendingRewardsCountProvider);
  ref.invalidate(noShowRiskClientsProvider);
  ref.invalidate(agendaRiskClientsProvider);
  ref.invalidate(ownerConversationsProvider);
}
