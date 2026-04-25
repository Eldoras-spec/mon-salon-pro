import 'package:cloud_firestore/cloud_firestore.dart';

class AppointmentModel {
  final String id;
  final String clientId;
  final String salonId;
  final String salonName;
  final String serviceName;
  final double price;
  final DateTime dateTime;
  final String status; // 'upcoming', 'completed', 'cancelled'
  final DateTime createdAt;
  final int durationMinutes;
  final String? clientName;
  final String? clientPhone;
  final String? assignedMemberId;
  final String? assignedMemberName;
  final String? groupId; // links multi-service bookings together
  final List<String>? selectedOptions; // complex service choices
  final String? selectedDesignUrl; // gallery design image/video URL
  final String? selectedDesignLabel; // gallery design label
  final String? selectedDesignThumbnail; // video thumbnail URL
  final bool? selectedDesignIsVideo;
  final String? managementToken; // walk-in management token

  AppointmentModel({
    required this.id,
    required this.clientId,
    required this.salonId,
    required this.salonName,
    required this.serviceName,
    required this.price,
    required this.dateTime,
    required this.status,
    required this.createdAt,
    this.durationMinutes = 30,
    this.clientName,
    this.clientPhone,
    this.assignedMemberId,
    this.assignedMemberName,
    this.groupId,
    this.selectedOptions,
    this.selectedDesignUrl,
    this.selectedDesignLabel,
    this.selectedDesignThumbnail,
    this.selectedDesignIsVideo,
    this.managementToken,
  });

  factory AppointmentModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return AppointmentModel(
      id: doc.id,
      clientId: data['clientId'] ?? '',
      salonId: data['salonId'] ?? '',
      salonName: data['salonName'] ?? '',
      serviceName: data['serviceName'] ?? '',
      price: (data['price'] ?? 0.0).toDouble(),
      dateTime: (data['dateTime'] as Timestamp).toDate().toUtc(),
      status: data['status'] ?? 'upcoming',
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      durationMinutes: data['durationMinutes'] ?? 30,
      clientName: data['clientName'],
      clientPhone: data['clientPhone'],
      assignedMemberId: data['assignedMemberId'],
      assignedMemberName: data['assignedMemberName'],
      groupId: data['groupId'],
      selectedOptions: data['selectedOptions'] != null ? List<String>.from(data['selectedOptions']) : null,
      selectedDesignUrl: data['selectedDesignUrl'],
      selectedDesignLabel: data['selectedDesignLabel'],
      selectedDesignThumbnail: data['selectedDesignThumbnail'],
      selectedDesignIsVideo: data['selectedDesignIsVideo'],
      managementToken: data['managementToken'],
    );
  }

  /// Clone with overrides — used to merge `private/contact` subcol into
  /// an existing instance during dual-source reads.
  AppointmentModel copyWith({
    String? clientName,
    String? clientPhone,
    String? managementToken,
  }) {
    return AppointmentModel(
      id: id,
      clientId: clientId,
      salonId: salonId,
      salonName: salonName,
      serviceName: serviceName,
      price: price,
      dateTime: dateTime,
      status: status,
      createdAt: createdAt,
      durationMinutes: durationMinutes,
      clientName: clientName ?? this.clientName,
      clientPhone: clientPhone ?? this.clientPhone,
      assignedMemberId: assignedMemberId,
      assignedMemberName: assignedMemberName,
      groupId: groupId,
      selectedOptions: selectedOptions,
      selectedDesignUrl: selectedDesignUrl,
      selectedDesignLabel: selectedDesignLabel,
      selectedDesignThumbnail: selectedDesignThumbnail,
      selectedDesignIsVideo: selectedDesignIsVideo,
      managementToken: managementToken ?? this.managementToken,
    );
  }

  /// Public fields — written to `appointments/{id}`. No PII.
  Map<String, dynamic> toPublicMap() {
    return {
      'clientId': clientId,
      'salonId': salonId,
      'salonName': salonName,
      'serviceName': serviceName,
      'price': price,
      'dateTime': Timestamp.fromDate(dateTime.toUtc()),
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'durationMinutes': durationMinutes,
      if (assignedMemberId != null) 'assignedMemberId': assignedMemberId,
      if (assignedMemberName != null) 'assignedMemberName': assignedMemberName,
      if (groupId != null) 'groupId': groupId,
      if (selectedOptions != null && selectedOptions!.isNotEmpty) 'selectedOptions': selectedOptions,
      if (selectedDesignUrl != null) 'selectedDesignUrl': selectedDesignUrl,
      if (selectedDesignLabel != null) 'selectedDesignLabel': selectedDesignLabel,
      if (selectedDesignThumbnail != null) 'selectedDesignThumbnail': selectedDesignThumbnail,
      if (selectedDesignIsVideo == true) 'selectedDesignIsVideo': true,
    };
  }

  /// PII fields — written to `appointments/{id}/private/contact`.
  Map<String, dynamic> toPrivateMap() {
    return {
      if (clientName != null) 'clientName': clientName,
      if (clientPhone != null) 'clientPhone': clientPhone,
      if (managementToken != null) 'managementToken': managementToken,
    };
  }

  Map<String, dynamic> toMap() {
    return {...toPublicMap(), ...toPrivateMap()};
  }
}
