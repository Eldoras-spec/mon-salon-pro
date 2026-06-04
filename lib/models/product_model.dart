import 'package:cloud_firestore/cloud_firestore.dart';

class ProductModel {
  final String id;
  final String salonId;
  final String name;
  final String description;
  final double price;
  final List<String> images; // max 3
  final String category;
  final int stock;
  final int lowStockThreshold;
  final String deliveryType; // 'pickup' | 'national' | 'cities'
  final List<String> deliveryCities;
  final double deliveryFee;
  /// Estimated lead time in days for the order to reach the client. Shown
  /// on the public product page (website + client app) when > 0. `0` /
  /// missing means no delay is displayed — owners who skip the field
  /// don't surface a misleading "0 days" badge.
  final int deliveryDays;
  // Only meaningful when deliveryType != 'pickup'. Drives which payment
  // options the checkout shows the client. Ignored for pickup (always COD).
  // 'card' | 'cod' | 'both'
  final String paymentOptions;
  final bool isActive;
  final DateTime createdAt;

  const ProductModel({
    required this.id,
    required this.salonId,
    required this.name,
    this.description = '',
    required this.price,
    this.images = const [],
    required this.category,
    required this.stock,
    this.lowStockThreshold = 5,
    this.deliveryType = 'pickup',
    this.deliveryCities = const [],
    this.deliveryFee = 0,
    this.deliveryDays = 0,
    this.paymentOptions = 'both',
    this.isActive = true,
    required this.createdAt,
  });

  bool get isLowStock => stock <= lowStockThreshold;
  bool get isOutOfStock => stock <= 0;

  factory ProductModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ProductModel(
      id: doc.id,
      salonId: d['salonId'] ?? '',
      name: d['name'] ?? '',
      description: d['description'] ?? '',
      price: (d['price'] as num?)?.toDouble() ?? 0,
      images: d['images'] != null ? List<String>.from(d['images']) : [],
      category: d['category'] ?? '',
      stock: (d['stock'] as num?)?.toInt() ?? 0,
      lowStockThreshold: (d['lowStockThreshold'] as num?)?.toInt() ?? 5,
      deliveryType: d['deliveryType'] as String? ?? 'pickup',
      deliveryCities: d['deliveryCities'] != null
          ? List<String>.from(d['deliveryCities'])
          : [],
      deliveryFee: (d['deliveryFee'] as num?)?.toDouble() ?? 0,
      deliveryDays: (d['deliveryDays'] as num?)?.toInt() ?? 0,
      paymentOptions: (d['paymentOptions'] as String?) ?? 'both',
      isActive: (d['isActive'] as bool?) ?? true,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'name': name,
        'description': description,
        'price': price,
        'images': images,
        'category': category,
        'stock': stock,
        'lowStockThreshold': lowStockThreshold,
        'deliveryType': deliveryType,
        'deliveryCities': deliveryCities,
        'deliveryFee': deliveryFee,
        'deliveryDays': deliveryDays,
        'paymentOptions': paymentOptions,
        'isActive': isActive,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ProductModel copyWith({
    String? name,
    String? description,
    double? price,
    List<String>? images,
    String? category,
    int? stock,
    int? lowStockThreshold,
    String? deliveryType,
    List<String>? deliveryCities,
    double? deliveryFee,
    int? deliveryDays,
    String? paymentOptions,
    bool? isActive,
  }) =>
      ProductModel(
        id: id,
        salonId: salonId,
        name: name ?? this.name,
        description: description ?? this.description,
        price: price ?? this.price,
        images: images ?? this.images,
        category: category ?? this.category,
        stock: stock ?? this.stock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        deliveryType: deliveryType ?? this.deliveryType,
        deliveryCities: deliveryCities ?? this.deliveryCities,
        deliveryFee: deliveryFee ?? this.deliveryFee,
        deliveryDays: deliveryDays ?? this.deliveryDays,
        paymentOptions: paymentOptions ?? this.paymentOptions,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}
