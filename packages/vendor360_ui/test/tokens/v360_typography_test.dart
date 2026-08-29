import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/painting.dart';
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
}
