import 'dart:math' as math;

import 'package:flutter/painting.dart';

import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 2.x contrast ratio.
double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

void main() {
  final themes = <String, V360Colors>{
    'light': V360Colors.light(),
    'dark': V360Colors.dark(),
    'light distributor': V360Colors.light().distributorVariant(),
    'dark distributor': V360Colors.dark().distributorVariant(),
  };

  group('V360Colors', () {
    // Body text must clear AA (4.5:1) on every surface it is set on. These are
    // asserted rather than eyeballed: the counter is in daylight.
    themes.forEach((name, c) {
      test('$name: text tokens clear AA on canvas, surface and board', () {
        for (final (label, fg) in <(String, Color)>[
          ('ink', c.ink),
          ('inkMuted', c.inkMuted),
          ('inkSubtle', c.inkSubtle),
          ('accentText', c.accentText),
          ('voiceText', c.voiceText),
          ('warningText', c.warningText),
          ('dangerText', c.dangerText),
        ]) {
          for (final (bgLabel, bg) in <(String, Color)>[
            ('canvas', c.canvas),
            ('surface', c.surface),
          ]) {
            expect(contrast(fg, bg), greaterThanOrEqualTo(4.5),
                reason: '$label on $bgLabel');
          }
        }
        expect(contrast(c.ink, c.surfaceMuted), greaterThanOrEqualTo(4.5));
        expect(contrast(c.inkMuted, c.surfaceMuted), greaterThanOrEqualTo(4.5));
      });

      test('$name: band text reads in sunlight', () {
        expect(contrast(c.onBand, c.band), greaterThanOrEqualTo(4.5));
        // Secondary text on the band is tinted from the teal, not greyed, and
        // still clears AA.
        expect(contrast(c.onBandMuted, c.band), greaterThanOrEqualTo(4.5));
      });

      test('$name: status text reads on its own tinted surface', () {
        expect(contrast(c.warningText, c.warningSurface),
            greaterThanOrEqualTo(4.5));
        expect(contrast(c.dangerText, c.dangerSurface),
            greaterThanOrEqualTo(4.5));
        expect(contrast(c.accentText, c.accentSurface),
            greaterThanOrEqualTo(4.5));
        expect(contrast(c.voiceText, c.voiceSurface),
            greaterThanOrEqualTo(4.5));
      });

      test('$name: fills carry their labels', () {
        expect(contrast(c.onActionFill, c.actionFill),
            greaterThanOrEqualTo(4.5));
        expect(contrast(c.onVoice, c.voice), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onFlash, c.flash), greaterThanOrEqualTo(4.5));
        expect(contrast(c.onFill, c.danger), greaterThanOrEqualTo(3.0),
            reason: 'badge counts are bold and large enough for 3:1');
      });

      test('$name: markers are visible against the page', () {
        // Non-text UI needs 3:1 (WCAG 1.4.11): the status squares, the live
        // dot, the mic disc's edge against the bar.
        for (final (label, fg) in <(String, Color)>[
          ('accent', c.accent),
          ('danger', c.danger),
          ('keyline', c.keyline),
        ]) {
          expect(contrast(fg, c.surface), greaterThanOrEqualTo(3.0),
              reason: label);
        }
      });
    });

    test('the page is white board, not cream', () {
      // A warm off-white canvas is the look every generated app lands on.
      final c = V360Colors.light();
      expect(c.canvas, const Color(0xFFFFFFFF));
      final hsv = HSVColor.fromColor(c.surfaceMuted);
      expect(hsv.hue, inInclusiveRange(120, 200),
          reason: 'the second neutral is a cool board grey');
    });

    test('teal is the brand in both themes', () {
      for (final c in <V360Colors>[V360Colors.light(), V360Colors.dark()]) {
        final hue = HSVColor.fromColor(c.accent).hue;
        expect(hue, inInclusiveRange(160, 180));
        expect(c.band, isNot(c.danger));
      }
    });

    test('primary action is teal, not near-black', () {
      final c = V360Colors.light();
      expect(c.actionFill, c.accent);
    });

    test('the mic keeps its own token', () {
      // So "the orange" for a stock alert cannot dilute the mic.
      final c = V360Colors.light();
      expect(c.voice, isNot(c.warning));
    });

    test('the distributor prints on a deeper band, nothing else changes', () {
      final shop = V360Colors.light();
      final dist = shop.distributorVariant();
      expect(dist.band, isNot(shop.band));
      expect(dist.band.computeLuminance(),
          lessThan(shop.band.computeLuminance()));
      expect(dist.accent, shop.accent);
      expect(dist.ink, shop.ink);
    });

    test('lerp at t=0 and t=1 returns the endpoints', () {
      final l = V360Colors.light();
      final d = V360Colors.dark();
      expect(l.lerp(d, 0).canvas, l.canvas);
      expect(l.lerp(d, 1).canvas, d.canvas);
      expect(l.lerp(d, 1).band, d.band);
    });
  });
}
