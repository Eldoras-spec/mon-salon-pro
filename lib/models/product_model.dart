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
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}
