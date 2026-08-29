import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import '../data/rolling_number.dart';

/// A single glanceable figure.
///
/// The UI/UX guide requires key numbers to be readable "in under two seconds,
/// in bright sunlight, at arm's length", so the value is set in the display
/// style and the label is deliberately smaller — the opposite of the usual
/// dashboard habit of equal-weight label and value.
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.icon,
    this.tone,
    this.onTap,
    this.animateFrom,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? caption;
  final IconData? icon;

  /// Overrides the value colour for alert states. Pass a token, never a
  /// literal.
  final Color? tone;

  final VoidCallback? onTap;

  /// When set, the value counts up from this number on first build.
  final double? animateFrom;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final valueColor = tone ?? colors.ink;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 14, color: tone ?? colors.inkSubtle),
              SizedBox(width: v360.spacing.xs),
            ],
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: v360.text.label.copyWith(color: colors.inkSubtle),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        SizedBox(height: v360.spacing.sm),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: animateFrom == null
              ? Text(
                  value,
                  style: (compact ? v360.text.titleL : v360.text.display)
                      .copyWith(color: valueColor, height: 1.0),
                )
              : RollingNumber(
                  value: animateFrom!,
                  style: (compact ? v360.text.titleL : v360.text.display)
                      .copyWith(color: valueColor, height: 1.0),
                ),
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

    return Container(
      padding: EdgeInsets.all(compact ? v360.spacing.lg : v360.spacing.xl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.lg),
        border: v360.isDark ? Border.all(color: colors.hairline) : null,
        boxShadow: v360.isDark
            ? null
            : <BoxShadow>[
                BoxShadow(
                  color: colors.ink.withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(V360Radius.lg),
              child: content,
            ),
    );
  }
}

/// A status pill.
///
/// Colour is never the only signal — the guide requires an icon or label
/// alongside it for colour-blind users, so [icon] pairs with every tone and
/// the text is always present.
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

    final (Color fill, Color text, IconData fallback) = switch (tone) {
      PillTone.healthy => (
          colors.accentSurface,
          colors.accentText,
          Icons.check_circle_outline_rounded
        ),
      PillTone.attention => (
          colors.warningSurface,
          colors.warningText,
          Icons.error_outline_rounded
        ),
      PillTone.urgent => (
          colors.dangerSurface,
          colors.dangerText,
          Icons.priority_high_rounded
        ),
      PillTone.neutral => (
          colors.surfaceMuted,
          colors.inkMuted,
          Icons.circle_outlined
        ),
      PillTone.voice => (
          colors.voiceSurface,
          colors.voiceText,
          Icons.mic_none_rounded
        ),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? v360.spacing.sm : v360.spacing.md,
        vertical: dense ? 2 : v360.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon ?? fallback, size: dense ? 11 : 13, color: text),
          SizedBox(width: v360.spacing.xs),
          Text(
            label,
            style: (dense ? v360.text.label : v360.text.caption).copyWith(
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

enum PillTone { healthy, attention, urgent, neutral, voice }
