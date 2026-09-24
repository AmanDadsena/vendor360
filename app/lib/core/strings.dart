import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';

import '../app/providers.dart';

/// On-screen strings in Hindi, Marathi and English.
///
/// The UI/UX guide requires all primary flows in all three, selected once at
/// onboarding, governing both voice and text. A hand-rolled table rather than
/// generated ARB files: three languages and a bounded string set do not
/// justify a code-generation step, and keeping the translations side by side
/// makes a missing one obvious at a glance.
class Strings {
  const Strings(this.language);

  final AppLanguage language;

  String _pick(String en, String hi, String mr) => switch (language) {
        AppLanguage.hindi => hi,
        AppLanguage.marathi => mr,
        AppLanguage.english => en,
      };

  // Navigation
  String get home => _pick('Home', 'होम', 'होम');
  String get inventory => _pick('Stock', 'स्टॉक', 'स्टॉक');
  String get speak => _pick('Speak', 'बोलें', 'बोला');
  String get forecast => _pick('Forecast', 'अनुमान', 'अंदाज');
  String get score => _pick('Score', 'स्कोर', 'स्कोअर');

  // Onboarding
  String get welcome => _pick(
        'Your store, one step ahead',
        'आपकी दुकान, एक कदम आगे',
        'तुमचे दुकान, एक पाऊल पुढे',
      );
  String get welcomeDetail => _pick(
        'Log stock by speaking. Know what will sell before it does.',
        'बोलकर स्टॉक दर्ज करें। जानें क्या बिकेगा, पहले से।',
        'बोलून स्टॉक नोंदवा. काय विकले जाईल ते आधीच जाणून घ्या.',
      );
  String get chooseLanguage =>
      _pick('Choose your language', 'अपनी भाषा चुनें', 'तुमची भाषा निवडा');
  String get phoneNumber =>
      _pick('Mobile number', 'मोबाइल नंबर', 'मोबाइल नंबर');
  String get sendCode => _pick('Send code', 'कोड भेजें', 'कोड पाठवा');
  String get enterCode =>
      _pick('Enter the 6-digit code', '6 अंकों का कोड डालें', '6 अंकी कोड टाका');
  String get verify => _pick('Verify', 'सत्यापित करें', 'पडताळणी करा');
  String get changeNumber =>
      _pick('Change number', 'नंबर बदलें', 'नंबर बदला');

  // Dashboard
  String get todaySales => _pick("Today's sales", 'आज की बिक्री', 'आजची विक्री');
  String get thisWeek => _pick('This week', 'इस सप्ताह', 'या आठवड्यात');
  String get lowStock => _pick('Low stock', 'कम स्टॉक', 'कमी स्टॉक');
  String get expiringSoon =>
      _pick('Expiring soon', 'जल्द खराब होगा', 'लवकर खराब होईल');
  String get atRisk => _pick('at risk', 'जोखिम में', 'धोक्यात');
  String get healthScore =>
      _pick('Health Score', 'हेल्थ स्कोर', 'हेल्थ स्कोअर');
  String get tapToSpeak =>
      _pick('Tap to log a sale', 'बिक्री दर्ज करने के लिए दबाएँ', 'विक्री नोंदवण्यासाठी दाबा');
  String get quickActions =>
      _pick('Quick actions', 'त्वरित कार्य', 'जलद कृती');
  String get scanReceipt =>
      _pick('Scan receipt', 'रसीद स्कैन करें', 'पावती स्कॅन करा');

  // Voice
  String get listening => _pick('Listening…', 'सुन रहे हैं…', 'ऐकत आहे…');
  String get speakNow => _pick(
        'Say what you sold',
        'बोलिए क्या बेचा',
        'काय विकले ते सांगा',
      );
  String get voiceExample => _pick(
        'For example: "sold 20 milk packets and 5 kg rice"',
        'जैसे: "20 दूध पैकेट और 5 किलो चावल बेचे"',
        'उदा: "20 दूध पॅकेट आणि 5 किलो तांदूळ विकले"',
      );
  String get checkBeforeSaving => _pick(
        'Check before saving',
        'सहेजने से पहले जाँचें',
        'जतन करण्यापूर्वी तपासा',
      );
  String get confirmAndSave =>
      _pick('Confirm and save', 'पुष्टि करें और सहेजें', 'पुष्टी करा आणि जतन करा');
  String get cancel => _pick('Cancel', 'रद्द करें', 'रद्द करा');
  String get tryAgain => _pick('Try again', 'फिर कोशिश करें', 'पुन्हा प्रयत्न करा');

