import 'package:flutter/widgets.dart';

/// The Vendor360 type scale, set in Anek.
///
/// Anek is by Ek Type, a Mumbai type foundry, and draws Latin and Devanagari
/// as one design — so a Hindi screen, the product's default, speaks in the
/// same letterforms as an English one. Both files are bundled rather than
/// fetched, so type renders correctly with no network.
///
/// The scale borrows its voice from the packets on a kirana shelf: the big
/// figures are set narrow and heavy, the way a pack prints its product name
/// and MRP, while running text stays at normal width where reading matters
/// more than presence. Width is Anek's `wdth` axis, 75 (narrow) to 125.
///
/// Tabular figures are on every style — functional, not stylistic: a figure
/// that updates live must not change width, and price columns must align.
///
/// Weight is written to the `wght` axis explicitly, alongside `fontWeight`.
/// A variable font given only a `fontWeight` may be emboldened synthetically
/// instead of drawn at that weight, which smears the counters of narrow
/// figures first. Use [V360TextStyleX.weight] to change weight so the axis
/// moves with it.
@immutable
class V360Typography {
  const V360Typography();

  static const String family = 'AnekLatin';

  /// Devanagari, for Hindi and Marathi. Also carries full Latin.
  ///
  /// Must be a bundled package asset, not a platform font name. Flutter
  /// prefixes *every* `fontFamilyFallback` entry with `packages/$package/`
  /// when [package] is set, so a system family named here would resolve to
  /// nothing at all — and would do it silently, with no error and no glyphs.
  static const String devanagari = 'AnekDevanagari';

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

  /// Normal width. Running text, labels, buttons.
  static const double regularWidth = 100;

  /// The pack-print width, for figures and titles that must carry weight in
  /// a small space.
  static const double narrowWidth = 78;

  static TextStyle _style({
    required double size,
    required double lineHeight,
    required FontWeight weight,
    double? axisWeight,
    double width = regularWidth,
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
        // Devanagari's matras rise above the Latin cap height; even leading
        // centres both scripts in the same line box, so a Hindi label sits
        // on the same line as an English one beside it.
        leadingDistribution: TextLeadingDistribution.even,
        fontVariations: <FontVariation>[
          FontVariation('wght', axisWeight ?? weight.value.toDouble()),
          FontVariation('wdth', width),
        ],
      );

  /// The figure that owns a screen's teal band — today's sales, a stock
  /// count, a score. Narrow and heavy, like a pack's product name.
  TextStyle get display => _style(
        size: 56,
        lineHeight: 56,
        weight: FontWeight.w700,
        width: narrowWidth,
        letterSpacing: -0.5,
      );

  /// A figure inside a panel — a count, an amount, a date.
  TextStyle get figure => _style(
        size: 30,
        lineHeight: 32,
        weight: FontWeight.w700,
        width: 82,
      );

  /// Screen titles.
  TextStyle get titleL => _style(
        size: 26,
        lineHeight: 30,
        weight: FontWeight.w700,
        width: 88,
      );

  /// Section headings.
  TextStyle get titleM => _style(
        size: 20,
        lineHeight: 24,
        weight: FontWeight.w600,
        width: 94,
      );

  /// Row titles — an item, a shop, an order.
  TextStyle get titleS =>
      _style(size: 17, lineHeight: 22, weight: FontWeight.w600);

  /// Anek's regular is drawn light; 430 on the axis holds up in daylight
  /// without reading as medium.
  TextStyle get body => _style(
        size: 15,
        lineHeight: 22,
        weight: FontWeight.w400,
        axisWeight: 430,
      );

  TextStyle get bodyStrong =>
      _style(size: 15, lineHeight: 22, weight: FontWeight.w600);

  TextStyle get caption => _style(
        size: 13,
        lineHeight: 18,
        weight: FontWeight.w400,
        axisWeight: 450,
      );

  /// The small print — the "Net qty" and "Best before" of a panel, set next
  /// to its value rather than above a heading. Sentence case; never used as
  /// an eyebrow.
  TextStyle get label => _style(
        size: 12,
        lineHeight: 16,
        weight: FontWeight.w500,
        letterSpacing: 0.1,
      );

  /// OTP digits, order numbers, batch codes.
  TextStyle get code => _style(
        size: 16,
        lineHeight: 22,
        weight: FontWeight.w600,
        width: 110,
        letterSpacing: 1,
      );
}

/// A strut taken from the Latin face, for a label that may be set in either
/// script.
///
/// Anek Devanagari is the fallback, and its vertical metrics are taller than
/// Anek Latin's to hold the matras. A line set entirely in Devanagari takes
/// its line box from the fallback's metrics, so a Hindi label and an English
/// one beside it sit on different baselines — the Hindi rides about 3dp high.
/// Forcing both onto the Latin face's strut puts them on one baseline.
StrutStyle v360Strut(TextStyle style) => StrutStyle(
      fontFamily: V360Typography.family,
      package: V360Typography.package,
      fontSize: style.fontSize,
      height: style.height,
      leadingDistribution: TextLeadingDistribution.even,
      forceStrutHeight: true,
    );

/// Axis-aware adjustments to a [V360Typography] style.
extension V360TextStyleX on TextStyle {
  /// Changes weight on both `fontWeight` and the `wght` axis, keeping width.
  TextStyle weight(FontWeight weight) => copyWith(
        fontWeight: weight,
        fontVariations: <FontVariation>[
          FontVariation('wght', weight.value.toDouble()),
          FontVariation('wdth', _axis('wdth') ?? V360Typography.regularWidth),
        ],
      );

  /// Sets the `wdth` axis, keeping weight. Defaults to the pack-print width.
  TextStyle narrow([double width = V360Typography.narrowWidth]) => copyWith(
        fontVariations: <FontVariation>[
          FontVariation(
            'wght',
            _axis('wght') ?? (fontWeight ?? FontWeight.w400).value.toDouble(),
          ),
          FontVariation('wdth', width),
        ],
      );

  double? _axis(String tag) {
    for (final v in fontVariations ?? const <FontVariation>[]) {
      if (v.axis == tag) return v.value;
    }
    return null;
  }
}
