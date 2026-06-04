import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team_member_model.dart';

/// Currently active team member (null = salon owner is active)
final activeTeamMemberProvider = StateProvider<TeamMemberModel?>((ref) => null);

/// Whether a profile is considered selected (so the app shows the home, not
/// the "Who are you?" selector). Defaults to TRUE: since employees now log in
/// with their own account (employee code → custom token), the owner opens
/// straight on the home page. The selector is only shown on demand, when the
/// owner taps the profile-switcher button (which sets this to false).
final profileSelectedProvider = StateProvider<bool>((ref) => true);

/// Hash a 6-digit PIN using SHA256
String hashPin(String pin) {
  final bytes = utf8.encode(pin);
  return sha256.convert(bytes).toString();
}
