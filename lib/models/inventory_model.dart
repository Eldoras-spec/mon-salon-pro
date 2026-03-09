import 'package:cloud_firestore/cloud_firestore.dart';

class InventoryModel {
  final String id;
  final String salonId;
  final String name;
  final String category; // 'Produit', 'Consommable', 'Équipement'
  final int quantity;
  final int minQuantity;
  final String unit; // 'unité', 'ml', 'g', 'L', 'kg'
  final double? price;
  final DateTime createdAt;

  const InventoryModel({
    required this.id,
    required this.salonId,
    required this.name,
    required this.category,
    required this.quantity,
    required this.minQuantity,
    required this.unit,
    this.price,
    required this.createdAt,
  });

  bool get isLow => quantity <= minQuantity;

  factory InventoryModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return InventoryModel(
      id: doc.id,
      salonId: d['salonId'] ?? '',
      name: d['name'] ?? '',
      category: d['category'] ?? 'Produit',
      quantity: (d['quantity'] ?? 0) as int,
      minQuantity: (d['minQuantity'] ?? 2) as int,
      unit: d['unit'] ?? 'unité',
      price: d['price'] != null ? (d['price'] as num).toDouble() : null,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'name': name,
        'category': category,
        'quantity': quantity,
        'minQuantity': minQuantity,
        'unit': unit,
        if (price != null) 'price': price,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  InventoryModel copyWith({
    int? quantity,
    bool? isLow,
  }) =>
      InventoryModel(
        id: id,
        salonId: salonId,
        name: name,
        category: category,
        quantity: quantity ?? this.quantity,
        minQuantity: minQuantity,
        unit: unit,
        price: price,
        createdAt: createdAt,
      );
}
