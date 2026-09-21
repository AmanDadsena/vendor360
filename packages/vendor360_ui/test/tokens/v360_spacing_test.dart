import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const s = V360Spacing();

  test('spacing follows the 4pt scale', () {
    expect(s.all, <double>[4, 8, 12, 16, 20, 24, 32, 40, 48]);
  });

  test('screen gutter matches Material compact margins', () {
    expect(s.gutter, 16);
  });

  test('every spacing value is divisible by 4', () {
    for (final v in s.all) {
      expect(v % 4, 0, reason: '$v breaks the 4pt scale');
    }
  });

  test('radii are tight, like a carton dieline', () {
    expect(V360Radius.sm, 4);
    expect(V360Radius.md, 6);
    expect(V360Radius.lg, 8);
    expect(V360Radius.xl, 12);
    expect(V360Radius.pill, 999);
  });

  // Print has no shadows. Panels are separated by rules; only floating
  // surfaces cast one, and never in dark mode where a shadow reads as mud.
  test('panels are flat, only floating surfaces cast a shadow', () {
    expect(V360Elevation.card(Brightness.light), isEmpty);
    expect(V360Elevation.card(Brightness.dark), isEmpty);
    expect(V360Elevation.floating(Brightness.light), isNotEmpty);
    expect(V360Elevation.floating(Brightness.dark), isEmpty);
  });

  test('a floating shadow has an offset, not a halo', () {
    for (final s in V360Elevation.floating(Brightness.light)) {
      expect(s.offset.dy, greaterThan(0));
      expect(s.spreadRadius, lessThanOrEqualTo(0));
    }
  });
}
