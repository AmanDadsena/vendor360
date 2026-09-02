import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// One entry on an order's history.
class TimelineStep {
  const TimelineStep({
    required this.label,
    required this.timestamp,
    this.detail,
    this.actor,
    this.isTerminal = false,
  });

  final String label;

  /// Pre-formatted by the caller. The design system does not own date
  /// formatting, because the app's locale rules live with the app's strings.
  final String timestamp;

  final String? detail;

  /// "You" / "Balaji Distributors" — who moved it.
  final String? actor;

  /// Draws the step in the danger tone. Used for cancellation, which is the
  /// one history entry that is not progress.
  final bool isTerminal;
}

/// A vertical order history.
///
/// Reads as a receipt rather than a log: the two parties use this to settle
/// "you said you dispatched it Tuesday", so every step carries who did it and
/// when, and the whole thing is ordered oldest-first the way a paper trail is.
class OrderTimeline extends StatelessWidget {
  const OrderTimeline({
    super.key,
    required this.steps,
    this.pending,
  });

  final List<TimelineStep> steps;

  /// The stage this order is waiting on, drawn hollow beneath the history.
  /// Null once the order is settled.
  final String? pending;

  @override
  Widget build(BuildContext context) {
    if (steps.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (var i = 0; i < steps.length; i++)
          _Row(
            step: steps[i],
            isFirst: i == 0,
            isLast: i == steps.length - 1 && pending == null,
          ),
        if (pending != null)
          _Row(
            step: TimelineStep(label: pending!, timestamp: 'waiting'),
            isFirst: false,
            isLast: true,
            hollow: true,
          ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.step,
    required this.isFirst,
    required this.isLast,
    this.hollow = false,
  });

  final TimelineStep step;
  final bool isFirst;
  final bool isLast;
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final tint = step.isTerminal
        ? colors.dangerText
        : hollow
            ? colors.inkSubtle
            : colors.accentText;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 24,
            child: Column(
              children: <Widget>[
                // The rail above the first dot is omitted rather than drawn
                // transparent, so the column starts flush with the label.
                SizedBox(
                  height: 6,
                  child: isFirst
                      ? null
                      : Center(
                          child: Container(width: 1.5, color: colors.hairline),
                        ),
                ),
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: hollow ? colors.surface : tint,
                    shape: BoxShape.circle,
                    border: Border.all(color: tint, width: 1.5),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Center(
                      child: Container(width: 1.5, color: colors.hairline),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: v360.spacing.sm),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          step.label,
                          style: v360.text.bodyStrong.copyWith(
                            color: hollow ? colors.inkSubtle : colors.ink,
                          ),
                        ),
                      ),
                      Text(
                        step.timestamp,
                        style: v360.text.label.copyWith(color: colors.inkSubtle),
                      ),
                    ],
                  ),
                  if (step.actor != null || step.detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        <String>[
                          if (step.actor != null) step.actor!,
                          if (step.detail != null) step.detail!,
                        ].join(' · '),
                        style: v360.text.caption.copyWith(
                          color: colors.inkMuted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
