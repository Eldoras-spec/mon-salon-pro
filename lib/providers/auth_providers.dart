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
final userStreamProvider = StreamProvider<UserModel?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);
  return DatabaseService().getUserStream(user.uid);
});

/// Provider to check if the current user is a Client.
final isClientProvider = Provider<bool>((ref) {
  final userModel = ref.watch(userModelProvider).value;
  return userModel?.userType == UserType.client;
});
