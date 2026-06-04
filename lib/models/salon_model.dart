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
  // Public salon contact phone, displayed on the website's "call" button.
  // Optional and distinct from the owner's WhatsApp number (which lives in
  // socialLinks.whatsapp and powers the WhatsApp button + bot/alerts).
  // Empty when the owner hasn't set one — the call button hides itself.
  final String phone;
  final Map<String, dynamic> workingHours;

  /// Salon-wide full-day closures (national holidays / exceptional closures).
  /// ISO "YYYY-MM-DD" dates in the salon's LOCAL calendar (same convention as
  /// TeamMemberModel.unavailableDates). Overrides the weekly workingHours —
  /// the salon is treated as closed on these dates across every booking surface.
  final List<String> closedDates;
  final List<Map<String, dynamic>> services;
  final List<String> serviceCategories;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;
  // Social links — handle/username only (e.g. "mybeautysalon"), empty = not set
  final Map<String, String> socialLinks;
  final bool rewardPointsEnabled;
  // Loyalty cashback config. Owner-tunable from the Promotions screen.
  // Keys + defaults:
  //   cashbackPercent: 5     (1-20)
  //   expirationDays: 30     (7-182, multiples of 7) — ignored when
  //                           pointsNeverExpire == true
  //   pointsNeverExpire: false
  // Read by the `onAppointmentStatusChanged` CF when crediting points
  // and by `toolGetMyLoyaltyPoints` when telling the client how long
  // their points will live.
  final Map<String, dynamic> loyaltyConfig;
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
  // IANA timezone (e.g. "Africa/Casablanca", "Europe/Paris").
  // Used by Zayna's getAvailability and reminders to interpret the
  // owner-typed working hours as wall-clock local. Captured at onboarding
  // (auto-detected from the device, picker override) and editable via the
  // settings sheet later. Default kept for legacy salons created before
  // this field existed.
  final String timezone;

  // ── Cart-wide deposit policy (Stripe Connect) ──────────────────────────
  // When set AND no per-service paymentMode requires payment, the booking
  // CF charges `cartDepositAmount` as a deposit if the appointment total
  // reaches `cartDepositThreshold`. Both 0/null = policy disabled.
  // Replaces the legacy per-service `fixed_above` mode which was
  // semantically a cart-level rule.
  final double cartDepositThreshold;
  final double cartDepositAmount;

  // ── No-show risky-client deposit (Stripe Connect) ──────────────────────
  // When > 0, clients flagged as risky by `clientReputation` get charged a
  // deposit of `noShowDepositRate%` on every booking, even on services
  // configured with `paymentMode: 'none'`. If the service already has a
  // percentage deposit, the effective rate is the max of the two. Stored as
  // a percentage (0-100). 0 = feature disabled.
  final double noShowDepositRate;

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
    this.phone = '',
    required this.workingHours,
    required this.services,
    required this.serviceCategories,
    this.latitude,
    this.longitude,
    required this.createdAt,
    this.socialLinks = const {},
    this.servicePacks = const [],
    this.rewardPointsEnabled = true,
    this.loyaltyConfig = const {
      'cashbackPercent': 5,
      'expirationDays': 30,
      'pointsNeverExpire': false,
    },
    this.aiPromosEnabled = false,
    this.aiPromoConfig = const {
      'topClientPercent': 30,
      'winBackPercent': 20,
      'winBackWeeks': 3,
      'loyalPercent': 15,
      'loyalMinVisits': 10,
      'birthdayEnabled': true,
      'birthdayPercent': 20,
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
    this.timezone = 'Africa/Casablanca',
    this.cartDepositThreshold = 0,
    this.cartDepositAmount = 0,
    this.noShowDepositRate = 0,
    this.closedDates = const [],
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

  /// True if [date]'s calendar day is a salon-wide closure (holiday /
  /// exceptional). Compared as a local ISO "YYYY-MM-DD" string, matching how
  /// closedDates are stored (salon local calendar).
  bool isClosedOnDate(DateTime date) {
    final iso = '${date.year}-${date.month.toString().padLeft(2, '0')}'
        '-${date.day.toString().padLeft(2, '0')}';
    return closedDates.contains(iso);
  }

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
      phone: (data['phone'] as String?) ?? '',
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
      loyaltyConfig: Map<String, dynamic>.from(data['loyaltyConfig'] ?? {
        'cashbackPercent': 5,
        'expirationDays': 30,
        'pointsNeverExpire': false,
      }),
      aiPromosEnabled: data['aiPromosEnabled'] ?? false,
      aiPromoConfig: Map<String, dynamic>.from(data['aiPromoConfig'] ?? {
        'topClientPercent': 30,
        'winBackPercent': 20,
        'winBackWeeks': 3,
        'loyalPercent': 15,
        'loyalMinVisits': 10,
        'birthdayEnabled': true,
        'birthdayPercent': 20,
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
      timezone: (data['timezone'] as String?)?.trim().isNotEmpty == true
          ? data['timezone'] as String
          : 'Africa/Casablanca',
      cartDepositThreshold:
          (data['cartDepositThreshold'] as num?)?.toDouble() ?? 0,
      cartDepositAmount:
          (data['cartDepositAmount'] as num?)?.toDouble() ?? 0,
      noShowDepositRate:
          (data['noShowDepositRate'] as num?)?.toDouble() ?? 0,
      closedDates: List<String>.from(data['closedDates'] ?? []),
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
      'phone': phone,
      'workingHours': workingHours,
      'services': services,
      'serviceCategories': serviceCategories,
      'latitude': latitude,
      'longitude': longitude,
      'createdAt': Timestamp.fromDate(createdAt),
      'socialLinks': socialLinks,
      'rewardPointsEnabled': rewardPointsEnabled,
      'loyaltyConfig': loyaltyConfig,
      'aiPromosEnabled': aiPromosEnabled,
      'aiPromoConfig': aiPromoConfig,
      'googleReviewReward': googleReviewReward,
      'servicePacks': servicePacks,
      if (slug != null) 'slug': slug,
      'currency': currency,
      'salonType': salonType,
      'plan': plan,
      'timezone': timezone,
      'cartDepositThreshold': cartDepositThreshold,
      'cartDepositAmount': cartDepositAmount,
      'noShowDepositRate': noShowDepositRate,
      'closedDates': closedDates,
    };
  }
}
