import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../support/harness.dart';

void main() {
  test('the demand ramp is five warm steps, not a rainbow', () {
    expect(V360Colors.heatRamp, hasLength(5));
    for (final c in V360Colors.heatRamp) {
      final hue = HSVColor.fromColor(c).hue;
      expect(hue, inInclusiveRange(0, 50), reason: 'marigold to red only');
    }
    // Darker as demand rises, so the steps read in greyscale too.
    for (var i = 1; i < V360Colors.heatRamp.length; i++) {
      expect(
        V360Colors.heatRamp[i].computeLuminance(),
        lessThan(V360Colors.heatRamp[i - 1].computeLuminance()),
      );
    }
  });

  testWidgets('the legend prints stepped swatches, no gradient',
      (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 360, child: HeatmapLegend()),
    ));
    for (final c in V360Colors.heatRamp) {
      expect(
        find.byWidgetPredicate((w) => w is Container && w.color == c),
        findsOneWidget,
      );
    }
    expect(
      find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration! as BoxDecoration).gradient != null),
      findsNothing,
    );
  });

  testWidgets('the map sits on the light board, not a dark panel',
      (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(
        width: 360,
        child: DemandHeatmap(cells: <HeatCell>[
          HeatCell(lat: 18.5, lon: 73.8, intensity: 0.9, demandQty: 40,
              vendorCount: 4, topSku: 'Milk'),
          HeatCell(lat: 18.52, lon: 73.82, intensity: 0.3, demandQty: 12,
              vendorCount: 3),
        ]),
      ),
    ));
    await tester.pumpAndSettle();
    final box = tester.widget<Container>(find
        .descendant(
          of: find.byType(DemandHeatmap),
          matching: find.byType(Container),
        )
        .first);
    expect((box.decoration! as BoxDecoration).color,
        V360Colors.light().surfaceMuted);
  });
}
