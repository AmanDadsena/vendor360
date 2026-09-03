import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';

/// Demand forecasts, each annotated with what is driving it.
///
/// The headline sentence comes first and the chart second, deliberately: a
/// vendor deciding what to buy needs the recommendation, not the model output.
/// The chart is there to make the claim checkable, which is what stops the
/// recommendation being a black box (UI/UX 5.5).
class ForecastScreen extends ConsumerWidget {
  const ForecastScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final forecasts = ref.watch(forecastsProvider);

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: v360.colors.accent,
          onRefresh: () async {
            HapticFeedback.lightImpact();
            ref.invalidate(forecastsProvider);
          },
          child: forecasts.when(
            loading: () => ListView.builder(
              padding: EdgeInsets.all(v360.spacing.gutter),
              itemCount: 3,
              itemBuilder: (_, _) => Padding(
                padding: EdgeInsets.only(bottom: v360.spacing.lg),
                child: const V360Skeleton(height: 250),
              ),
            ),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load forecasts',
              body: '$error',
              action: V360Button.primary(
                label: s.retry,
                onPressed: () => ref.invalidate(forecastsProvider),
              ),
            ),
            data: (list) => list.isEmpty
                ? EmptyState(
                    icon: Icons.trending_up_rounded,
                    title: 'No forecasts yet',
                    body: 'Log a few days of sales and predictions appear here.',
                  )
                : ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      v360.spacing.gutter,
                      v360.spacing.lg,
                      v360.spacing.gutter,
                      v360.spacing.x5,
                    ),
                    itemCount: list.length + 1,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Padding(
                          padding: EdgeInsets.only(bottom: v360.spacing.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                s.comingDays,
                                style: v360.text.titleL
                                    .copyWith(color: v360.colors.ink),
                              ),
                              SizedBox(height: v360.spacing.xs),
                              Text(
                                'Ordered by how strong the signal is, '
                                'not by how much you sell.',
                                style: v360.text.caption
                                    .copyWith(color: v360.colors.inkMuted),
                              ),
                            ],
                          ),
                        );
                      }
                      return V360Reveal(
                        delayIndex: index - 1,
                        child: _ForecastCard(forecast: list[index - 1]),
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast});

  final Forecast forecast;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final peak = forecast.peak;
    final dayFormat = DateFormat('E');

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.lg),
      child: V360Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    forecast.skuName,
                    style: v360.text.titleM.copyWith(color: colors.ink),
                  ),
                ),
                if (forecast.usedFallback)
                  const StatusPill(
                    label: 'Estimate',
                    tone: PillTone.neutral,
                    icon: Icons.help_outline_rounded,
                    dense: true,
                  )
                else if (peak != null && peak.hasSignal)
                  DriverBadge(
                    driver: peak.driver!,
                    effect: peak.driverEffect,
                    compact: true,
                  ),
              ],
            ),
            SizedBox(height: v360.spacing.md),

            // The recommendation, in the vendor's terms.
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(v360.spacing.lg),
              decoration: BoxDecoration(
                color: colors.accentSurface,
                borderRadius: BorderRadius.circular(V360Radius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.lightbulb_outline_rounded, size: 18, color: colors.accentText),
                  SizedBox(width: v360.spacing.sm),
                  Expanded(
                    child: Text(
                      forecast.headline,
                      style: v360.text.bodyStrong.copyWith(color: colors.accentText),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: v360.spacing.xl),

            ForecastSpark(
              points: <SparkPoint>[
                for (final day in forecast.days)
                  SparkPoint(
                    label: dayFormat.format(day.on),
                    value: day.predicted,
                    lower: day.lower,
                    upper: day.upper,
                    hasSignal: day.hasSignal,
                  ),
              ],
            ),
            SizedBox(height: v360.spacing.lg),

            Row(
              children: <Widget>[
                _Metric(
                  label: 'Next 7 days',
                  value: forecast.total.toStringAsFixed(0),
                ),
                SizedBox(width: v360.spacing.xl),
                if (peak != null)
                  _Metric(
                    label: 'Busiest day',
                    value: DateFormat('E d MMM').format(peak.on),
                  ),
              ],
            ),

            if (forecast.usedFallback) ...<Widget>[
              SizedBox(height: v360.spacing.md),
              Text(
                'Not enough history for this item yet — this is its category '
                'average, and will sharpen as you log more sales.',
                style: v360.text.caption.copyWith(color: colors.inkSubtle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SectionLabel(label),
        SizedBox(height: 2),
        Text(value, style: v360.text.titleS.copyWith(color: v360.colors.ink)),
      ],
    );
  }
}
