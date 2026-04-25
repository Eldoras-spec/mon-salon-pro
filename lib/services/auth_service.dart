import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

  // Stream of auth state changes
  Stream<User?> get user => _auth.authStateChanges();

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Sign in with email and password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      return await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
    } catch (e) {
      rethrow;
    }
  }

  // Register with email and details
  Future<UserCredential?> registerWithEmail({
    required String email,
    required String password,
    required String fullName,
    required String phone,
    required String city,
    required bool isClient,
  }) async {
    // Server-side rate limit check before creating the account
    await _functions.httpsCallable('checkSignupLimit').call({'email': email});

    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create a user document in Firestore
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'fullName': fullName,
        'whatsapp': phone,
        'city': city,
        'userType': isClient ? 'client' : 'owner',
        'whatsappVerified': false,
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Record successful signup for server-side rate tracking
      try {
        await _functions.httpsCallable('recordSignup').call({});
      } catch (_) {}

      return result;
    } catch (e) {
      rethrow;
    }
  }

  // Fetch user model from Firestore
  Future<UserModel?> getUserModel(String uid) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('users')
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 10));

      if (doc.exists) {
        return UserModel.fromFirestore(doc);
      } else {
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Send password reset email
  Future<void> sendPasswordResetEmail(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } catch (e) {
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    await _auth.signOut();
  }

  /// Delete account: removes all user data from Firestore + Storage, then
  /// deletes the Firebase Auth account. Requires recent authentication.
  Future<void> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Non connecté');
    final uid = user.uid;

    // ── Firestore cleanup (tolerant — errors don't block account deletion) ──

    Future<void> deleteQueryDocs(Query query) async {
      try {
        final snap = await query.get();
        if (snap.docs.isEmpty) return;
        final batch = _firestore.batch();
        for (final doc in snap.docs) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      } catch (_) {}
    }

    Future<void> deleteSubcollection(DocumentReference parent, String name) async {
      try {
        final snap = await parent.collection(name).get();
        if (snap.docs.isEmpty) return;
        final b = _firestore.batch();
        for (final doc in snap.docs) b.delete(doc.reference);
        await b.commit();
      } catch (_) {}
    }

    // User document
    try { await _firestore.collection('users').doc(uid).delete(); } catch (_) {}

    // Appointments (as client)
    await deleteQueryDocs(
      _firestore.collection('appointments').where('clientId', isEqualTo: uid),
    );

    // Notifications
    await deleteQueryDocs(
      _firestore.collection('notifications').where('userId', isEqualTo: uid),
    );

    // Points
    await deleteQueryDocs(
      _firestore.collection('points').where('userId', isEqualTo: uid),
    );

    // If owner: delete salon + related data
    try {
      final salonSnap = await _firestore
          .collection('salons')
          .where('ownerId', isEqualTo: uid)
          .limit(1)
          .get();

      if (salonSnap.docs.isNotEmpty) {
        final salonRef = salonSnap.docs.first.reference;
        final salonId = salonSnap.docs.first.id;

        await deleteSubcollection(salonRef, 'teamMembers');
        await deleteSubcollection(salonRef, 'beforeAfter');

        await deleteQueryDocs(
          _firestore.collection('appointments').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('promotions').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('charges').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('reviews').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('waitlist').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('inventory').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('products').where('salonId', isEqualTo: salonId),
        );
        await deleteQueryDocs(
          _firestore.collection('orders').where('salonId', isEqualTo: salonId),
        );

        try { await salonRef.delete(); } catch (_) {}
      }
    } catch (_) {}

    // Conversations
    try {
      final convos = await _firestore
          .collection('conversations')
          .where('participants', arrayContains: uid)
          .get();
      for (final doc in convos.docs) {
        await deleteSubcollection(doc.reference, 'messages');
        try { await doc.reference.delete(); } catch (_) {}
      }
    } catch (_) {}

    // ── Storage cleanup ──
    try {
      await _storage.ref().child('user_profiles').child('$uid.jpg').delete();
    } catch (_) {}

    // ── Unlink phone provider to free the number immediately ──
    try {
      final hasPhone = user.providerData.any((p) => p.providerId == 'phone');
      if (hasPhone) {
        await user.unlink('phone');
      }
    } catch (_) { /* non-fatal */ }

    // ── Delete Firebase Auth account (must be last) ──
    try {
      await user.delete();
    } catch (_) {
      // Fallback: force-delete via Admin SDK (Cloud Function)
      try {
        await _functions.httpsCallable('forceDeleteSelf').call();
      } catch (_) { /* swallowed — caller will still be signed out */ }
    }
  }

  // Upload profile picture to Firebase Storage.
  // Versioned filename (timestamp) so the URL changes on each update —
  // otherwise the 7-day Cache-Control would serve stale avatars to
  // other clients who already fetched the previous version.
  Future<String> uploadProfilePicture(String uid, File imageFile) async {
    try {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final ref = _storage.ref().child('user_profiles').child('${uid}_$ts.jpg');
      await ref.putFile(
        imageFile,
        SettableMetadata(cacheControl: 'public, max-age=604800'),
      );
      final url = await ref.getDownloadURL();
      // Best-effort cleanup of previous versions for this user so we
      // don't accumulate storage over time.
      _cleanupOldProfilePictures(uid, keepPath: ref.fullPath);
      return url;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _cleanupOldProfilePictures(String uid,
      {required String keepPath}) async {
    try {
      final listResult = await _storage.ref('user_profiles').listAll();
      for (final item in listResult.items) {
        if (item.fullPath == keepPath) continue;
        if (item.name == '$uid.jpg' || item.name.startsWith('${uid}_')) {
          try { await item.delete(); } catch (_) {}
        }
      }
    } catch (_) { /* cleanup is best-effort */ }
  }

  // Update profile image URL in Firestore
  Future<void> updateProfileImageUrl(String uid, String url) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'profileImageUrl': url,
      });
    } catch (e) {
      rethrow;
    }
  }
}
