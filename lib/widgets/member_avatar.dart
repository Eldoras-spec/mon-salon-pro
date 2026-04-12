import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable avatar widget for team members.
/// Shows photo if available, otherwise shows initials with colored background.
class MemberAvatar extends StatelessWidget {
  const MemberAvatar({
    super.key,
    required this.name,
    this.photoUrl,
    this.radius = 20,
    this.fontSize,
    this.backgroundColor,
  });

  final String name;
  final String? photoUrl;
  final double radius;
  final double? fontSize;
  final Color? backgroundColor;

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    if (parts.isNotEmpty && parts[0].isNotEmpty) return parts[0][0].toUpperCase();
    return '?';
  }

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundImage: NetworkImage(photoUrl!),
        backgroundColor: backgroundColor ?? AppColors.brand100,
        onBackgroundImageError: (_, __) {},
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: backgroundColor ?? AppColors.brand100,
      child: Text(
        _initials,
        style: TextStyle(
          fontSize: fontSize ?? radius * 0.8,
          fontWeight: FontWeight.w600,
          color: AppColors.brand700,
        ),
      ),
    );
  }
}
