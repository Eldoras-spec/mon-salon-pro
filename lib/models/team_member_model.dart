import 'package:cloud_firestore/cloud_firestore.dart';

class TeamMemberModel {
  final String id;
  final String salonId;
  final String name;
  final String role; // 'gerant' | 'member'
  final String pinHash; // SHA256 of 6-digit PIN
  final String? phone;
  final bool isActive;
  final DateTime createdAt;
  final List<String> unavailableDates; // ISO date strings e.g. "2026-03-15"
  final Map<String, List<String>> unavailableSlots; // e.g. {"2026-03-10": ["12:00-13:00", "17:00-18:00"]}
  final List<String> assignedServiceNames; // service names this member can perform
  final String? photoUrl; // profile photo URL
  final List<int> recurringDaysOff; // weekday numbers (1=Mon ... 7=Sun)

  TeamMemberModel({
    required this.id,
    required this.salonId,
    required this.name,
    required this.role,
    required this.pinHash,
    this.phone,
    required this.isActive,
    required this.createdAt,
    this.unavailableDates = const [],
    this.unavailableSlots = const {},
    this.assignedServiceNames = const [],
    this.photoUrl,
    this.recurringDaysOff = const [],
  });

  factory TeamMemberModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return TeamMemberModel(
      id: doc.id,
      salonId: data['salonId'] ?? '',
      name: data['name'] ?? '',
      role: data['role'] ?? 'member',
      pinHash: data['pinHash'] ?? '',
      phone: data['phone'],
      isActive: data['isActive'] ?? true,
      createdAt: data['createdAt'] != null
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      unavailableDates:
          List<String>.from(data['unavailableDates'] ?? []),
      unavailableSlots: (data['unavailableSlots'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, List<String>.from(v))) ??
          {},
      assignedServiceNames:
          List<String>.from(data['assignedServiceNames'] ?? []),
      photoUrl: data['photoUrl'] as String?,
      recurringDaysOff:
          List<int>.from(data['recurringDaysOff'] ?? []),
    );
  }

  TeamMemberModel copyWith({
    List<String>? unavailableDates,
    Map<String, List<String>>? unavailableSlots,
    List<String>? assignedServiceNames,
    String? photoUrl,
    List<int>? recurringDaysOff,
  }) {
    return TeamMemberModel(
      id: id,
      salonId: salonId,
      name: name,
      role: role,
      pinHash: pinHash,
      phone: phone,
      isActive: isActive,
      createdAt: createdAt,
      unavailableDates: unavailableDates ?? this.unavailableDates,
      unavailableSlots: unavailableSlots ?? this.unavailableSlots,
      assignedServiceNames: assignedServiceNames ?? this.assignedServiceNames,
      photoUrl: photoUrl ?? this.photoUrl,
      recurringDaysOff: recurringDaysOff ?? this.recurringDaysOff,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'salonId': salonId,
      'name': name,
      'role': role,
      'pinHash': pinHash,
      'phone': phone,
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'unavailableDates': unavailableDates,
      'unavailableSlots': unavailableSlots,
      'assignedServiceNames': assignedServiceNames,
      if (photoUrl != null) 'photoUrl': photoUrl,
      'recurringDaysOff': recurringDaysOff,
    };
  }
}
