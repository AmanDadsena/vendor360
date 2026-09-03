import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const t = V360Typography();

  test('scale matches the spec', () {
    expect(t.display.fontSize, 34);
    expect(t.display.height, 40 / 34);
    expect(t.display.fontWeight, FontWeight.w700);

    expect(t.titleL.fontSize, 24);
    expect(t.titleM.fontSize, 20);
    expect(t.titleS.fontSize, 17);
    expect(t.body.fontSize, 15);
    expect(t.bodyStrong.fontWeight, FontWeight.w600);
    expect(t.caption.fontSize, 13);
    expect(t.label.fontSize, 11);
  });

  test('section labels are letterspaced for the uppercase treatment', () {
    expect(t.label.letterSpacing, closeTo(11 * 0.08, 0.001));
    expect(t.label.fontWeight, FontWeight.w600);
  });

  // Tabular figures are functional: rolling counters jitter without them and
  // right-aligned price columns fail to align.
  test('every style uses tabular figures', () {
    final all = <TextStyle>[
      t.display, t.titleL, t.titleM, t.titleS,
      t.body, t.bodyStrong, t.caption, t.label, t.code,
    ];
    for (final s in all) {
      expect(
        s.fontFeatures,
        contains(const FontFeature.tabularFigures()),
        reason: 'style at ${s.fontSize}px is missing tabular figures',
      );
    }
  });

  test('every style resolves bundled Inter from this package', () {
    final all = <TextStyle>[t.display, t.titleL, t.body, t.label, t.code];
    for (final s in all) {
      expect(s.fontFamily, contains('Inter'));
    }
  });

  test('every style falls back to Devanagari for Hindi and Marathi', () {
    // Inter carries no Devanagari. Without this fallback the app's default
    // language renders as empty boxes — including the language picker's own
    // endonyms, which is the one place it is most visible.
    final all = <TextStyle>[
      t.display, t.titleL, t.titleM, t.titleS,
      t.body, t.bodyStrong, t.caption, t.label, t.code,
    ];
    for (final s in all) {
      expect(
        s.fontFamilyFallback,
        isNotNull,
        reason: 'a style with no fallback renders Devanagari as tofu',
      );
      expect(s.fontFamilyFallback, contains(contains('NotoSansDevanagari')));
    }
  });

  test('the fallback is package-qualified, not a platform font name', () {
    // Flutter prefixes every fontFamilyFallback entry with `packages/$package/`
    // when `package` is set. A bare platform family name would therefore
    // resolve to nothing, silently, with no error and no glyphs — so this
    // asserts the prefix actually arrived.
    expect(t.body.fontFamilyFallback!.single,
        'packages/vendor360_ui/NotoSansDevanagari');
  });

  test('the theme default carries the same fallback', () {
    // Anything that does not go through a V360Typography style — dialog text,
    // snackbars, TextField hints — inherits ThemeData's font instead.
    //
    // `ThemeData.fontFamily` is constructor-only and folds into the text
    // theme, so the assertion goes through a resolved style rather than
    // reading the field back.
    for (final brightness in Brightness.values) {
      final body = buildV360Theme(brightness).textTheme.bodyMedium!;

      expect(
        body.fontFamily,
        'packages/vendor360_ui/Inter',
        reason: 'ThemeData takes no package argument, so it must be qualified',
      );
      expect(
        body.fontFamilyFallback,
        contains('packages/vendor360_ui/NotoSansDevanagari'),
      );
    }
  });
}