  // Inventory
  String get allItems => _pick('All', 'सभी', 'सर्व');
  String get reorderAt => _pick('Reorder at', 'दोबारा मंगाएँ', 'पुन्हा मागवा');
  String get inStock => _pick('In stock', 'स्टॉक में', 'स्टॉकमध्ये');
  String get reorderNow => _pick('Reorder now', 'अभी मंगाएँ', 'आता मागवा');
  String get outOfStock => _pick('Out of stock', 'स्टॉक खत्म', 'स्टॉक संपला');

  // Forecast
  String get comingDays => _pick('Next 7 days', 'अगले 7 दिन', 'पुढील 7 दिवस');
  String get whyThis => _pick('Why this?', 'क्यों?', 'का?');

  // Health score
  String get outOf100 => _pick('out of 100', '100 में से', '100 पैकी');
  String get shareWithLender => _pick(
        'Share with lenders',
        'ऋणदाता के साथ साझा करें',
        'कर्जदात्यासोबत सामायिक करा',
      );
  String get consentNote => _pick(
        'Your score is never shared until you turn this on.',
        'जब तक आप चालू न करें, आपका स्कोर साझा नहीं होता।',
        'तुम्ही चालू करेपर्यंत तुमचा स्कोअर सामायिक होत नाही.',
      );

  // Sync
  String get queued => _pick('waiting to sync', 'सिंक बाकी', 'सिंक बाकी');
  String get allSynced => _pick('All saved', 'सब सहेजा गया', 'सर्व जतन झाले');
  String get workingOffline => _pick(
        'Working offline — nothing is lost',
        'ऑफ़लाइन काम कर रहे हैं — कुछ नहीं खोएगा',
        'ऑफलाइन काम करत आहे — काहीही हरवणार नाही',
      );

  // Common
  String get save => _pick('Save', 'सहेजें', 'जतन करा');
  String get retry => _pick('Retry', 'फिर से', 'पुन्हा');
  String get loading => _pick('Loading…', 'लोड हो रहा है…', 'लोड होत आहे…');
  String get noData => _pick('Nothing here yet', 'अभी कुछ नहीं', 'अजून काही नाही');
  String get seeAll => _pick('See all', 'सभी देखें', 'सर्व पहा');
  String get continueLabel => _pick('Continue', 'आगे बढ़ें', 'पुढे जा');

