/// Currency formatting helper.
/// Formats a price amount with the correct symbol/position for the given currency code.
class CurrencyHelper {
  static const Map<String, _CurrencyInfo> _currencies = {
    'MAD': _CurrencyInfo('MAD', 'MAD', false, 0),
    'EUR': _CurrencyInfo('€', 'EUR', false, 2),
    'USD': _CurrencyInfo('\$', 'USD', true, 2),
    'GBP': _CurrencyInfo('£', 'GBP', true, 2),
    'XOF': _CurrencyInfo('CFA', 'XOF', false, 0),
    'XAF': _CurrencyInfo('FCFA', 'XAF', false, 0),
    'TND': _CurrencyInfo('DT', 'TND', false, 3),
    'DZD': _CurrencyInfo('DA', 'DZD', false, 0),
    'EGP': _CurrencyInfo('E£', 'EGP', true, 2),
    'SAR': _CurrencyInfo('SAR', 'SAR', false, 2),
    'AED': _CurrencyInfo('AED', 'AED', false, 2),
  };

  /// Format a price with the salon's currency.
  /// Returns e.g. "300 MAD", "$25.00", "15 000 CFA"
  static String format(double amount, [String currencyCode = 'MAD']) {
    final info = _currencies[currencyCode] ?? _currencies['MAD']!;
    final formatted = info.decimals == 0
        ? amount.toStringAsFixed(0)
        : amount.toStringAsFixed(info.decimals);

    if (info.symbolBefore) {
      return '${info.symbol}$formatted';
    }
    return '$formatted ${info.symbol}';
  }

  /// Get just the symbol for a currency code.
  static String symbol(String currencyCode) {
    return (_currencies[currencyCode] ?? _currencies['MAD']!).symbol;
  }

  /// List of all supported currencies for dropdown.
  static const List<CurrencyOption> allCurrencies = [
    CurrencyOption('MAD', 'MAD — Dirham marocain'),
    CurrencyOption('EUR', 'EUR — Euro'),
    CurrencyOption('USD', 'USD — Dollar américain'),
    CurrencyOption('GBP', 'GBP — Livre sterling'),
    CurrencyOption('XOF', 'XOF — Franc CFA (Afrique de l\'Ouest)'),
    CurrencyOption('XAF', 'XAF — Franc CFA (Afrique Centrale)'),
    CurrencyOption('TND', 'TND — Dinar tunisien'),
    CurrencyOption('DZD', 'DZD — Dinar algérien'),
    CurrencyOption('EGP', 'EGP — Livre égyptienne'),
    CurrencyOption('SAR', 'SAR — Riyal saoudien'),
    CurrencyOption('AED', 'AED — Dirham émirati'),
  ];
}

class _CurrencyInfo {
  final String symbol;
  final String code;
  final bool symbolBefore;
  final int decimals;
  const _CurrencyInfo(this.symbol, this.code, this.symbolBefore, this.decimals);
}

class CurrencyOption {
  final String code;
  final String label;
  const CurrencyOption(this.code, this.label);
}
