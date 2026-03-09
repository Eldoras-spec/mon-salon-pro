import 'package:cloud_firestore/cloud_firestore.dart';

class WaitlistEntry {
  final String id;
  final String clientId;
  final String clientName;
  final String salonId;
  final String salonName;
  final String serviceName;
  final DateTime desiredDate;
  final DateTime createdAt;
  final bool notified;

  WaitlistEntry({
    required this.id,
    required this.clientId,
    required this.clientName,
    required this.salonId,
    required this.salonName,
    required this.serviceName,
    required this.desiredDate,
    required this.createdAt,
    this.notified = false,
  });

  factory WaitlistEntry.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return WaitlistEntry(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      clientName: data['clientName'] ?? '',
      salonId: data['salonId'] ?? '',
      salonName: data['salonName'] ?? '',
      serviceName: data['serviceName'] ?? '',
      desiredDate: (data['desiredDate'] as Timestamp).toDate(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      notified: data['notified'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'clientId': clientId,
      'clientName': clientName,
      'salonId': salonId,
      'salonName': salonName,
      'serviceName': serviceName,
      'desiredDate': Timestamp.fromDate(desiredDate),
      'createdAt': Timestamp.fromDate(createdAt),
      'notified': notified,
    };
  }
}
