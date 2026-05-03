import 'dart:io' show Platform;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// Thin wrapper around RevenueCat's `Purchases` SDK.
///
/// - Configured once at app start via [initialize].
/// - Call [loginUser] after Firebase Auth sign-in so the RC subscriber ID
///   matches the Firebase UID (server webhooks use the same ID to update
///   the salon plan).
/// - Call [logoutUser] on sign-out.
///
/// Entitlement checks and purchase flows live in the UI (OwnerUpgradeScreen).
class RevenueCatService {
  // Public SDK keys — safe to ship in the app binary.
  // Android key will be added when we wire Google Play Billing.
  static const String _iosApiKey = 'appl_fwZVnJtEfBKIBQADmepumjRAGkl';
  static const String _androidApiKey = '';

  /// RevenueCat entitlement identifiers — must match those defined in the
  /// RevenueCat dashboard (Product catalog → Entitlements).
  static const String entitlementEssentiel = 'essentiel';
  static const String entitlementBusiness = 'business';

  /// Offering identifier queried at runtime — matches the "default"
  /// offering defined in RevenueCat with 2 packages: essentiel_monthly,
  /// business_monthly.
  static const String defaultOfferingId = 'default';
  static const String packageEssentielMonthly = 'essentiel_monthly';
  static const String packageBusinessMonthly = 'business_monthly';

  static bool _initialized = false;

  /// Configure the SDK with the platform-specific API key. Safe to call
  /// multiple times — subsequent calls are no-ops.
  static Future<void> initialize() async {
    if (_initialized) return;

    String? apiKey;
    if (Platform.isIOS) {
      apiKey = _iosApiKey;
    } else if (Platform.isAndroid && _androidApiKey.isNotEmpty) {
      apiKey = _androidApiKey;
    }
    if (apiKey == null || apiKey.isEmpty) return;

    await Purchases.setLogLevel(
      kDebugMode ? LogLevel.debug : LogLevel.warn,
    );
    await Purchases.configure(PurchasesConfiguration(apiKey));
    _initialized = true;
  }

  /// Identify the current Firebase user to RevenueCat. After login the
  /// webhook events sent to the Cloud Function will carry this UID as
  /// `app_user_id`, letting the CF look up `salons/{uid}` directly.
  static Future<void> loginUser(String firebaseUid) async {
    if (!_initialized) return;
    try {
      await Purchases.logIn(firebaseUid);
    } catch (e) {
      debugPrint('RevenueCatService.loginUser failed: $e');
    }
  }

  /// Clear the RC identity on sign-out — future purchases are attributed
  /// to a new anonymous ID until the next login.
  static Future<void> logoutUser() async {
    if (!_initialized) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      // Happens if the user was already anonymous — safe to ignore.
      debugPrint('RevenueCatService.logoutUser: $e');
    }
  }

  /// Sync the current Firebase Auth user to RC at app start (handles
  /// the case where the user is already signed in when main() runs).
  static Future<void> syncCurrentUser() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) await loginUser(uid);
  }
}
