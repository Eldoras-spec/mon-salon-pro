import 'package:cloud_firestore/cloud_firestore.dart';

class PromotionModel {
  final String id;
  final String salonId;
  final String title;
  final String description;
  final String type; // 'percent', 'conditional', 'code'
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
  // Total redemptions across all eligible clients for this rule-based
  // AI promo (used to display "{n} personnes ont profité" on the owner
  // card). Incremented atomically by the backend at each redemption.
  //
  // Per-client eligibility resets on use: e.g. for the `loyal` rule with
  // `loyalMinVisits=10`, a client redeems at visit 10, then their next
  // eligibility window opens at visit 20 — tracked per-(client, aiReason)
  // outside this doc (planned: `users/{uid}/aiPromoState/{aiReason}`).
  // This counter is only the cumulative total — eligibility logic lives
  // in the backend.
  final int redemptionCount;
  // Conditional promo fields
  final double? minAmount; // minimum spend to activate
  final List<String>? validDays; // e.g. ['lundi', 'mardi'] — null = every day
  final String? validHoursStart; // e.g. '09:00'
  final String? validHoursEnd; // e.g. '12:00'

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
    this.redemptionCount = 0,
    this.minAmount,
    this.validDays,
    this.validHoursStart,
    this.validHoursEnd,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// True when this AI promo is the rule-based variant (1 doc per
  /// `aiReason`, applies to every eligible client). Old per-client AI
  /// promos (`targetedClientId != null`) are transitional and expire
  /// naturally — distinguishing them lets the UI show the appropriate
  /// per-instance vs aggregate info during the migration window.
  bool get isAiRuleBased => isAiGenerated && targetedClientId == null;

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
      redemptionCount: (d['redemptionCount'] as num?)?.toInt() ?? 0,
      minAmount: d['minAmount'] != null ? (d['minAmount'] as num).toDouble() : null,
      validDays: d['validDays'] != null ? List<String>.from(d['validDays']) : null,
      validHoursStart: d['validHoursStart'] as String?,
      validHoursEnd: d['validHoursEnd'] as String?,
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
        'redemptionCount': redemptionCount,
        if (minAmount != null) 'minAmount': minAmount,
        if (validDays != null) 'validDays': validDays,
        if (validHoursStart != null) 'validHoursStart': validHoursStart,
        if (validHoursEnd != null) 'validHoursEnd': validHoursEnd,
      };
}
