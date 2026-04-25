import 'package:cloud_firestore/cloud_firestore.dart';

class SalonModel {
  final String id;
  final String ownerId;
  final String name;
  final String address;
  final String city;
  final String country;
  final String description;
  final String category;
  final double rating;
  final int reviewCount;
  final List<String> images;
  final String? logoUrl;
  final Map<String, dynamic> workingHours;
  final List<Map<String, dynamic>> services;
  final List<String> serviceCategories;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  // Social links — handle/username only (e.g. "mybeautysalon"), empty = not set
  final Map<String, String> socialLinks;
  final bool rewardPointsEnabled;
  final bool aiPromosEnabled;
  final Map<String, dynamic> aiPromoConfig;
  final Map<String, dynamic> googleReviewReward;
  final String? slug;
  // Service packs — bundled services at a reduced price
  // Each pack: { name, services: [service names], price, description? }
  final List<Map<String, dynamic>> servicePacks;
  final bool isPremium;
  final int galleryStorageUsed;
  final String currency; // ISO code: MAD, EUR, USD, XOF, etc.
  final String salonType; // 'femme', 'homme', 'mixte'
  final List<String> dismissedSetupTasks; // keys of setup tasks owner has manually hidden

  // ── Subscription plan (source of truth) ────────────────────────────────
  // 'free'      → team capped at 2 members (owner + 1), no videos
  // 'essentiel' → unlimited team, AI widgets, everything except Business extras
  // 'business'  → essentiel + video uploads + SMS verification + AI chatbot
  // `isPremium` is the derived boolean kept in sync server-side by the
  // `onSalonPlanChange` CF (plan == 'business' ⇔ isPremium == true).
  final String plan;
  // End of Essentiel free trial (3 months). null if not on trial / already paid.
  final DateTime? trialEndsAt;
  // When a Free salon has >2 team members (e.g. after downgrade from a paid
  // plan), this stamps the 30-day grace deadline. The `enforceFreeTeamCap`
  // CF deactivates excess members once it passes. null if no grace pending.
  final DateTime? freeCapGraceEndsAt;
  // Stamped server-side the first time a salon touches any paid plan
  // (essentiel or business). Once true, the free trial is never granted
  // again — see `onSalonPlanChange` CF.
  final bool paidPlanEverActivated;

  SalonModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.address,
    required this.city,
    this.country = 'Maroc',
    required this.description,
    required this.category,
    required this.rating,
    required this.reviewCount,
    required this.images,
    this.logoUrl,
    required this.workingHours,
    required this.services,
    required this.serviceCategories,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.socialLinks = const {},
    this.servicePacks = const [],
    this.rewardPointsEnabled = true,
    this.aiPromosEnabled = false,
    this.aiPromoConfig = const {
      'topClientPercent': 30,
      'winBackPercent': 20,
      'winBackWeeks': 3,
      'loyalPercent': 15,
      'loyalMinVisits': 10,
    },
    this.googleReviewReward = const {
      'enabled': false,
      'discountPercent': 10,
      'googleMapsUrl': '',
    },
    this.slug,
    this.isPremium = false,
    this.galleryStorageUsed = 0,
    this.currency = 'MAD',
    this.salonType = 'femme',
    this.dismissedSetupTasks = const [],
    this.plan = 'essentiel',
    this.trialEndsAt,
    this.freeCapGraceEndsAt,
    this.paidPlanEverActivated = false,
  });

  /// Client-side predictor of whether this salon would get the 3-month
  /// trial if it upgraded to Essentiel now. Mirrors the CF guard — used
  /// for UI (hide "3 mois offerts" when we already know it won't apply).
  /// The server remains the real authority (phone registry is server-only).
  bool get isTrialEligible {
    if (paidPlanEverActivated) return false;
    if (trialEndsAt != null) return false;
    if (plan == 'business' || plan == 'essentiel') return false;
    return true;
  }

  /// Shorthand accessors for plan-based feature gating.
  /// `isPremium` continues to represent Business (field kept for legacy
  /// rules + triggers). `isFree` / `isEssentiel` are read-only derivations.
  bool get isFree => plan == 'free';
  bool get isEssentiel => plan == 'essentiel';
  bool get isBusiness => plan == 'business';

  factory SalonModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return SalonModel(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      city: data['city'] ?? '',
      country: data['country'] ?? 'Maroc',
      description: data['description'] ?? '',
      category: data['category'] ?? '',
      rating: (data['rating'] ?? 0.0).toDouble(),
      reviewCount: data['reviewCount'] ?? 0,
      images: List<String>.from(data['images'] ?? []),
      logoUrl: data['logoUrl'],
      workingHours: Map<String, dynamic>.from(data['workingHours'] ?? {}),
      services: List<Map<String, dynamic>>.from(data['services'] ?? []),
      serviceCategories: List<String>.from(data['serviceCategories'] ?? []),
      latitude: (data['latitude'] as num?)?.toDouble(),
      longitude: (data['longitude'] as num?)?.toDouble(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      socialLinks: data['socialLinks'] != null
          ? Map<String, String>.from(
              (data['socialLinks'] as Map).map(
                (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
              ),
            )
          : {},
      rewardPointsEnabled: data['rewardPointsEnabled'] ?? true,
      aiPromosEnabled: data['aiPromosEnabled'] ?? false,
      aiPromoConfig: Map<String, dynamic>.from(data['aiPromoConfig'] ?? {
        'topClientPercent': 30,
        'winBackPercent': 20,
        'winBackWeeks': 3,
        'loyalPercent': 15,
        'loyalMinVisits': 10,
      }),
      googleReviewReward: Map<String, dynamic>.from(data['googleReviewReward'] ?? {
        'enabled': false,
        'discountPercent': 10,
        'googleMapsUrl': '',
      }),
      servicePacks: List<Map<String, dynamic>>.from(data['servicePacks'] ?? []),
      slug: data['slug'],
      isPremium: data['isPremium'] ?? false,
      galleryStorageUsed: (data['galleryStorageUsed'] as num?)?.toInt() ?? 0,
      currency: data['currency'] ?? 'MAD',
      salonType: data['salonType'] ?? 'femme',
      dismissedSetupTasks:
          List<String>.from(data['dismissedSetupTasks'] ?? const []),
      // Fallback for legacy salons without `plan` field: derive from
      // `isPremium` (grandfathered as Essentiel so existing non-premium
      // salons keep full features by default).
      plan: data['plan'] as String? ??
          ((data['isPremium'] == true) ? 'business' : 'essentiel'),
      trialEndsAt: (data['trialEndsAt'] is Timestamp)
          ? (data['trialEndsAt'] as Timestamp).toDate()
          : null,
      freeCapGraceEndsAt: (data['freeCapGraceEndsAt'] is Timestamp)
          ? (data['freeCapGraceEndsAt'] as Timestamp).toDate()
          : null,
      paidPlanEverActivated: data['paidPlanEverActivated'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'address': address,
      'city': city,
      'country': country,
      'description': description,
      'category': category,
      'rating': rating,
      'reviewCount': reviewCount,
      'images': images,
      'logoUrl': logoUrl,
      'workingHours': workingHours,
      'services': services,
      'serviceCategories': serviceCategories,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'socialLinks': socialLinks,
      'rewardPointsEnabled': rewardPointsEnabled,
      'aiPromosEnabled': aiPromosEnabled,
      'aiPromoConfig': aiPromoConfig,
      'googleReviewReward': googleReviewReward,
      'servicePacks': servicePacks,
      if (slug != null) 'slug': slug,
      'currency': currency,
      'salonType': salonType,
      'plan': plan,
    };
  }
}
