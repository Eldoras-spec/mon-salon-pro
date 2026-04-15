import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleService {
  static const _key = 'app_locale';
  static const supportedLocales = [
    Locale('fr'),
    Locale('en'),
    Locale('ar'),
    Locale('es'),
  ];

  /// Get saved locale, or auto-detect from phone settings.
  static Future<Locale> getSavedLocale() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    if (saved != null) {
      return Locale(saved);
    }
    return _detectLocale();
  }

  /// Auto-detect from phone language settings.
  static Locale _detectLocale() {
    final phoneLang = ui.PlatformDispatcher.instance.locale.languageCode;
    if (['fr', 'en', 'ar', 'es'].contains(phoneLang)) return Locale(phoneLang);
    return const Locale('fr');
  }

  /// Save user's manual choice.
  static Future<void> saveLocale(String langCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, langCode);
  }

  /// Reset to auto-detect (remove saved preference).
  static Future<void> resetToAuto() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
