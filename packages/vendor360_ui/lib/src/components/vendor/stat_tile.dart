import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import '../data/rolling_number.dart';
import '../feedback/status_mark.dart';

/// One figure, laid out like a line of a pack's small-print panel: what it
/// is, then how much.
///
/// The key numbers must read "in under two seconds, in bright sunlight, at
/// arm's length", so the value is set large and narrow in ink and the label
/// is small and plain above it — in the case it was written, not tracked-out
/// uppercase, and with no icon box. When the figure needs attention, [tone]
/// prints a small square of colour before the label; the number itself stays
/// ink, because amber digits are the first thing to wash out in daylight.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tone,
    this.onTap,
    this.animateFrom,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? caption;

  /// The status colour for this figure, as a token. Null when all is well.
  final Color? tone;

  final VoidCallback? onTap;

  /// When set, the value counts up from this number on first build.
  final double? animateFrom;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final valueStyle = v360.text.figure.copyWith(
      color: colors.ink,
      height: 1.0,
      fontSize: compact ? 26 : null,
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: tone == null
                  ? Text(
                      label,
                      style: v360.text.caption.copyWith(color: colors.inkMuted),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : StatusMark(label: label, color: tone!, emphasis: false),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: colors.inkSubtle),
          ],
        ),
        SizedBox(height: v360.spacing.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: animateFrom == null
              ? Text(value, style: valueStyle)
              : RollingNumber(value: animateFrom!, style: valueStyle),
        ),
        if (caption != null) ...<Widget>[
          SizedBox(height: v360.spacing.xs),
          Text(
            caption!,
            style: v360.text.caption.copyWith(color: colors.inkMuted),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );

    return Material(
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      clipBehavior: Clip.antiAlias,
      // The label, value and caption are three separate Text widgets, so a
      // screen reader would otherwise announce them as three unrelated
      // fragments — "overdue", "₹3,200" — with nothing tying them together.
      // Merging into one node reads them as the single fact they are.
      child: Semantics(
        button: onTap != null,
        label: <String>[label, value, ?caption].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.all(compact ? 14 : v360.spacing.lg),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// A status tag: a [StatusMark] in a small ruled box, for the end of a row.
///
/// Colour is never the only signal — the word is always printed, and the
/// colour lives only in the square (or in [icon], when one is given).
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
    this.dense = false,
  });

  final String label;
  final PillTone tone;
  final IconData? icon;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final color = switch (tone) {
      PillTone.healthy => colors.accent,
      PillTone.attention => colors.warning,
      PillTone.urgent => colors.danger,
      PillTone.neutral => colors.inkSubtle,
      PillTone.voice => colors.voice,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : v360.spacing.sm,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.sm),
        border: Border.all(color: colors.hairline),
      ),
      child: StatusMark(label: label, color: color, icon: icon, dense: dense),
    );
  }
}

enum PillTone { healthy, attention, urgent, neutral, voice }
