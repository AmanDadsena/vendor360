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
      expect(_cardDecoration(tester).color, V360Colors.light().surface);

      // MaterialApp animates theme changes, so settle or we read a lerped
      // colour partway between the two palettes.
      await tester.pumpWidget(carryHarness(
        const V360Card(child: Text('x')),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      expect(_cardDecoration(tester).color, V360Colors.dark().surface);
    });

    // A shadow on a near-black canvas reads as mud, so dark separates with
    // a hairline border instead.
    testWidgets('is flat and ruled in both themes', (tester) async {
      await tester.pumpWidget(
        carryHarness(const V360Card(child: Text('x'))),
      );
      await tester.pumpAndSettle();
      final light = _cardDecoration(tester);
      expect(light.boxShadow ?? const <BoxShadow>[], isEmpty);
      expect(light.border, isNotNull);

      await tester.pumpWidget(carryHarness(
        const V360Card(child: Text('x')),
        brightness: Brightness.dark,
      ));
      await tester.pumpAndSettle();
      final dark = _cardDecoration(tester);
      expect(dark.boxShadow ?? const <BoxShadow>[], isEmpty);
      expect(dark.border, isNotNull);
    });

    testWidgets('default radius is V360Radius.lg', (tester) async {
      await tester.pumpWidget(
        carryHarness(const V360Card(child: Text('x'))),
      );
      final r = _cardDecoration(tester).borderRadius! as BorderRadius;
      expect(r.topLeft.x, V360Radius.lg);
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
      expect(divider.color, V360Colors.light().hairline);
    });
  });

  group('SectionLabel', () {
    testWidgets('keeps the case it was given', (tester) async {
      await tester.pumpWidget(carryHarness(const SectionLabel('Running out')));
      expect(find.text('Running out'), findsOneWidget);
      expect(find.text('RUNNING OUT'), findsNothing);
    });

    testWidgets('reads as a heading in ink, not a grey eyebrow',
        (tester) async {
      await tester.pumpWidget(carryHarness(const SectionLabel('Today')));
      final style = tester.widget<Text>(find.text('Today')).style!;
      expect(style.color, V360Colors.light().ink);
      expect(style.fontWeight, FontWeight.w700);
      expect(style.letterSpacing ?? 0, lessThan(0.5));
    });

    testWidgets('is announced as a header', (tester) async {
      await tester.pumpWidget(carryHarness(const SectionLabel('Today')));
      expect(
        tester.getSemantics(find.text('Today')),
        matchesSemantics(isHeader: true, label: 'Today'),
      );
    });

    testWidgets('puts an action at the end of the row', (tester) async {
      await tester.pumpWidget(carryHarness(
        SectionLabel('Orders', action: TextButton(
          onPressed: () {},
          child: const Text('See all'),
        )),
      ));
      expect(find.text('See all'), findsOneWidget);
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
      expect(decoration.color, V360Colors.light().actionFill);
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
