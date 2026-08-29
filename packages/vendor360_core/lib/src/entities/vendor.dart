/// The signed-in vendor.
class Vendor {
  const Vendor({
    required this.id,
    required this.name,
    required this.storeName,
    required this.phone,
    required this.language,
    this.locality,
    this.city = 'Pune',
    this.lat,
    this.lon,
    this.healthScore,
    this.supplierLeadDays = 2,
  });

  final String id;
  final String name;
  final String storeName;
  final String phone;
  final AppLanguage language;
  final String? locality;
  final String city;
  final double? lat;
  final double? lon;
  final double? healthScore;
  final int supplierLeadDays;

  /// Masked for display.
  ///
  /// The phone number is the account identifier and, with store location, the
  /// only PII collected (TRD 8). It is not rendered in full on a screen a
  /// customer standing at the counter can read over the vendor's shoulder.
  String get maskedPhone =>
      phone.length < 4 ? phone : '••••••${phone.substring(phone.length - 4)}';

  /// Initials for the avatar, from the store name rather than the owner's —
  /// the store is what the vendor recognises as theirs.
  String get initials {
    final words = storeName.trim().split(RegExp(r'\s+'));
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words.first[0].toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}

enum AppLanguage { hindi, marathi, english }

extension AppLanguageX on AppLanguage {
  /// ISO code driving both the Bhashini locale and on-screen strings.
  String get code => switch (this) {
        AppLanguage.hindi => 'hi',
        AppLanguage.marathi => 'mr',
        AppLanguage.english => 'en',
      };

  /// BCP-47 tag for speech recognition.
  String get speechLocale => switch (this) {
        AppLanguage.hindi => 'hi-IN',
        AppLanguage.marathi => 'mr-IN',
        AppLanguage.english => 'en-IN',
      };

  /// Endonym. A language picker that names languages in a language the user
  /// may not read is not a language picker.
  String get nativeName => switch (this) {
        AppLanguage.hindi => 'हिन्दी',
        AppLanguage.marathi => 'मराठी',
        AppLanguage.english => 'English',
      };

  String get englishName => switch (this) {
        AppLanguage.hindi => 'Hindi',
        AppLanguage.marathi => 'Marathi',
        AppLanguage.english => 'English',
      };
}

AppLanguage languageFromCode(String code) => switch (code) {
      'mr' => AppLanguage.marathi,
      'en' => AppLanguage.english,
      _ => AppLanguage.hindi,
    };
