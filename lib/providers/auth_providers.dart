import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/auth_service.dart';
import '../services/database_service.dart';
import '../models/user_model.dart';

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
final userStreamProvider = StreamProvider<UserModel?>((ref) {
  final employee = ref.watch(employeeSessionProvider).value;
  if (employee != null) {
    return FirebaseFirestore.instance
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
  }
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return DatabaseService().getUserStream(user.uid);
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
  final user = ref.watch(authStateProvider).value;
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
