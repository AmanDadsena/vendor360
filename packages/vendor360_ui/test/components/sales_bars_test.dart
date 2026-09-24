import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../support/harness.dart';

void main() {
  final light = V360Colors.light();

  const points = <SalesPointData>[
    SalesPointData(label: 'Mon', value: 9200, display: '₹9,200'),
    SalesPointData(label: 'Tue', value: 0, display: '₹0'),
    SalesPointData(label: 'Wed', value: 12600, display: '₹12,600'),
    SalesPointData(label: 'Thu', value: 8100, display: '₹8,100', today: true),
  ];

  BarChartData chartData(WidgetTester tester) =>
      tester.widget<BarChart>(find.byType(BarChart)).data;

  testWidgets('bars are the brand ink, one series, no legend', (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 340, child: SalesBars(points: points)),
    ));

    final data = chartData(tester);
    expect(data.barGroups, hasLength(4));
    for (final group in data.barGroups) {
      expect(group.barRods.single.color, light.accent);
    }
  });

  testWidgets('a closed day stays in the series as a zero', (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 340, child: SalesBars(points: points)),
    ));

    // Dropping it would draw a trend that never happened.
    expect(chartData(tester).barGroups[1].barRods.single.toY, 0);
  });

  testWidgets('no gridlines, just a baseline rule', (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 340, child: SalesBars(points: points)),
    ));

    final data = chartData(tester);
    expect(data.gridData.show, isFalse);
    expect(data.borderData.border.bottom.color, light.hairline);
    expect(data.borderData.border.top.style, BorderStyle.none);
  });

  testWidgets('only the peak carries a number', (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 340, child: SalesBars(points: points)),
    ));

    final lines = chartData(tester).extraLinesData.horizontalLines;
    expect(lines, hasLength(1));
    expect(lines.single.y, 12600);
    expect(lines.single.label.labelResolver(lines.single), '₹12,600');
  });

  testWidgets('the whole series is readable without seeing it', (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(
        width: 340,
        child: SalesBars(points: points, caption: 'Last 4 days'),
      ),
    ));

    // The table view, for anyone who cannot see the bars.
    final label = tester
        .getSemantics(find.byType(SalesBars))
        .label;
    expect(label, contains('Last 4 days'));
    expect(label, contains('Wed ₹12,600'));
  });

  testWidgets('an empty series says so rather than drawing nothing',
      (tester) async {
    await tester.pumpWidget(carryHarness(
      const SizedBox(width: 340, child: SalesBars(points: <SalesPointData>[])),
    ));

    expect(find.text('No sales recorded yet'), findsOneWidget);
    expect(find.byType(BarChart), findsNothing);
  });
}
