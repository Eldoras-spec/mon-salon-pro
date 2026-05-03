import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../constants/allowed_countries.dart';

/// Detects the visitor's country once per app run via ipapi.co.
/// Falls back to null on error, timeout or non-allowed country so the
/// caller can decide what to do (usually: default to Morocco).
class IpCountryService {
  static Future<Country?>? _cached;

  static Future<Country?> detect() {
    return _cached ??= _fetch();
  }

  static Future<Country?> _fetch() async {
    try {
      final uri = Uri.parse('https://ipapi.co/json/');
      final res = await http.get(uri).timeout(const Duration(seconds: 3));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final iso = (data['country_code'] as String?)?.toUpperCase();
      if (iso == null) return null;
      return findCountryByCode(iso);
    } catch (_) {
      return null;
    }
  }
}
