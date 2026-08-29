import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

/// Scopes assertions to the switcher's own subtree. `find.byType` alone
/// also matches Flutter's internal route and Material transitions, which
/// made "no SlideTransition" impossible to assert honestly.
const Key kSwitcher = Key('switcher-under-test');

Finder _inSwitcher(Type type) => find.descendant(
      of: find.byKey(kSwitcher),
      matching: find.byType(type),
    );

Widget _switcher(String key, {bool reduced = false, V360Axis? axis}) {
  return carryHarness(
    KeyedSubtree(
      key: kSwitcher,
      child: Builder(
        builder: (context) => V360Transitions.switcher(
          context: context,
          axis: axis ?? V360Axis.horizontal,
          child: KeyedSubtree(
            key: ValueKey<String>(key),
            child: Text(key),
          ),
        ),
      ),
    ),
    disableAnimations: reduced,
  );
}

void main() {
  group('V360Transitions.switcher', () {
    testWidgets('renders its child', (tester) async {
      await tester.pumpWidget(_switcher('one'));
      await tester.pumpAndSettle();
      expect(find.text('one'), findsOneWidget);
    });

    testWidgets('animates to a new child and settles', (tester) async {
      await tester.pumpWidget(_switcher('one'));
      await tester.pumpAndSettle();

      await tester.pumpWidget(_switcher('two'));
      // Mid-transition both are present, which is what makes the movement
      // readable rather than a hard cut.
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.text('two'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('one'), findsNothing);
      expect(find.text('two'), findsOneWidget);
    });

    // Movement is orientation, not decoration — under reduce-motion the
    // fade remains but the translation and scale must not.
    testWidgets('degrades to a plain fade under reduce-motion',
        (tester) async {
      await tester.pumpWidget(_switcher('one', reduced: true));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_switcher('two', reduced: true));
      await tester.pump();

      expect(_inSwitcher(SlideTransition), findsNothing);
      expect(_inSwitcher(ScaleTransition), findsNothing);
      expect(_inSwitcher(FadeTransition), findsWidgets);
    });

    testWidgets('horizontal axis slides sideways', (tester) async {
      await tester.pumpWidget(_switcher('one', axis: V360Axis.horizontal));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_switcher('two', axis: V360Axis.horizontal));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_inSwitcher(SlideTransition), findsWidgets);
    });

    // Drilling in should feel like moving toward content, not past it.
    testWidgets('depth axis scales rather than slides', (tester) async {
      await tester.pumpWidget(_switcher('one', axis: V360Axis.depth));
      await tester.pumpAndSettle();
      await tester.pumpWidget(_switcher('two', axis: V360Axis.depth));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_inSwitcher(ScaleTransition), findsWidgets);
      expect(_inSwitcher(SlideTransition), findsNothing);
    });
  });

  group('V360Refresh', () {
    testWidgets('wraps a scrollable and exposes the indicator',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        SizedBox(
          height: 300,
          child: V360Refresh(
            onRefresh: () async {},
            child: ListView(
              children: const <Widget>[SizedBox(height: 600, child: Text('x'))],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(RefreshIndicator), findsOneWidget);
    });

    // Material's stock indicator ignores the theme; a primary-coloured
    // spinner on a themed surface is how a consistent app gives itself away.
    testWidgets('uses the accent, not a Material default', (tester) async {
      await tester.pumpWidget(carryHarness(
        SizedBox(
          height: 300,
          child: V360Refresh(
            onRefresh: () async {},
            child: ListView(
              children: const <Widget>[SizedBox(height: 600, child: Text('x'))],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      final indicator =
          tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      expect(indicator.color, V360Colors.light().accent);
    });
  });
}
