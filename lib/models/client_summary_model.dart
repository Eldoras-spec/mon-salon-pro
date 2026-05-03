import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-salon aggregate of a single client's visit history, maintained by
/// the `maintainClientSummary` Cloud Function.
///
/// Stored at `salons/{salonId}/clientSummaries/{id}` where `id` is either the
/// Firebase UID (registered client) or `walkin_<phoneNormalized>` (walk-in).
class ClientSummaryModel {
  final String id;
  final String clientId; // 'walk-in' or Firebase UID
  final String type; // 'walk-in' | 'registered'
  final String clientName;
  final String clientPhone;
  final String? clientEmail;
  final String? phoneNormalized;
  final DateTime firstVisit;
  final DateTime lastVisit;
  final int visitCount;
  final double totalSpent;
  final Map<String, int> servicesCount;
  final bool migratedFromWalkIn;

  ClientSummaryModel({
    required this.id,
    required this.clientId,
    required this.type,
    required this.clientName,
    required this.clientPhone,
    this.clientEmail,
    this.phoneNormalized,
    required this.firstVisit,
    required this.lastVisit,
    required this.visitCount,
    required this.totalSpent,
    required this.servicesCount,
    this.migratedFromWalkIn = false,
  });

  bool get isWalkIn => type == 'walk-in';

  String get favoriteService {
    if (servicesCount.isEmpty) return '—';
    final sorted = servicesCount.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.isEmpty ? '—' : sorted.first.key;
  }

  double get averageBasket =>
      visitCount > 0 ? totalSpent / visitCount : 0;

  factory ClientSummaryModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ClientSummaryModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      type: data['type'] ?? 'registered',
      clientName: data['clientName'] ?? '—',
      clientPhone: data['clientPhone'] ?? '',
      clientEmail: data['clientEmail'],
      phoneNormalized: data['phoneNormalized'],
      firstVisit: (data['firstVisit'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastVisit: (data['lastVisit'] as Timestamp?)?.toDate() ?? DateTime.now(),
      visitCount: (data['visitCount'] ?? 0) as int,
      totalSpent: (data['totalSpent'] ?? 0).toDouble(),
      servicesCount: (data['servicesCount'] as Map<String, dynamic>? ?? {})
          .map((k, v) => MapEntry(k, (v ?? 0) as int)),
      migratedFromWalkIn: data['migratedFromWalkIn'] == true,
    );
  }
}
