import 'package:flutter/widgets.dart';

/// The Vendor360 type scale.
///
/// Inter, bundled as a package asset rather than fetched at runtime, so
/// typography renders correctly with no network. Tabular figures are enabled
/// on every style — a functional requirement, not a stylistic one: rolling
/// counters jitter without them and price columns fail to align.
///
/// Inter carries no Devanagari, so [devanagari] is bundled behind it as a
/// fallback. This is load-bearing rather than decorative: `language_pref`
/// defaults to `hi`, and without the fallback every Hindi and Marathi string —
/// the language picker's own endonyms included — renders as empty boxes.
@immutable
class V360Typography {
  const V360Typography();

  static const String family = 'Inter';

  /// Devanagari coverage for Hindi and Marathi.
  ///
  /// Must be a bundled package asset, not a platform font name. Flutter
  /// prefixes *every* `fontFamilyFallback` entry with `packages/$package/`
  /// when [package] is set, so a system family named here would resolve to
  /// nothing at all — and would do it silently, with no error and no glyphs.
  static const String devanagari = 'NotoSansDevanagari';

  static const String package = 'vendor360_ui';

  /// Package-qualified family names, for the few places that set a font
  /// without going through [_style] — `ThemeData` most importantly, since it
  /// supplies the default for dialogs, snackbars and field hints, and it has
  /// no `package` argument to do the prefixing for it.
  static const String qualifiedFamily = 'packages/$package/$family';
  static const String qualifiedDevanagari = 'packages/$package/$devanagari';

  static const List<String> _fallback = <String>[devanagari];

  static const List<FontFeature> _features = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  TextStyle _style({
    required double size,
    required double lineHeight,
    required FontWeight weight,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: _fallback,
        package: package,
        fontSize: size,
        height: lineHeight / size,
        fontWeight: weight,
        letterSpacing: letterSpacing,
        fontFeatures: _features,
      );

  /// Hero numbers — arrival time, total, capacity percentage.
  TextStyle get display =>
      _style(size: 34, lineHeight: 40, weight: FontWeight.w700);

  /// Screen titles.
  TextStyle get titleL =>
      _style(size: 24, lineHeight: 30, weight: FontWeight.w600);

  /// Card titles.
  TextStyle get titleM =>
      _style(size: 20, lineHeight: 26, weight: FontWeight.w600);

  /// Row titles.
  TextStyle get titleS =>
      _style(size: 17, lineHeight: 22, weight: FontWeight.w600);

  TextStyle get body =>
      _style(size: 15, lineHeight: 22, weight: FontWeight.w400);

  TextStyle get bodyStrong =>
      _style(size: 15, lineHeight: 22, weight: FontWeight.w600);

  TextStyle get caption =>
      _style(size: 13, lineHeight: 18, weight: FontWeight.w400);

  /// Uppercase section labels. Always render with an uppercased string —
  /// `SectionLabel` does this for you.
  TextStyle get label => _style(
        size: 11,
        lineHeight: 14,
        weight: FontWeight.w600,
        letterSpacing: 11 * 0.08,
      );

  /// Parcel IDs, OTP digits, registration plates.
  TextStyle get code => _style(
        size: 15,
        lineHeight: 22,
        weight: FontWeight.w600,
        letterSpacing: 0.5,
      );
}
