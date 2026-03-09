import 'package:cloud_firestore/cloud_firestore.dart';

class PointsModel {
  final String id;
  final String userId;
  final String salonId;
  final double amount;
  final String bookingId;
  final bool isUsed;
  final DateTime expiresAt;
  final DateTime createdAt;

  PointsModel({
    required this.id,
    required this.userId,
    required this.salonId,
    required this.amount,
    required this.bookingId,
    required this.isUsed,
    required this.expiresAt,
    required this.createdAt,
  });

  factory PointsModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PointsModel(
      id: doc.id,
      userId: data['userId'] ?? '',
      salonId: data['salonId'] ?? '',
      amount: (data['amount'] ?? 0.0).toDouble(),
      bookingId: data['bookingId'] ?? '',
      isUsed: data['isUsed'] ?? false,
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
