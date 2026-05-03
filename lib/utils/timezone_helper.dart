import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class TimezoneOption {
  final String iana;
  final String label;
  const TimezoneOption(this.iana, this.label);
}

class TimezoneHelper {
  /// Curated short list — covers the markets currently in scope. Add
  /// entries as expansion happens; the picker dropdown reads from here.
  static const List<TimezoneOption> commonTimezones = [
    TimezoneOption('Africa/Casablanca', 'Maroc — Casablanca (UTC+1)'),
    TimezoneOption('Africa/Algiers', 'Algérie — Alger (UTC+1)'),
    TimezoneOption('Africa/Tunis', 'Tunisie — Tunis (UTC+1)'),
    TimezoneOption('Africa/Cairo', 'Égypte — Le Caire (UTC+2)'),
    TimezoneOption('Africa/Lagos', 'Nigeria — Lagos (UTC+1)'),
    TimezoneOption('Africa/Dakar', 'Sénégal — Dakar (UTC+0)'),
    TimezoneOption('Africa/Abidjan', "Côte d'Ivoire — Abidjan (UTC+0)"),
    TimezoneOption('Europe/Paris', 'France — Paris (UTC+1/+2)'),
    TimezoneOption('Europe/London', 'Royaume-Uni — Londres (UTC+0/+1)'),
    TimezoneOption('Europe/Madrid', 'Espagne — Madrid (UTC+1/+2)'),
    TimezoneOption('Europe/Brussels', 'Belgique — Bruxelles (UTC+1/+2)'),
    TimezoneOption('Europe/Berlin', 'Allemagne — Berlin (UTC+1/+2)'),
    TimezoneOption('Europe/Rome', 'Italie — Rome (UTC+1/+2)'),
    TimezoneOption('America/New_York', 'États-Unis — Côte Est (UTC-5/-4)'),
    TimezoneOption('America/Chicago', 'États-Unis — Centre (UTC-6/-5)'),
    TimezoneOption('America/Denver', 'États-Unis — Montagne (UTC-7/-6)'),
    TimezoneOption('America/Los_Angeles', 'États-Unis — Côte Ouest (UTC-8/-7)'),
    TimezoneOption('America/Toronto', 'Canada — Toronto (UTC-5/-4)'),
    TimezoneOption('America/Montreal', 'Canada — Montréal (UTC-5/-4)'),
    TimezoneOption('Asia/Dubai', 'EAU — Dubaï (UTC+4)'),
    TimezoneOption('Asia/Riyadh', 'Arabie Saoudite — Riyad (UTC+3)'),
    TimezoneOption('Asia/Istanbul', 'Turquie — Istanbul (UTC+3)'),
  ];

  static const String defaultTimezone = 'Africa/Casablanca';

  static bool _tzInitialized = false;
  static void _ensureTzInitialized() {
    if (_tzInitialized) return;
    tzdata.initializeTimeZones();
    _tzInitialized = true;
  }

  /// Best-effort device timezone detection.
  /// Returns an IANA name when the platform exposes one (Android/iOS via
  /// `DateTime.now().timeZoneName`), otherwise resolves to the best
  /// matching IANA from the curated list using the current UTC offset.
  /// Falls back to `Africa/Casablanca` — the bulk of current salons.
  static String detectDeviceTimezone() {
    final reported = DateTime.now().timeZoneName.trim();
    // Android & iOS often return the IANA name directly.
    if (reported.contains('/') &&
        commonTimezones.any((t) => t.iana == reported)) {
      return reported;
    }
    // Fall back to offset matching against the curated list.
    _ensureTzInitialized();
    final nowOffsetMinutes = DateTime.now().timeZoneOffset.inMinutes;
    final now = DateTime.now().toUtc();
    for (final opt in commonTimezones) {
      try {
        final loc = tz.getLocation(opt.iana);
        final localTime = tz.TZDateTime.from(now, loc);
        if (localTime.timeZoneOffset.inMinutes == nowOffsetMinutes) {
          return opt.iana;
        }
      } catch (_) {
        continue;
      }
    }
    return defaultTimezone;
  }

  /// Current wall-clock time in the given salon timezone. Used by every
  /// booking surface (reschedule sheet, slot pickers, "today" filters)
  /// so the UI speaks the salon's local time, not the device's. Falls
  /// back to `DateTime.now()` if the IANA name is unknown.
  static DateTime salonNow(String? tzName) {
    final name = (tzName == null || tzName.trim().isEmpty)
        ? defaultTimezone
        : tzName;
    _ensureTzInitialized();
    try {
      return tz.TZDateTime.now(tz.getLocation(name));
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Salon-local "today" as a date-only DateTime (midnight). Convenient
  /// for date pickers / "is this day in the past?" checks.
  static DateTime salonToday(String? tzName) {
    final n = salonNow(tzName);
    return DateTime(n.year, n.month, n.day);
  }

  /// Resolves the human label for a given IANA — falls back to the IANA
  /// itself when the timezone isn't in the curated list (defensive).
  static String labelFor(String iana) {
    return commonTimezones
        .firstWhere(
          (t) => t.iana == iana,
          orElse: () => TimezoneOption(iana, iana),
        )
        .label;
  }
}
