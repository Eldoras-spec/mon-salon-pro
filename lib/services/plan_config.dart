import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io' show Platform;

/// Static pricing + capacity rules for the 3 subscription tiers.
/// Keep in sync with:
///  - functions/src/index.ts (PLAN_PRICES map)
///
/// Prices are monthly, quoted per ISO currency. The Free plan tier is
/// always 0; Essentiel and Business have local-currency psychological
/// prices (rounded to xx9/x9 where it makes sense).
///
/// Free tier cap is enforced on team-member count (see [freeTeamMemberCap]),
/// not on revenue. Bookings are never blocked by plan.
class PlanConfig {
  static const String planFree = 'free';
  static const String planEssentiel = 'essentiel';
  static const String planBusiness = 'business';

  static const List<String> allPlans = [planFree, planEssentiel, planBusiness];

  /// Free plan: max number of team members (gerant + member docs under
  /// `salons/{id}/teamMembers`). Owner is not counted — only team docs.
  static const int freeTeamMemberCap = 2;

  /// Monthly subscription prices per plan per currency.
  /// Aligned with Apple App Store Connect overrides (2026-04-24). Native
  /// display currencies (MAD/XOF/TND/DZD) are marketing equivalents —
  /// Apple actually bills in USD for those storefronts. Other currencies
  /// (USD/EUR/GBP/CAD/CHF) match what the native Apple Sheet will charge.
  static const Map<String, Map<String, num>> prices = {
    planFree: {
      'MAD': 0, 'EUR': 0, 'USD': 0, 'XOF': 0,
      'TND': 0, 'DZD': 0, 'GBP': 0, 'CAD': 0, 'CHF': 0,
    },
    planEssentiel: {
      'MAD': 199,
      'EUR': 22.99,
      'USD': 19.99,
      'XOF': 11500,
      'TND': 59,
      'DZD': 2699,
      'GBP': 19.99,
      'CAD': 24.99,
      'CHF': 22.99,
    },
    planBusiness: {
      'MAD': 499,
      'EUR': 59.99,
      'USD': 53.99,
      'XOF': 32900,
      'TND': 169,
      'DZD': 7499,
      'GBP': 49.99,
      'CAD': 64.99,
      'CHF': 60,
    },
  };

  /// Length of the Essentiel free trial in days.
  static const int essentielTrialDays = 90; // 3 months

  /// Country ISO-2 → local currency mapping.
  /// WAEMU (Western African CFA franc) uses XOF.
  static const Map<String, String> countryToCurrency = {
    'MA': 'MAD',
    'DZ': 'DZD',
    'TN': 'TND',
    'FR': 'EUR', 'BE': 'EUR', 'ES': 'EUR', 'PT': 'EUR', 'IT': 'EUR',
    'DE': 'EUR', 'NL': 'EUR', 'AT': 'EUR', 'IE': 'EUR', 'FI': 'EUR',
    'GR': 'EUR', 'LU': 'EUR',
    'CH': 'CHF',
    'US': 'USD',
    // WAEMU / CEMAC zones
    'SN': 'XOF', 'CI': 'XOF', 'BF': 'XOF', 'ML': 'XOF', 'NE': 'XOF',
    'TG': 'XOF', 'BJ': 'XOF', 'CM': 'XOF', 'GA': 'XOF', 'CG': 'XOF',
    'GB': 'GBP',
    'CA': 'CAD',
  };

  /// Get the monthly price for a plan in a given currency.
  /// Falls back to EUR if the currency isn't mapped.
  static num priceFor(String plan, String currency) {
    final map = prices[plan];
    if (map == null) return 0;
    return map[currency] ?? map['EUR'] ?? 0;
  }

  /// Map a country ISO-2 code to its local currency.
  /// Defaults to EUR for unknown countries (safest wide-market default).
  static String currencyForCountry(String countryCode) {
    return countryToCurrency[countryCode.toUpperCase()] ?? 'EUR';
  }

  /// Best-effort currency auto-detection via GeoJS (free, no rate limit,
  /// no API key). Falls back to EUR if the lookup fails.
  /// Cache the result for the app session to avoid repeat calls.
  static String? _cachedCurrency;
  static Future<String> detectCurrencyByIp({Duration timeout =
      const Duration(seconds: 4)}) async {
    if (_cachedCurrency != null) return _cachedCurrency!;
    try {
      final resp = await http
          .get(Uri.parse('https://get.geojs.io/v1/ip/country.json'))
          .timeout(timeout);
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final code = (data['country'] as String?)?.toUpperCase();
        if (code != null && code.isNotEmpty) {
          _cachedCurrency = currencyForCountry(code);
          return _cachedCurrency!;
        }
      }
    } catch (_) { /* swallow — fall through to locale / default */ }

    // Fallback 1: device locale (offline-friendly)
    try {
      final locale = Platform.localeName; // e.g. "fr_MA", "en_US"
      final parts = locale.split(RegExp(r'[_-]'));
      if (parts.length >= 2) {
        final country = parts[1].toUpperCase();
        if (countryToCurrency.containsKey(country)) {
          _cachedCurrency = countryToCurrency[country]!;
          return _cachedCurrency!;
        }
      }
    } catch (_) {}

    // Fallback 2: EUR (most broadly acceptable default)
    _cachedCurrency = 'EUR';
    return _cachedCurrency!;
  }
}
