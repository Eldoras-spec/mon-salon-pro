import 'package:cloud_firestore/cloud_firestore.dart';

class SalonModel {
  final String id;
  final String ownerId;
  final String name;
  final String address;
  final String city;
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
  final String? slug;

  SalonModel({
    required this.id,
    required this.ownerId,
    required this.name,
    required this.address,
    required this.city,
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
    this.rewardPointsEnabled = true,
    this.aiPromosEnabled = false,
    this.aiPromoConfig = const {
      'topClientPercent': 30,
      'winBackPercent': 20,
      'winBackWeeks': 3,
      'loyalPercent': 15,
      'loyalMinVisits': 10,
    },
    this.slug,
  });

  factory SalonModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return SalonModel(
      id: doc.id,
      ownerId: data['ownerId'] ?? '',
      name: data['name'] ?? '',
      address: data['address'] ?? '',
      city: data['city'] ?? '',
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
      slug: data['slug'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'ownerId': ownerId,
      'name': name,
      'address': address,
      'city': city,
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
      if (slug != null) 'slug': slug,
    };
  }
}
