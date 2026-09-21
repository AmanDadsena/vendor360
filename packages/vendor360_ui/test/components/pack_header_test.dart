import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../support/harness.dart';

void main() {
  final light = V360Colors.light();

  group('PackHeader', () {
    testWidgets('is one flat band with no gradient', (tester) async {
      await tester.pumpWidget(carryHarness(
        const PackHeader(title: 'Kumar General Stores', subtitle: 'Kothrud'),
      ));
      final band = tester.widget<Material>(find
          .descendant(
            of: find.byType(PackHeader),
            matching: find.byType(Material),
          )
          .first);
      expect(band.color, light.band);
      expect(
        find.descendant(
          of: find.byType(PackHeader),
          matching: find.byWidgetPredicate((w) =>
              w is DecoratedBox &&
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).gradient != null),
        ),
        findsNothing,
      );
    });

    testWidgets('prints the figure in the display style on band ink',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        const PackHeader(
          title: 'Home',
          figure: Text('₹12,480'),
          figureCaption: 'Sold today',
        ),
      ));
      final context = tester.element(find.text('₹12,480'));
      final style = DefaultTextStyle.of(context).style;
      expect(style.color, light.onBand);
      expect(style.fontSize, const V360Typography().display.fontSize);
      expect(find.text('Sold today'), findsOneWidget);
    });

    testWidgets('the title is announced as a header', (tester) async {
      await tester.pumpWidget(carryHarness(
        const PackHeader(title: 'Stock'),
      ));
      expect(
        find.bySemanticsLabel('Stock'),
        findsOneWidget,
      );
    });
  });

  group('DeclarationStrip', () {
    testWidgets('prints value first, label beneath, one cell per fact',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        const SizedBox(
          width: 360,
          child: DeclarationStrip(facts: <PackFact>[
            PackFact('14', 'entries'),
            PackFact('₹48,200', 'this week'),
          ]),
        ),
      ));
      final value = tester.getTopLeft(find.text('14'));
      final label = tester.getTopLeft(find.text('entries'));
      expect(value.dy, lessThan(label.dy));
      expect(find.bySemanticsLabel('14 entries'), findsOneWidget);
    });
  });
}
