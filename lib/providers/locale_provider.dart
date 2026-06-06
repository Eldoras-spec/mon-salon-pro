import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/locale_service.dart';

final localeProvider = StateNotifierProvider<LocaleNotifier, Locale>((ref) {
  return LocaleNotifier();
});

class LocaleNotifier extends StateNotifier<Locale> {
  LocaleNotifier() : super(const Locale('en')) {
    _init();
  }

  Future<void> _init() async {
    state = await LocaleService.getSavedLocale();
    _syncLangToFirestore(state.languageCode);
  }

  Future<void> setLocale(Locale locale) async {
    state = locale;
    await LocaleService.saveLocale(locale.languageCode);
    _syncLangToFirestore(locale.languageCode);
  }

  void _syncLangToFirestore(String langCode) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    FirebaseFirestore.instance.collection('users').doc(uid).update({
      'lang': langCode,
    }).catchError((_) {});
  }
}
