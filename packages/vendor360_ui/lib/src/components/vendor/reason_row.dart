import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// The short reasons behind a ranked recommendation.
///
/// Exists because an unexplained ordering is one a vendor cannot disagree
/// with, and a ranking nobody can argue with is a ranking nobody trusts.
/// *"₹18 cheaper per kg · arrives 1 day sooner · fills 96%"* invites the
/// judgement that a bare position in a list forecloses.
///
/// Reasons that start with "only" or "arrives in" are warnings — the ranking
/// telling you what is wrong with an option rather than what is right — and
/// they are tinted accordingly. Detecting that here rather than asking the
/// caller to classify keeps the API a plain list of strings.
class ReasonRow extends StatelessWidget {
  const ReasonRow({super.key, required this.reasons, this.max = 3});

  final List<String> reasons;
  final int max;

  static const List<String> _warningPrefixes = <String>[
    'only',
    'arrives in',
    'minimum',
    'no order history',
  ];

  static bool _isWarning(String reason) {
    final lowered = reason.toLowerCase();
    return _warningPrefixes.any(lowered.startsWith);
  }

  @override
  Widget build(BuildContext context) {
    if (reasons.isEmpty) return const SizedBox.shrink();

    final v360 = context.v360;
    final colors = v360.colors;

    return Wrap(
      spacing: v360.spacing.xs,
      runSpacing: v360.spacing.xs,
      children: <Widget>[
        for (final reason in reasons.take(max))
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: v360.spacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: _isWarning(reason)
                  ? colors.warningSurface
                  : colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V360Radius.pill),
            ),
            child: Text(
              reason,
              style: v360.text.label.copyWith(
                color: _isWarning(reason) ? colors.warningText : colors.inkMuted,
              ),
            ),
          ),
      ],
    );
  }
}
