import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double? _axis(TextStyle s, String tag) {
  for (final v in s.fontVariations ?? const <FontVariation>[]) {
    if (v.axis == tag) return v.value;
  }
  return null;
}

void main() {
  const t = V360Typography();

  List<TextStyle> all() => <TextStyle>[
        t.display, t.figure, t.titleL, t.titleM, t.titleS,
        t.body, t.bodyStrong, t.caption, t.label, t.code,
      ];

  test('scale matches the spec', () {
    expect(t.display.fontSize, 56);
    expect(t.display.fontWeight, FontWeight.w700);
    expect(t.figure.fontSize, 30);
    expect(t.titleL.fontSize, 26);
    expect(t.titleM.fontSize, 20);
    expect(t.titleS.fontSize, 17);
    expect(t.body.fontSize, 15);
    expect(t.bodyStrong.fontWeight, FontWeight.w600);
    expect(t.caption.fontSize, 13);
    expect(t.label.fontSize, 12);
  });

  test('figures are set narrow, running text at normal width', () {
    // The pack-print voice lives in the big numbers; body copy is for
    // reading, and a narrow body would cost legibility at the counter.
    expect(_axis(t.display, 'wdth'), lessThan(V360Typography.regularWidth));
    expect(_axis(t.figure, 'wdth'), lessThan(V360Typography.regularWidth));
    expect(_axis(t.body, 'wdth'), V360Typography.regularWidth);
    expect(_axis(t.caption, 'wdth'), V360Typography.regularWidth);
  });

  test('labels are small print, not tracked-out eyebrows', () {
    expect(t.label.letterSpacing, lessThan(0.5));
  });

  // Tabular figures are functional: a live figure must not change width as it
  // updates, and right-aligned price columns must line up.
  test('every style uses tabular figures', () {
    for (final s in all()) {
      expect(
        s.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'style at ${s.fontSize}px is missing tabular figures',
      );
    }
  });

  test('every style drives the weight axis, not synthetic bold', () {
    for (final s in all()) {
      final wght = _axis(s, 'wght');
      expect(wght, isNotNull, reason: '${s.fontSize}px has no wght axis');
      // Within one step of the declared weight: body styles sit a little
      // above 400 on the axis because Anek's regular is drawn light.
      expect((wght! - s.fontWeight!.value).abs(), lessThanOrEqualTo(50));
    }
  });

  test('weight() moves the axis and keeps the width', () {
    final bold = t.display.weight(FontWeight.w800);
    expect(bold.fontWeight, FontWeight.w800);
    expect(_axis(bold, 'wght'), 800);
    expect(_axis(bold, 'wdth'), _axis(t.display, 'wdth'));
  });

  test('narrow() moves the width and keeps the weight', () {
    final n = t.bodyStrong.narrow();
    expect(_axis(n, 'wdth'), V360Typography.narrowWidth);
    expect(_axis(n, 'wght'), 600);
  });

  test('every style resolves bundled Anek from this package', () {
    for (final s in all()) {
      expect(s.fontFamily, contains('AnekLatin'));
    }
  });

  test('every style falls back to Anek Devanagari for Hindi and Marathi', () {
    // Hindi is the default language. Without this fallback it renders as
    // empty boxes — including the language picker's own endonyms.
    for (final s in all()) {
      expect(s.fontFamilyFallback, contains(contains('AnekDevanagari')));
    }
  });

  test('the fallback is package-qualified, not a platform font name', () {
    // Flutter prefixes every fontFamilyFallback entry with `packages/$package/`
    // when `package` is set. A bare platform family name would therefore
    // resolve to nothing, silently — so this asserts the prefix arrived.
    expect(t.body.fontFamilyFallback!.single,
        'packages/vendor360_ui/AnekDevanagari');
  });

  test('the theme default carries the same family and fallback', () {
    // Anything that does not go through a V360Typography style — dialog text,
    // snackbars, TextField hints — inherits ThemeData's font instead.
    for (final brightness in Brightness.values) {
      final body = buildV360Theme(brightness).textTheme.bodyMedium!;

      expect(
        body.fontFamily,
        'packages/vendor360_ui/AnekLatin',
        reason: 'ThemeData takes no package argument, so it must be qualified',
      );
      expect(
        body.fontFamilyFallback,
        contains('packages/vendor360_ui/AnekDevanagari'),
      );
    }
  });
}
