/// Lenient decimal parsing for price / amount fields: accepts "49,90" as
/// well as "49.90" and ignores surrounding spaces. Returns null when empty
/// or unparsable.
double? parseDecimal(String raw) {
  final s = raw.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (s.isEmpty) return null;
  return double.tryParse(s);
}

/// Pre-fills an edit field without losing cents: 50 → "50", 49.9 → "49.9",
/// 49.95 → "49.95". `toStringAsFixed(0)` used to round 49.90 up to 50 on
/// every edit.
String formatDecimal(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  var s = value.toStringAsFixed(2);
  if (s.endsWith('0')) s = s.substring(0, s.length - 1);
  return s;
}
