import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewRewardModel {
  final String id;
  final String clientId;
  final String clientName;
  final String salonId;
  final String appointmentId;
  final String status; // 'pending' | 'validated' | 'rejected'
  final int discountPercent;
  final String? promoCode;
  final DateTime createdAt;
  final DateTime? validatedAt;

  ReviewRewardModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.salonId,
    required this.appointmentId,
    required this.status,
    required this.discountPercent,
    this.promoCode,
    required this.createdAt,
    this.validatedAt,
  });

  factory ReviewRewardModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReviewRewardModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      salonId: data['salonId'] ?? '',
      appointmentId: data['appointmentId'] ?? '',
      status: data['status'] ?? 'pending',
      discountPercent: data['discountPercent'] ?? 10,
      promoCode: data['promoCode'],
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      validatedAt: data['validatedAt'] != null
          ? (data['validatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'clientName': clientName,
      'salonId': salonId,
      'appointmentId': appointmentId,
      'status': status,
      'discountPercent': discountPercent,
      if (promoCode != null) 'promoCode': promoCode,
      'createdAt': Timestamp.fromDate(createdAt),
      if (validatedAt != null) 'validatedAt': Timestamp.fromDate(validatedAt!),
    };
  }
}
