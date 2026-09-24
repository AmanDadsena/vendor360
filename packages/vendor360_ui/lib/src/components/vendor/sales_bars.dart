import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// One day of takings.
@immutable
class SalesPointData {
  const SalesPointData({
    required this.label,
    required this.value,
    required this.display,
    this.today = false,
  });

  /// The short axis label — "Mon", "12".
  final String label;

  final double value;

  /// The value as the product writes money, for the tooltip and the peak
  /// label. Passed in rather than formatted here, so the design system never
  /// has to know what a rupee is.
  final String display;

  final bool today;
}

/// Daily takings as printed bars.
///
/// One series, so there is no legend and no categorical palette: identity
/// comes from position on the time axis, and the single teal is the shop's
/// own ink. The peak carries a direct label — the one number worth reading
/// off the chart — rather than every bar wearing a value.
///
/// Flat fills with a 4px rounded top and a 2px gap, a baseline rule, no
/// gridlines: a printed panel, not a dashboard widget. Closed days are zero
/// and stay in the series, because dropping them would draw a trend that
/// never happened.
class SalesBars extends StatelessWidget {
  const SalesBars({
    super.key,
    required this.points,
    this.height = 160,
    this.caption,
  });

  final List<SalesPointData> points;
  final double height;

  /// What the bars are, in words — the title does the work a legend would.
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No sales recorded yet',
            style: v360.text.caption.copyWith(color: colors.inkMuted),
          ),
        ),
      );
    }

    final maxValue = points.map((p) => p.value).reduce((a, b) => a > b ? a : b);
    final peak = points.indexWhere((p) => p.value == maxValue);
    // Headroom for the peak's own label, so it never collides with the frame.
    final ceiling = maxValue <= 0 ? 1.0 : maxValue * 1.28;

    return Semantics(
      // The table view, for anyone who cannot see the bars.
      label: <String>[
        ?caption,
        for (final p in points) '${p.label} ${p.display}',
      ].join(', '),
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (caption != null) ...<Widget>[
            Text(
              caption!,
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
            SizedBox(height: v360.spacing.sm),
          ],
          SizedBox(
            height: height,
            child: BarChart(
              BarChartData(
                maxY: ceiling,
                minY: 0,
                alignment: BarChartAlignment.spaceBetween,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (_) => colors.ink,
                    tooltipBorderRadius: BorderRadius.circular(V360Radius.sm),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final point = points[group.x.toInt()];
                      return BarTooltipItem(
                        '${point.label}\n${point.display}',
                        v360.text.caption.copyWith(color: colors.canvas),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(),
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      getTitlesWidget: (value, _) {
                        final index = value.toInt();
                        if (index < 0 || index >= points.length) {
                          return const SizedBox.shrink();
                        }
                        // Every other label on a fortnight, so a phone-width
                        // axis never stacks its days on top of each other.
                        final crowded = points.length > 8;
                        final point = points[index];
                        if (crowded && !point.today && index.isOdd) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            point.label,
                            style: v360.text.label.copyWith(
                              color: point.today
                                  ? colors.ink
                                  : colors.inkMuted,
                            ).weight(
                              point.today ? FontWeight.w700 : FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(
                  show: true,
                  // A baseline rule and nothing else: the bars sit on the
                  // page the way a printed panel's do.
                  border: Border(
                    bottom: BorderSide(color: colors.hairline),
                  ),
                ),
                barGroups: <BarChartGroupData>[
                  for (var i = 0; i < points.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: <BarChartRodData>[
                        BarChartRodData(
                          toY: points[i].value,
                          width: points.length > 10 ? 12 : 18,
                          color: colors.accent,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                      showingTooltipIndicators: const <int>[],
                    ),
                ],
                // The peak names itself; no other bar carries a number.
                extraLinesData: ExtraLinesData(
                  horizontalLines: <HorizontalLine>[
                    if (maxValue > 0)
                      HorizontalLine(
                        y: maxValue,
                        color: colors.hairline,
                        strokeWidth: 1,
                        dashArray: <int>[3, 3],
                        label: HorizontalLineLabel(
                          show: true,
                          alignment: Alignment.topLeft,
                          style: v360.text.label
                              .copyWith(color: colors.inkMuted),
                          labelResolver: (_) =>
                              peak >= 0 ? points[peak].display : '',
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
