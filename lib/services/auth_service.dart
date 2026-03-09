import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

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
    try {
      UserCredential result = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      // Create a user document in Firestore
      await _firestore.collection('users').doc(result.user!.uid).set({
        'email': email,
        'fullName': fullName,
        'phone': phone,
        'city': city,
        'userType': isClient ? 'client' : 'owner',
        'createdAt': FieldValue.serverTimestamp(),
      });

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

    // ── Firestore cleanup (multiple batches to stay under 500-op limit) ──

    Future<void> deleteQueryDocs(Query query) async {
      final snap = await query.get();
      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    }

    // User document
    await _firestore.collection('users').doc(uid).delete();

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
    final salonSnap = await _firestore
        .collection('salons')
        .where('ownerId', isEqualTo: uid)
        .limit(1)
        .get();

    if (salonSnap.docs.isNotEmpty) {
      final salonRef = salonSnap.docs.first.reference;
      final salonId = salonSnap.docs.first.id;

      // Team members sub-collection
      final team = await salonRef.collection('teamMembers').get();
      if (team.docs.isNotEmpty) {
        final b = _firestore.batch();
        for (final doc in team.docs) b.delete(doc.reference);
        await b.commit();
      }

      // Salon appointments
      await deleteQueryDocs(
        _firestore.collection('appointments').where('salonId', isEqualTo: salonId),
      );

      // Promotions
      await deleteQueryDocs(
        _firestore.collection('promotions').where('salonId', isEqualTo: salonId),
      );

      // Charges
      await deleteQueryDocs(
        _firestore.collection('charges').where('salonId', isEqualTo: salonId),
      );

      // Reviews
      await deleteQueryDocs(
        _firestore.collection('reviews').where('salonId', isEqualTo: salonId),
      );

      // Waitlist
      await deleteQueryDocs(
        _firestore.collection('waitlist').where('salonId', isEqualTo: salonId),
      );

      // Inventory sub-collection
      final inventory = await salonRef.collection('inventory').get();
      if (inventory.docs.isNotEmpty) {
        final b = _firestore.batch();
        for (final doc in inventory.docs) b.delete(doc.reference);
        await b.commit();
      }

      // Salon document
      await salonRef.delete();
    }

    // Conversations
    final convos = await _firestore
        .collection('conversations')
        .where('participants', arrayContains: uid)
        .get();
    for (final doc in convos.docs) {
      final msgs = await doc.reference.collection('messages').get();
      if (msgs.docs.isNotEmpty) {
        final b = _firestore.batch();
        for (final m in msgs.docs) b.delete(m.reference);
        await b.commit();
      }
      await doc.reference.delete();
    }

    // ── Storage cleanup ──
    try {
      await _storage.ref().child('user_profiles').child('$uid.jpg').delete();
    } catch (_) {}

    // ── Delete Firebase Auth account (must be last) ──
    await user.delete();
  }

  // Upload profile picture to Firebase Storage
  Future<String> uploadProfilePicture(String uid, File imageFile) async {
    try {
      final ref = _storage.ref().child('user_profiles').child('$uid.jpg');
      await ref.putFile(imageFile);
      return await ref.getDownloadURL();
    } catch (e) {
      rethrow;
    }
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
