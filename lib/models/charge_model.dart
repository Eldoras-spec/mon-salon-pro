import 'package:cloud_firestore/cloud_firestore.dart';

class ChargeModel {
  final String id;
  final String salonId;
  final String label;
  final String category; // 'Fixe', 'Variable'
  final String type; // 'Salaire', 'Loyer', 'Produits', 'Équipement', 'Factures', 'Marketing', 'Autre'
  final double amount;
  final int month; // 1-12
  final int year;
  final DateTime createdAt;

  const ChargeModel({
    required this.id,
    required this.salonId,
    required this.label,
    required this.category,
    this.type = 'Autre',
    required this.amount,
    required this.month,
    required this.year,
    required this.createdAt,
  });

  factory ChargeModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ChargeModel(
      id: doc.id,
      salonId: d['salonId'] ?? '',
      label: d['label'] ?? '',
      category: d['category'] ?? 'Variable',
      type: d['type'] ?? 'Autre',
      amount: (d['amount'] ?? 0.0).toDouble(),
      month: (d['month'] ?? 1) as int,
      year: (d['year'] ?? DateTime.now().year) as int,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'label': label,
        'category': category,
        'type': type,
        'amount': amount,
        'month': month,
        'year': year,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
