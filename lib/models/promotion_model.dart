import 'package:cloud_firestore/cloud_firestore.dart';

class PromotionModel {
  final String id;
  final String salonId;
  final String title;
  final String description;
  final String type; // 'percent', 'special', 'code'
  final double? discountPercent;
  final String? promoCode;
  final List<String>? applicableServiceNames; // null = all services
  final DateTime? expiresAt;
  final bool isActive;
  final DateTime createdAt;
  // AI-generated promotion fields
  final bool isAiGenerated;
  final String? aiReason; // e.g. 'top_client', 'win_back', 'loyal'
  final String? targetedClientId;
  final String? targetedClientName;

  const PromotionModel({
    required this.id,
    required this.salonId,
    required this.title,
    required this.description,
    required this.type,
    this.discountPercent,
    this.promoCode,
    this.applicableServiceNames,
    this.expiresAt,
    required this.isActive,
    required this.createdAt,
    this.isAiGenerated = false,
    this.aiReason,
    this.targetedClientId,
    this.targetedClientName,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  bool get isVisibleToClient => isActive && !isExpired && targetedClientId == null;

  /// Check if this promo is visible to a specific client
  bool isVisibleTo(String? clientId) =>
      isActive && !isExpired && (targetedClientId == null || targetedClientId == clientId);

  factory PromotionModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return PromotionModel(
      id: doc.id,
      salonId: d['salonId'] ?? '',
      title: d['title'] ?? '',
      description: d['description'] ?? '',
      type: d['type'] ?? 'percent',
      discountPercent: d['discountPercent'] != null
          ? (d['discountPercent'] as num).toDouble()
          : null,
      promoCode: d['promoCode'] as String?,
      applicableServiceNames: d['applicableServiceNames'] != null
          ? List<String>.from(d['applicableServiceNames'])
          : null,
      expiresAt: d['expiresAt'] != null
          ? (d['expiresAt'] as Timestamp).toDate()
          : null,
      isActive: (d['isActive'] as bool?) ?? true,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      isAiGenerated: d['isAiGenerated'] ?? false,
      aiReason: d['aiReason'] as String?,
      targetedClientId: d['targetedClientId'] as String?,
      targetedClientName: d['targetedClientName'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'title': title,
        'description': description,
        'type': type,
        if (discountPercent != null) 'discountPercent': discountPercent,
        if (promoCode != null) 'promoCode': promoCode,
        if (applicableServiceNames != null)
          'applicableServiceNames': applicableServiceNames,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
        'isAiGenerated': isAiGenerated,
        if (aiReason != null) 'aiReason': aiReason,
        if (targetedClientId != null) 'targetedClientId': targetedClientId,
        if (targetedClientName != null) 'targetedClientName': targetedClientName,
      };
}
