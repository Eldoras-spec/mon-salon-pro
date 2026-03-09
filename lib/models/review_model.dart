import 'package:cloud_firestore/cloud_firestore.dart';

class ReviewModel {
  final String id;
  final String salonId;
  final String userId;
  final String userName;
  final int rating; // 1–5
  final String comment;
  final DateTime createdAt;

  ReviewModel({
    required this.id,
    required this.salonId,
    required this.userId,
    required this.userName,
    required this.rating,
    required this.comment,
    required this.createdAt,
  });

  factory ReviewModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ReviewModel(
      id: doc.id,
      salonId: data['salonId'] ?? '',
      userId: data['userId'] ?? '',
      userName: data['userName'] ?? 'Client',
      rating: (data['rating'] ?? 5) as int,
      comment: data['comment'] ?? '',
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() => {
        'salonId': salonId,
        'userId': userId,
        'userName': userName,
        'rating': rating,
        'comment': comment,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
