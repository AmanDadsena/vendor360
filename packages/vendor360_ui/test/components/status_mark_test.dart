import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../support/harness.dart';

void main() {
  final light = V360Colors.light();

  group('StatusMark', () {
    testWidgets('colour lives in the square, the word stays ink',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        StatusMark(label: 'Out of stock', color: light.danger),
      ));
      final text = tester.widget<Text>(find.text('Out of stock'));
      expect(text.style!.color, light.ink);

      final square = tester.widget<Container>(find
          .descendant(
            of: find.byType(StatusMark),
            matching: find.byType(Container),
          )
          .first);
      expect((square.decoration! as BoxDecoration).color, light.danger);
    });

    testWidgets('an icon replaces the square when given', (tester) async {
      await tester.pumpWidget(carryHarness(
        StatusMark(
          label: 'Due today',
          color: light.warning,
          icon: Icons.schedule_rounded,
        ),
      ));
      final icon = tester.widget<Icon>(find.byIcon(Icons.schedule_rounded));
      expect(icon.color, light.warning);
    });
  });

  group('SignalBanner', () {
    testWidgets('is a flat flash band with ink on it', (tester) async {
      await tester.pumpWidget(carryHarness(
        const SignalBanner(
          title: 'Anant Chaturdashi in 3 days',
          detail: 'Expect more demand for sweets',
        ),
      ));
      final material = tester.widget<Material>(find
          .descendant(
            of: find.byType(SignalBanner),
            matching: find.byType(Material),
          )
          .first);
      expect(material.color, light.flash);
      final title =
          tester.widget<Text>(find.text('Anant Chaturdashi in 3 days'));
      expect(title.style!.color, light.onFlash);
    });
  });

  group('StatTile', () {
    testWidgets('the figure stays ink even when the tone is urgent',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        SizedBox(
          width: 200,
          child: StatTile(label: 'Low stock', value: '7', tone: light.warning),
        ),
      ));
      final value = tester.widget<Text>(find.text('7'));
      expect(value.style!.color, light.ink);
      expect(find.byType(StatusMark), findsOneWidget);
    });
  });
}
