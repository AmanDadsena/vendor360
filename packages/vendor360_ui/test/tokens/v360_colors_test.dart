import 'dart:ui';

import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('V360Colors', () {
    test('light uses the exact teal palette', () {
      final c = V360Colors.light();
      expect(c.canvas, const Color(0xFFFAF9F6));
      expect(c.surface, const Color(0xFFFFFFFF));
      expect(c.ink, const Color(0xFF1A2E2A));
      expect(c.inkMuted, const Color(0xFF5B6B67));
      expect(c.hairline, const Color(0xFFD8E4E1));
      expect(c.accent, const Color(0xFF0F7A6B));
      expect(c.accentText, const Color(0xFF0A5A4F));
      expect(c.accentSurface, const Color(0xFFE4F2EF));
    });

    test('dark uses the exact teal palette', () {
      final c = V360Colors.dark();
      expect(c.canvas, const Color(0xFF0B1210));
      expect(c.surface, const Color(0xFF151E1B));
      expect(c.ink, const Color(0xFFEDF3F1));
      expect(c.hairline, const Color(0xFF223029));
      expect(c.accent, const Color(0xFF2FB39D));
      expect(c.accentSurface, const Color(0xFF0C2E28));
    });

    // The single most load-bearing rule in the design system.
    test('actionFill inverts between themes', () {
      expect(V360Colors.light().actionFill, const Color(0xFF1A2E2A));
      expect(V360Colors.dark().actionFill, const Color(0xFF2FB39D));
    });

    test('onActionFill inverts with actionFill', () {
      expect(V360Colors.light().onActionFill, const Color(0xFFFFFFFF));
      expect(V360Colors.dark().onActionFill, const Color(0xFF04211C));
    });

    // The accent on white is far below any readable threshold, so a deeper
    // blue is used for text. On dark the accent reads fine and they converge.
    test('accentText differs from accent in light and matches it in dark', () {
      expect(V360Colors.light().accentText,
          isNot(V360Colors.light().accent));
      expect(V360Colors.dark().accentText, V360Colors.dark().accent);
    });

    test('danger text is darker than the danger fill in light mode', () {
      final c = V360Colors.light();
      expect(c.dangerText, isNot(c.danger));
      expect(c.dangerText.computeLuminance(),
          lessThan(c.danger.computeLuminance()));
    });

    test('lerp at t=0 and t=1 returns the endpoints', () {
      final l = V360Colors.light();
      final d = V360Colors.dark();
      expect(l.lerp(d, 0).canvas, l.canvas);
      expect(l.lerp(d, 1).canvas, d.canvas);
      expect(l.lerp(d, 1).actionFill, d.actionFill);
    });
  });
}
