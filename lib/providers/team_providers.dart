import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team_member_model.dart';

/// Currently active team member (null = salon owner is active)
final activeTeamMemberProvider = StateProvider<TeamMemberModel?>((ref) => null);

/// Whether the profile selector has been shown this session
final profileSelectedProvider = StateProvider<bool>((ref) => false);

/// Hash a 6-digit PIN using SHA256
String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}
