/// Countries whose phone numbers are accepted across the app (SMS OTP,
/// WhatsApp numbers, etc.). Must stay in sync with the Firebase Auth
/// SMS Region allowlist configured in the console.
class Country {
  final String code; // ISO 3166-1 alpha-2
  final String name; // French display name
  final String dial; // E.164 dial code (with '+')
  final String flag; // Emoji

  const Country({
    required this.code,
    required this.name,
    required this.dial,
    required this.flag,
  });
}

const List<Country> kAllowedCountries = [
  // Maghreb + Afrique arabe
  Country(code: 'MA', name: 'Maroc', dial: '+212', flag: '🇲🇦'),
  Country(code: 'DZ', name: 'Algérie', dial: '+213', flag: '🇩🇿'),
  Country(code: 'TN', name: 'Tunisie', dial: '+216', flag: '🇹🇳'),
  Country(code: 'LY', name: 'Libye', dial: '+218', flag: '🇱🇾'),
  Country(code: 'EG', name: 'Égypte', dial: '+20', flag: '🇪🇬'),
  Country(code: 'SD', name: 'Soudan', dial: '+249', flag: '🇸🇩'),
  Country(code: 'MR', name: 'Mauritanie', dial: '+222', flag: '🇲🇷'),
  Country(code: 'DJ', name: 'Djibouti', dial: '+253', flag: '🇩🇯'),
  Country(code: 'KM', name: 'Comores', dial: '+269', flag: '🇰🇲'),
  // Europe
  Country(code: 'FR', name: 'France', dial: '+33', flag: '🇫🇷'),
  Country(code: 'BE', name: 'Belgique', dial: '+32', flag: '🇧🇪'),
  Country(code: 'ES', name: 'Espagne', dial: '+34', flag: '🇪🇸'),
  Country(code: 'LU', name: 'Luxembourg', dial: '+352', flag: '🇱🇺'),
  Country(code: 'CH', name: 'Suisse', dial: '+41', flag: '🇨🇭'),
  Country(code: 'GB', name: 'Royaume-Uni', dial: '+44', flag: '🇬🇧'),
  Country(code: 'IE', name: 'Irlande', dial: '+353', flag: '🇮🇪'),
  // Amérique du Nord
  Country(code: 'US', name: 'États-Unis', dial: '+1', flag: '🇺🇸'),
  Country(code: 'CA', name: 'Canada', dial: '+1', flag: '🇨🇦'),
  // Afrique francophone
  Country(code: 'SN', name: 'Sénégal', dial: '+221', flag: '🇸🇳'),
  Country(code: 'CI', name: 'Côte d\'Ivoire', dial: '+225', flag: '🇨🇮'),
  Country(code: 'ML', name: 'Mali', dial: '+223', flag: '🇲🇱'),
  Country(code: 'CM', name: 'Cameroun', dial: '+237', flag: '🇨🇲'),
  Country(code: 'GA', name: 'Gabon', dial: '+241', flag: '🇬🇦'),
  Country(code: 'CG', name: 'Congo-Brazzaville', dial: '+242', flag: '🇨🇬'),
  Country(code: 'CD', name: 'RDC', dial: '+243', flag: '🇨🇩'),
  Country(code: 'TG', name: 'Togo', dial: '+228', flag: '🇹🇬'),
  Country(code: 'BJ', name: 'Bénin', dial: '+229', flag: '🇧🇯'),
  Country(code: 'BF', name: 'Burkina Faso', dial: '+226', flag: '🇧🇫'),
  Country(code: 'NE', name: 'Niger', dial: '+227', flag: '🇳🇪'),
  Country(code: 'TD', name: 'Tchad', dial: '+235', flag: '🇹🇩'),
  Country(code: 'MG', name: 'Madagascar', dial: '+261', flag: '🇲🇬'),
  Country(code: 'GN', name: 'Guinée', dial: '+224', flag: '🇬🇳'),
  Country(code: 'CF', name: 'Centrafrique', dial: '+236', flag: '🇨🇫'),
  // Golfe + Levant
  Country(code: 'SA', name: 'Arabie saoudite', dial: '+966', flag: '🇸🇦'),
  Country(code: 'AE', name: 'Émirats arabes unis', dial: '+971', flag: '🇦🇪'),
  Country(code: 'KW', name: 'Koweït', dial: '+965', flag: '🇰🇼'),
  Country(code: 'QA', name: 'Qatar', dial: '+974', flag: '🇶🇦'),
  Country(code: 'BH', name: 'Bahreïn', dial: '+973', flag: '🇧🇭'),
  Country(code: 'OM', name: 'Oman', dial: '+968', flag: '🇴🇲'),
  Country(code: 'LB', name: 'Liban', dial: '+961', flag: '🇱🇧'),
  Country(code: 'SY', name: 'Syrie', dial: '+963', flag: '🇸🇾'),
  Country(code: 'JO', name: 'Jordanie', dial: '+962', flag: '🇯🇴'),
  Country(code: 'PS', name: 'Palestine', dial: '+970', flag: '🇵🇸'),
];

Country? findCountryByCode(String? iso2) {
  if (iso2 == null) return null;
  final upper = iso2.toUpperCase();
  for (final c in kAllowedCountries) {
    if (c.code == upper) return c;
  }
  return null;
}

Country? findCountryByDial(String dial) {
  // Multiple countries share a dial code (US/CA +1): return the first match.
  for (final c in kAllowedCountries) {
    if (c.dial == dial) return c;
  }
  return null;
}

const Country kDefaultCountry = Country(
  code: 'MA',
  name: 'Maroc',
  dial: '+212',
  flag: '🇲🇦',
);
