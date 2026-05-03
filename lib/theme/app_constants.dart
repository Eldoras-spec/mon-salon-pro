import 'package:flutter/material.dart';

class AppConstants {
  static const List<Map<String, dynamic>> femmeCategories = [
    {'name': 'Coupe', 'icon': Icons.content_cut},
    {'name': 'Coiffure', 'icon': Icons.cut},
    {'name': 'Cils & Sourcils', 'icon': Icons.visibility},
    {'name': 'Ongles', 'icon': Icons.back_hand},
    {'name': 'Épilation', 'icon': Icons.auto_fix_high},
    {'name': 'Visage', 'icon': Icons.face},
    {'name': 'Massage', 'icon': Icons.spa},
    {'name': 'Maquillage', 'icon': Icons.brush},
    {'name': 'Coloration', 'icon': Icons.palette},
    {'name': 'Soin capillaire', 'icon': Icons.water_drop},
    {'name': 'Autre', 'icon': Icons.more_horiz},
  ];

  static const List<Map<String, dynamic>> hommeCategories = [
    {'name': 'Coupe', 'icon': Icons.content_cut},
    {'name': 'Coiffure', 'icon': Icons.cut},
    {'name': 'Barbe', 'icon': Icons.face_retouching_natural},
    {'name': 'Hammam & Spa', 'icon': Icons.hot_tub},
    {'name': 'Soin visage', 'icon': Icons.face},
    {'name': 'Manucure', 'icon': Icons.back_hand},
    {'name': 'Massage', 'icon': Icons.spa},
    {'name': 'Soin corps', 'icon': Icons.self_improvement},
    {'name': 'Tatouage', 'icon': Icons.draw},
    {'name': 'Autre', 'icon': Icons.more_horiz},
  ];

  /// Returns categories based on salon type.
  static List<Map<String, dynamic>> categoriesFor(String salonType) {
    switch (salonType) {
      case 'homme':
        return hommeCategories;
      case 'mixte':
        return [...femmeCategories, ...hommeCategories.where(
          (h) => !femmeCategories.any((f) => f['name'] == h['name']),
        )];
      default:
        return femmeCategories;
    }
  }

  /// Legacy accessor — defaults to femme categories.
  static List<Map<String, dynamic>> get categories => femmeCategories;

  static List<String> categoryNamesFor(String salonType) =>
      categoriesFor(salonType).map((c) => c['name'] as String).toList();

  static List<String> get categoryNames =>
      femmeCategories.map((c) => c['name'] as String).toList();
}
