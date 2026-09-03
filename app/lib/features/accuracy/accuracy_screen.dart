import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';

/// Forecast accuracy and the signals driving it.
///
/// MAPE is the Project Report's stated evaluation metric (§5.5), measured
/// out-of-sample: the model is refitted on history up to a cutoff and scored
/// against what actually sold afterwards. Reusing stored predictions would
/// restate the training fit and flatter the model.
///
/// Showing this to the vendor at all is a deliberate choice. A system that
/// tells you what to buy should also tell you how often it has been right.
class AccuracyScreen extends ConsumerWidget {
  const AccuracyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final accuracy = ref.watch(accuracyProvider);
    final signals = ref.watch(signalsProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Model accuracy',
          style: v360.text.titleM.copyWith(color: colors.ink),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter, 0, v360.spacing.gutter, v360.spacing.x5,
          ),
          children: <Widget>[
            accuracy.when(
              loading: () => const V360Skeleton(height: 130, radius: V360Radius.lg),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Accuracy unavailable',
                body: '$error',
              ),
              data: (data) => _AccuracySummary(data: data),
            ),
            SizedBox(height: v360.spacing.xl),

            accuracy.maybeWhen(
              data: (data) {
                final items = (data['items'] as List?) ?? const <dynamic>[];
                if (items.isEmpty) return const SizedBox.shrink();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionLabel('Per item — best predicted first'),
                    SizedBox(height: v360.spacing.md),
                    for (var i = 0; i < items.length && i < 12; i++)
                      V360Reveal(
                        delayIndex: i,
                        child: _ItemAccuracyRow(
                          row: Map<String, dynamic>.from(items[i] as Map),
                        ),
                      ),
                    SizedBox(height: v360.spacing.xl),
                  ],
                );
              },
              orElse: () => const SizedBox.shrink(),
            ),

            const SectionLabel('Signals feeding the model'),
            SizedBox(height: v360.spacing.md),
            signals.when(
              loading: () => const V360Skeleton(height: 180),
              error: (_, _) => Text(
                'Signal feed unavailable offline.',
                style: v360.text.caption.copyWith(color: colors.inkMuted),
              ),
              data: (data) => _SignalsPanel(data: data),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccuracySummary extends StatelessWidget {
  const _AccuracySummary({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final mape = (data['overall_mape'] as num?)?.toDouble();
    final scored = (data['items_scored'] as num?)?.toInt() ?? 0;
    final lookback = (data['lookback_days'] as num?)?.toInt() ?? 14;

    // Retail demand forecasting is generally considered good under ~20% MAPE
    // and strong under ~15%; a kirana basket with erratic daily volumes is a
    // harder case than an enterprise SKU, so these bands are deliberately not
    // presented as pass/fail.
    final (String verdict, Color tone) = switch (mape) {
      null => ('Not enough history yet', colors.inkMuted),
      < 15 => ('Strong — well inside retail benchmarks', colors.accent),
      < 25 => ('Good — usable for restocking decisions', colors.accent),
      < 40 => ('Fair — treat spikes with caution', colors.warning),
      _ => ('Weak — more history needed', colors.danger),
    };

    return V360Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SectionLabel('Mean absolute percentage error'),
          SizedBox(height: v360.spacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: <Widget>[
              Text(
                mape == null ? '—' : mape.toStringAsFixed(1),
                style: v360.text.display.copyWith(color: tone),
              ),
              if (mape != null)
                Text('%', style: v360.text.titleM.copyWith(color: tone)),
            ],
          ),
          SizedBox(height: v360.spacing.xs),
          Text(verdict, style: v360.text.bodyStrong.copyWith(color: tone)),
          SizedBox(height: v360.spacing.md),
          Text(
            'Measured by hiding the last $lookback days, refitting on what came '
            'before, then comparing the prediction against what actually sold. '
            '$scored items scored.',
            style: v360.text.caption.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ItemAccuracyRow extends StatelessWidget {
  const _ItemAccuracyRow({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final mape = (row['mape'] as num).toDouble();
    final actual = (row['actual_total'] as num).toDouble();
    final predicted = (row['predicted_total'] as num).toDouble();
    final over = predicted > actual;

    final tone = switch (mape) {
      < 15 => PillTone.healthy,
      < 30 => PillTone.attention,
      _ => PillTone.urgent,
    };

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.sm),
      child: V360Card(
        padding: EdgeInsets.all(v360.spacing.lg),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    row['sku_name'] as String,
                    style: v360.text.bodyStrong.copyWith(color: colors.ink),
                  ),
                  Text(
                    'predicted ${predicted.toStringAsFixed(0)} · '
                    'actual ${actual.toStringAsFixed(0)} '
                    '(${over ? 'over' : 'under'} by '
                    '${(predicted - actual).abs().toStringAsFixed(0)})',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: '${mape.toStringAsFixed(1)}%',
              tone: tone,
              icon: over ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _SignalsPanel extends StatelessWidget {
  const _SignalsPanel({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final festivals = (data['festivals'] as List?) ?? const <dynamic>[];
    final weather = (data['weather'] as List?) ?? const <dynamic>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (weather.isNotEmpty) ...<Widget>[
          V360Card(
            padding: EdgeInsets.all(v360.spacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const SectionLabel('Rain outlook'),
                SizedBox(height: v360.spacing.md),
                SizedBox(
                  height: 62,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      for (final day in weather.take(14))
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 1.5),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                Container(
                                  height: (((day['rain_mm'] as num).toDouble() / 25)
                                          .clamp(0.04, 1.0)) *
                                      46,
                                  decoration: BoxDecoration(
                                    color: (day['is_wet'] as bool? ?? false)
                                        ? colors.accent
                                        : colors.hairline,
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                ),
                                SizedBox(height: v360.spacing.xs),
                                Text(
                                  (day['on'] as String).substring(8),
                                  style: v360.text.label.copyWith(
                                    color: colors.inkSubtle,
                                    fontSize: 8,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: v360.spacing.md),
        ],

        for (final f in festivals.take(4))
          Padding(
            padding: EdgeInsets.only(bottom: v360.spacing.sm),
            child: V360Card(
              padding: EdgeInsets.all(v360.spacing.lg),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: EdgeInsets.all(v360.spacing.sm),
                    decoration: BoxDecoration(
                      color: colors.voiceSurface,
                      borderRadius: BorderRadius.circular(V360Radius.sm),
                    ),
                    child: Icon(
                      Icons.celebration_outlined,
                      size: 16,
                      color: colors.voiceText,
                    ),
                  ),
                  SizedBox(width: v360.spacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          '${f['name']} · ${f['name_hi']}',
                          style: v360.text.bodyStrong.copyWith(color: colors.ink),
                        ),
                        Text(
                          _liftSummary(f),
                          style: v360.text.caption.copyWith(color: colors.inkMuted),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${f['days_away']}d',
                    style: v360.text.titleS.copyWith(color: colors.accentText),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _liftSummary(dynamic festival) {
    final lifts = Map<String, dynamic>.from(festival['lifts'] as Map? ?? const {});
    if (lifts.isEmpty) return 'No category effect recorded';

    final sorted = lifts.entries.toList()
      ..sort((a, b) => (b.value as num).compareTo(a.value as num));

    return sorted
        .take(3)
        .map((e) => '${e.key} +${e.value}%')
        .join(' · ');
  }
}
