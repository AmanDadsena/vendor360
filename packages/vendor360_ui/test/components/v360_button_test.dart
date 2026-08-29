import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

BoxDecoration _decorationOf(WidgetTester tester) {
  final container = tester.widget<AnimatedContainer>(
    find
        .descendant(
          of: find.byType(V360Button),
          matching: find.byType(AnimatedContainer),
        )
        .first,
  );
  return container.decoration! as BoxDecoration;
}

void main() {
  group('V360Button', () {
    testWidgets('primary is black in light mode', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Find space', onPressed: () {}),
      ));
      expect(_decorationOf(tester).color, const Color(0xFF1A2E2A));
    });

    // The inversion rule. If this ever flips, every screen looks wrong.
    testWidgets('primary is teal in dark mode', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Find space', onPressed: () {}),
        brightness: Brightness.dark,
      ));
      expect(_decorationOf(tester).color, const Color(0xFF2FB39D));
    });

    testWidgets('label colour inverts with the fill', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Go', onPressed: () {}),
      ));
      expect(tester.widget<Text>(find.text('Go')).style!.color,
          const Color(0xFFFFFFFF));

      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Go', onPressed: () {}),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.text('Go')).style!.color,
          const Color(0xFF04211C));
    });

    testWidgets('is a true pill at every size', (tester) async {
      for (final size in V360ButtonSize.values) {
        await tester.pumpWidget(carryHarness(
          V360Button.primary(label: 'X', onPressed: () {}, size: size),
        ));
        final radius =
            (_decorationOf(tester).borderRadius! as BorderRadius).topLeft.x;
        final height = tester.getSize(find.byType(V360Button)).height;
        expect(radius, greaterThanOrEqualTo(height / 2),
            reason: '$size is not a full pill');
      }
    });

    testWidgets('sizes are 40 / 48 / 56', (tester) async {
      const expected = <V360ButtonSize, double>{
        V360ButtonSize.sm: 40,
        V360ButtonSize.md: 48,
        V360ButtonSize.lg: 56,
      };
      for (final entry in expected.entries) {
        await tester.pumpWidget(carryHarness(
          V360Button.primary(label: 'X', onPressed: () {}, size: entry.key),
        ));
        // AnimatedContainer tweens height between pumps, so settle before
        // measuring or we read a frame mid-transition.
        await tester.pumpAndSettle();
        expect(tester.getSize(find.byType(V360Button)).height, entry.value);
      }
    });

    testWidgets('secondary uses surface with a hairline border',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.secondary(label: 'Directions', onPressed: () {}),
      ));
      final decoration = _decorationOf(tester);
      expect(decoration.color, const Color(0xFFFFFFFF));
      expect(decoration.border, isNotNull);
    });

    testWidgets('ghost uses accentText, the readable blue', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.ghost(label: 'Custom dimensions', onPressed: () {}),
      ));
      expect(
        tester.widget<Text>(find.text('Custom dimensions')).style!.color,
        const Color(0xFF0A5A4F),
      );
    });

    testWidgets('fires onPressed when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Tap', onPressed: () => taps++),
      ));
      await tester.tap(find.byType(V360Button));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });

    testWidgets('does not fire when disabled', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360Button.primary(label: 'Off', onPressed: null),
      ));
      await tester.tap(find.byType(V360Button));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a spinner and blocks taps while loading',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(carryHarness(
        V360Button.primary(
          label: 'Saving',
          onPressed: () => taps++,
          loading: true,
        ),
      ));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(V360Button));
      await tester.pump();
      expect(taps, 0);
    });

    testWidgets('renders a trailing icon when given one', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.primary(
          label: 'Find space',
          onPressed: () {},
          trailingIcon: Icons.arrow_forward,
        ),
      ));
      expect(find.byIcon(Icons.arrow_forward), findsOneWidget);
    });

    testWidgets('is exposed to screen readers as an enabled button',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Button.primary(label: 'Accept parcel', onPressed: () {}),
      ));
      final node = tester.getSemantics(find.byType(V360Button).first);
      // Exactly once — not "Accept parcel\nAccept parcel", which is what
      // happens if the wrapper's label merges with the inner Text's.
      expect(node.label, 'Accept parcel');
      expect(
        node,
        isSemantics(isButton: true, isEnabled: true, hasEnabledState: true),
      );
    });
  });
}