  // Home
  String get runningOut => _pick('Running out', 'खत्म हो रहा है', 'संपत आहे');
  String get reorder => _pick('Reorder', 'मंगाएँ', 'मागवा');
  String get left => _pick('left', 'बचा', 'शिल्लक');
  String get entries => _pick('entries', 'एंट्री', 'नोंदी');
  String get noSalesYet => _pick(
        'Nothing logged yet today. Tap the mic to add a sale.',
        'आज अभी कुछ दर्ज नहीं हुआ। बिक्री जोड़ने के लिए माइक दबाएँ।',
        'आज अजून काही नोंदवले नाही. विक्री जोडण्यासाठी माइक दाबा.',
      );
  String get allAboveReorder => _pick(
        'Everything is above its reorder point.',
        'सब कुछ दोबारा मंगाने के स्तर से ऊपर है।',
        'सर्व काही पुन्हा मागवण्याच्या पातळीच्या वर आहे.',
      );
  String get orders => _pick('Orders', 'ऑर्डर', 'ऑर्डर');
  String get suppliers => _pick('Suppliers', 'सप्लायर', 'पुरवठादार');
  String get demandMap => _pick('Demand map', 'मांग नक्शा', 'मागणी नकाशा');
  String get bulkDeals => _pick('Bulk deals', 'थोक सौदे', 'घाऊक सौदे');
  String get accuracy =>
      _pick('Forecast accuracy', 'अनुमान की सटीकता', 'अंदाजाची अचूकता');
  /// Matches the server's window: the dashboard counts stock that expires
  /// within three days, so the label says three days, not "this week".
  // Day close and the paper it produces
  String get dayClose => _pick('Day close', 'दिन का हिसाब', 'दिवसाचा हिशोब');
  String get cashIn => _pick('cash in', 'नकद मिला', 'रोख मिळाले');
  String get wasted => _pick('wasted', 'बर्बाद', 'वाया');
  String get givenOnUdhaar =>
      _pick('Given on udhaar', 'उधार दिया', 'उधार दिले');
  String get collectedOnUdhaar =>
      _pick('Collected on udhaar', 'उधार वसूला', 'उधार वसूल');
  String get last14Days =>
      _pick('Last 14 days', 'पिछले 14 दिन', 'मागील 14 दिवस');
  String get soldMost => _pick('Sold most', 'सबसे ज़्यादा बिका', 'सर्वाधिक विकले');
  String get takeItWithYou =>
      _pick('Take it with you', 'साथ ले जाएँ', 'सोबत न्या');
  String get daySheet => _pick('Day sheet (PDF)', 'दिन का पर्चा (PDF)',
      'दिवसाचा कागद (PDF)');
  String get creditReport => _pick('Credit report (PDF)',
      'क्रेडिट रिपोर्ट (PDF)', 'क्रेडिट अहवाल (PDF)');
  String get ledgerWorkbook =>
      _pick('Ledger (Excel)', 'बही (Excel)', 'वही (Excel)');

  // Udhaar — the customer credit book
  String get udhaar => _pick('Udhaar', 'उधार', 'उधार');
  String get owedToYou => _pick('owed to you', 'आपको मिलना है', 'तुम्हाला येणे');
  String get addCustomer =>
      _pick('Add customer', 'ग्राहक जोड़ें', 'ग्राहक जोडा');
  String get customerName => _pick('Name', 'नाम', 'नाव');
  String get phoneOptional =>
      _pick('Phone (optional)', 'फ़ोन (वैकल्पिक)', 'फोन (ऐच्छिक)');
  String get tookGoods => _pick('Took goods', 'सामान लिया', 'माल घेतला');
  String get paidBack => _pick('Paid', 'चुकाया', 'दिले');
  String get remind => _pick('Remind', 'याद दिलाएँ', 'आठवण करा');
  String get amount => _pick('Amount', 'रकम', 'रक्कम');
  String get whatFor => _pick('What for? (optional)', 'किसलिए? (वैकल्पिक)',
      'कशासाठी? (ऐच्छिक)');
  String get nobodyOwes => _pick(
        'Nobody owes you right now.',
        'अभी किसी से कुछ लेना नहीं है।',
        'सध्या कोणाकडून काही येणे नाही.',
      );
  String get settled => _pick('Settled', 'चुकता', 'चुकते');
  String get oldest => _pick('oldest', 'सबसे पुराना', 'सर्वात जुने');
  String get customers => _pick('customers', 'ग्राहक', 'ग्राहक');
  String daysOld(int days) => switch (language) {
        AppLanguage.hindi => '$days दिन से',
        AppLanguage.marathi => '$days दिवसांपासून',
        AppLanguage.english => days == 1 ? '1 day' : '$days days',
      };

  String get expiringSoonWindow => _pick(
        'expiring in 3 days',
        '3 दिन में खराब होंगे',
        '3 दिवसांत संपणार',
      );
}

/// Strings for the currently selected language.
final stringsProvider = Provider<Strings>(
  (ref) => Strings(ref.watch(languageProvider)),
);

extension StringsContext on WidgetRef {
  Strings get s => read(stringsProvider);
}
