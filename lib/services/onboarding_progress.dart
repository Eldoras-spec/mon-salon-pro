import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Persists onboarding progress on `users/{uid}.onboardingProgress` so an
/// owner who quits mid-onboarding **resumes where they left off**, and so we
/// can see **where signups drop off** (the same field is the funnel signal —
/// query users without a salon by `onboardingProgress.step`).
///
/// Shape written under `onboardingProgress`:
///   step      — int, screen to resume at (see step numbers below)
///   stepName  — string label for console readability
///   data      — accumulated salonData map (steps 2+)
///   step1Raw  — raw step-1 fields, to re-fill the form
///   updatedAt — server timestamp
///
/// Step numbers: 1=Détails, 2=Plan, 3=Photos, 4=Horaires, 5=Équipe,
/// 6=Services. Resume caps at 5 (Équipe) so team members reload from
/// Firestore before the final Services step.
class OnboardingProgress {
  static const String field = 'onboardingProgress';

  static Future<void> save({
    required int step,
    required String stepName,
    Map<String, dynamic>? data,
    Map<String, dynamic>? step1Raw,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final payload = <String, dynamic>{
      'step': step,
      'stepName': stepName,
      'updatedAt': FieldValue.serverTimestamp(),
      'data': ?data,
      'step1Raw': ?step1Raw,
    };
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({field: payload}, SetOptions(merge: true));
    } catch (_) {/* best effort — never block onboarding */}
  }

  static Future<Map<String, dynamic>?> load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final raw = snap.data()?[field];
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .set({field: FieldValue.delete()}, SetOptions(merge: true));
    } catch (_) {/* best effort */}
  }
}

/// One-shot read of the saved onboarding draft for the current owner.
/// Used by the auth gate (main.dart) to decide which onboarding step to
/// resume at when the owner has no salon yet.
final onboardingDraftProvider =
    FutureProvider.autoDispose<Map<String, dynamic>?>(
  (ref) => OnboardingProgress.load(),
);
