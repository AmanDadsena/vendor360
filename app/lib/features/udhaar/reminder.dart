import 'package:intl/intl.dart';
import 'package:vendor360_core/vendor360_core.dart';

/// Composes the message a shopkeeper would send about an unpaid balance.
///
/// Pure text, deliberately: the app **composes**, the shopkeeper **sends**.
/// Wiring this to an SMS or WhatsApp API would mean the app messaging a
/// customer who never agreed to hear from it, which needs consent plumbing
/// this product does not have — and a reminder that arrives from a shop's own
/// number is the one that gets paid anyway.
///
/// Written in the shop's language, because the customer reads it, not the app.
String reminderMessage({
  required String shopName,
  required String customerName,
  required Money owed,
  required DateTime since,
  required AppLanguage language,
}) {
  final date = DateFormat('d MMM').format(since);
  final amount = owed.display;

  return switch (language) {
    AppLanguage.hindi => 'नमस्ते $customerName जी, $shopName में आपका '
        '$amount बकाया है ($date से)। सुविधा हो तो चुका दीजिए। धन्यवाद।',
    AppLanguage.marathi => 'नमस्कार $customerName, $shopName मध्ये तुमचे '
        '$amount बाकी आहे ($date पासून). सोयीनुसार द्या. धन्यवाद.',
    AppLanguage.english => 'Hello $customerName, $amount is pending at '
        '$shopName since $date. Please settle when convenient. Thank you.',
  };
}
