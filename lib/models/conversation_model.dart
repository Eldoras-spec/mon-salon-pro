import 'package:cloud_firestore/cloud_firestore.dart';

class ConversationModel {
  final String id;
  final String clientId;
  final String clientName;
  final String salonId;
  final String salonName;
  final String ownerId;
  final String lastMessage;
  final DateTime lastMessageAt;
  final int unreadByOwner;
  final int unreadByClient;
  final DateTime createdAt;

  ConversationModel({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.salonId,
    required this.salonName,
    required this.ownerId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.unreadByOwner,
    required this.unreadByClient,
    required this.createdAt,
  });

  factory ConversationModel.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return ConversationModel(
      id: doc.id,
      clientId: d['clientId'] ?? '',
      clientName: d['clientName'] ?? '',
      salonId: d['salonId'] ?? '',
      salonName: d['salonName'] ?? '',
      ownerId: d['ownerId'] ?? '',
      lastMessage: d['lastMessage'] ?? '',
      lastMessageAt: d['lastMessageAt'] != null
          ? (d['lastMessageAt'] as Timestamp).toDate()
          : DateTime.now(),
      unreadByOwner: (d['unreadByOwner'] ?? 0) as int,
      unreadByClient: (d['unreadByClient'] ?? 0) as int,
      createdAt: d['createdAt'] != null
          ? (d['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
    );
  }
}
