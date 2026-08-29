import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V360Spacing();

  test('spacing follows the 4pt scale', () {
    expect(s.all, <double>[4, 8, 12, 16, 20, 24, 32, 40, 48]);
  });

  test('screen gutter is 20 per the design PDF', () {
    expect(s.gutter, 20);
  });

  test('every spacing value is divisible by 4', () {
    for (final v in s.all) {
      expect(v % 4, 0, reason: '$v breaks the 4pt scale');
    }
  });

  test('radius scale matches the spec', () {
    expect(V360Radius.sm, 12);
    expect(V360Radius.md, 16);
    expect(V360Radius.lg, 20);
    expect(V360Radius.xl, 24);
    expect(V360Radius.pill, 999);
  });

  // Shadows on a near-black canvas read as mud, so dark mode separates
  // surfaces with a hairline border instead.
  test('cards have a shadow in light and none in dark', () {
    expect(V360Elevation.card(Brightness.light), isNotEmpty);
    expect(V360Elevation.card(Brightness.dark), isEmpty);
    expect(V360Elevation.floating(Brightness.light), isNotEmpty);
    expect(V360Elevation.floating(Brightness.dark), isEmpty);
  });
}
