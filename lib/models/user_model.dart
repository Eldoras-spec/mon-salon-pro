import 'package:cloud_firestore/cloud_firestore.dart';

enum UserType { client, owner }

class UserModel {
  final String id;
  final String email;
  final String fullName;
  final String whatsapp;
  final String city;
  final UserType userType;
  final String? profileImageUrl;
  final List<String> favorites;
  final String? fcmToken;
  final bool hasClaimedOffer;
  final bool promoCodeUsed; // true once ELITE10 has been redeemed (permanent)
  final bool notificationsEnabled;
  final String? pinHash; // SHA256 PIN for profile selector (owner only)
  final bool whatsappVerified; // true once WA OTP has been validated
  final DateTime createdAt;

  UserModel({
    required this.id,
    required this.email,
    required this.fullName,
    required this.whatsapp,
    required this.city,
    required this.userType,
    this.profileImageUrl,
    this.favorites = const [],
    this.fcmToken,
    this.hasClaimedOffer = false,
    this.promoCodeUsed = false,
    this.notificationsEnabled = true,
    this.pinHash,
    this.whatsappVerified = false,
    required this.createdAt,
  });

  factory UserModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return UserModel(
      id: doc.id,
      email: data['email'] ?? '',
      fullName: data['fullName'] ?? '',
      // Read `whatsapp` (post-migration) or fall back to legacy `phone`.
      whatsapp: (data['whatsapp'] as String?) ?? (data['phone'] as String?) ?? '',
      city: data['city'] ?? '',
      userType: data['userType'] == 'owner' ? UserType.owner : UserType.client,
      profileImageUrl: data['profileImageUrl'],
      favorites: List<String>.from(data['favorites'] ?? []),
      fcmToken: data['fcmToken'],
      hasClaimedOffer: data['hasClaimedOffer'] ?? false,
      promoCodeUsed: data['promoCodeUsed'] ?? false,
      notificationsEnabled: data['notificationsEnabled'] ?? true,
      pinHash: data['pinHash'],
      whatsappVerified: (data['whatsappVerified'] as bool?) ??
          (data['phoneVerified'] as bool?) ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'email': email,
      'fullName': fullName,
      'whatsapp': whatsapp,
      'city': city,
      'userType': userType == UserType.owner ? 'owner' : 'client',
      'profileImageUrl': profileImageUrl,
      'favorites': favorites,
      'fcmToken': fcmToken,
      'hasClaimedOffer': hasClaimedOffer,
      'promoCodeUsed': promoCodeUsed,
      'notificationsEnabled': notificationsEnabled,
      if (pinHash != null) 'pinHash': pinHash,
      'whatsappVerified': whatsappVerified,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }
}
