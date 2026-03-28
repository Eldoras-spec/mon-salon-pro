import 'package:cloud_firestore/cloud_firestore.dart';

class MessageModel {
  final String id;
  final String senderId;
  final String text;
  final DateTime sentAt;
  final String? imageUrl;
  final String type; // 'text', 'image', 'custom_request'
  final bool isAutoReply;
  // Custom request fields
  final String? customRequestStatus; // 'pending', 'approved', 'rejected'
  final double? proposedPrice;
  final int? proposedDuration;
  final String? ownerResponse;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.text,
    required this.sentAt,
    this.imageUrl,
    this.type = 'text',
    this.isAutoReply = false,
    this.customRequestStatus,
    this.proposedPrice,
    this.proposedDuration,
    this.ownerResponse,
  });

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      senderId: d['senderId'] ?? '',
      text: d['text'] ?? '',
      sentAt: d['sentAt'] != null
          ? (d['sentAt'] as Timestamp).toDate()
          : DateTime.now(),
      imageUrl: d['imageUrl'],
      type: d['type'] ?? 'text',
      isAutoReply: d['isAutoReply'] ?? false,
      customRequestStatus: d['customRequestStatus'],
      proposedPrice: (d['proposedPrice'] as num?)?.toDouble(),
      proposedDuration: d['proposedDuration'] as int?,
      ownerResponse: d['ownerResponse'],
    );
  }
}
