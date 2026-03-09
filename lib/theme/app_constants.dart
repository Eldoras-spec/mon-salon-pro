import 'package:flutter/material.dart';

class AppConstants {
  static const List<Map<String, dynamic>> categories = [
    {'name': 'Coiffure', 'icon': Icons.cut},
    {'name': 'Brushing', 'icon': Icons.air},
    {'name': 'Ongles', 'icon': Icons.back_hand},
    {'name': 'Épilation', 'icon': Icons.auto_fix_high},
    {'name': 'Visage', 'icon': Icons.face},
    {'name': 'Massage', 'icon': Icons.spa},
    {'name': 'Maquillage', 'icon': Icons.brush},
    {'name': 'Coloration', 'icon': Icons.palette},
    {'name': 'Soin capillaire', 'icon': Icons.water_drop},
    {'name': 'Autre', 'icon': Icons.more_horiz},
  ];

  static List<String> get categoryNames =>
      categories.map((c) => c['name'] as String).toList();
}
