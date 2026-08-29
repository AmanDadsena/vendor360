import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

BoxDecoration _cardDecoration(WidgetTester tester) {
  return tester
      .widget<Container>(
        find
            .descendant(
              of: find.byType(V360Card),
              matching: find.byType(Container),
            )
            .first,
      )
      .decoration! as BoxDecoration;
}

void main() {
  group('V360Card', () {
    testWidgets('uses the surface token in light and dark', (tester) async {
      await tester.pumpWidget(
        carryHarness(const V360Card(child: Text('x'))),
      );
      await tester.pumpAndSettle();
      expect(_cardDecoration(tester).color, const Color(0xFFFFFFFF));

      // MaterialApp animates theme changes, so settle or we read a lerped
      // colour partway between the two palettes.
      await tester.pumpWidget(carryHarness(
        const V360Card(child: Text('x')),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(_cardDecoration(tester).color, const Color(0xFF151E1B));
    });

    // A shadow on a near-black canvas reads as mud, so dark separates with
    // a hairline border instead.
    testWidgets('has a shadow in light and a border in dark', (tester) async {
      await tester.pumpWidget(
        carryHarness(const V360Card(child: Text('x'))),
      );
      await tester.pumpAndSettle();
      final light = _cardDecoration(tester);
      expect(light.boxShadow, isNotEmpty);
      expect(light.border, isNull);

      await tester.pumpWidget(carryHarness(
        const V360Card(child: Text('x')),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      final dark = _cardDecoration(tester);
      expect(dark.boxShadow, isEmpty);
      expect(dark.border, isNotNull);
    });

    testWidgets('default radius is V360Radius.xl', (tester) async {
      await tester.pumpWidget(
        carryHarness(const V360Card(child: Text('x'))),
      );
      final r = _cardDecoration(tester).borderRadius! as BorderRadius;
      expect(r.topLeft.x, V360Radius.xl);
    });

    testWidgets('fires onTap when given one', (tester) async {
      var taps = 0;
      await tester.pumpWidget(carryHarness(
        V360Card(onTap: () => taps++, child: const Text('tap me')),
      ));
      await tester.tap(find.byType(V360Card));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('V360StackCard', () {
    testWidgets('renders N rows with N-1 dividers', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360StackCard(
          rows: <Widget>[Text('a'), Text('b'), Text('c')],
        ),
      ));

      expect(find.text('a'), findsOneWidget);
      expect(find.text('c'), findsOneWidget);

      final dividers = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(V360StackCard),
            matching: find.byType(Container),
          ))
          .where((c) => c.constraints?.maxHeight == 1 || _isHairline(c))
          .toList();
      expect(dividers.length, 2);
    });

    testWidgets('dividers use the hairline token', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360StackCard(rows: <Widget>[Text('a'), Text('b')]),
      ));
      final divider = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(V360StackCard),
            matching: find.byType(Container),
          ))
          .firstWhere(_isHairline);
      expect(divider.color, const Color(0xFFD8E4E1));
    });
  });

  group('SectionLabel', () {
    testWidgets('uppercases its input', (tester) async {
      await tester.pumpWidget(carryHarness(const SectionLabel('from')));
      expect(find.text('FROM'), findsOneWidget);
      expect(find.text('from'), findsNothing);
    });

    testWidgets('uses the label style and inkSubtle', (tester) async {
      await tester.pumpWidget(carryHarness(const SectionLabel('departs')));
      final style = tester.widget<Text>(find.text('DEPARTS')).style!;
      expect(style.color, const Color(0xFF8A9793));
      expect(style.fontSize, 11);
      expect(style.letterSpacing, closeTo(11 * 0.08, 0.001));
    });
  });

  group('V360IconButton', () {
    testWidgets('is circular', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360IconButton(icon: Icons.swap_vert, onPressed: () {}),
      ));
      final size = tester.getSize(find.byType(V360IconButton));
      expect(size.width, size.height);

      final decoration = tester
          .widget<Container>(find
              .descendant(
                of: find.byType(V360IconButton),
                matching: find.byType(Container),
              )
              .first)
          .decoration! as BoxDecoration;
      expect(decoration.shape, BoxShape.circle);
    });

    testWidgets('outlined by default, filled uses actionFill',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        V360IconButton(icon: Icons.add, onPressed: () {}, filled: true),
      ));
      final decoration = tester
          .widget<Container>(find
              .descendant(
                of: find.byType(V360IconButton),
                matching: find.byType(Container),
              )
              .first)
          .decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF1A2E2A));
    });

    testWidgets('fires onPressed', (tester) async {
      var taps = 0;
      await tester.pumpWidget(carryHarness(
        V360IconButton(icon: Icons.add, onPressed: () => taps++),
      ));
      await tester.tap(find.byType(V360IconButton));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });
}

bool _isHairline(Container c) {
  final h = c.constraints?.maxHeight;
  return h == 1 && c.color != null;
}
