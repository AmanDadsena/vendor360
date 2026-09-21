import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// The reason a forecast moved.
///
/// This component is the answer to the guide's requirement that a spike be
/// "annotated with its driving signal so the recommendation is explainable,
/// not a black box". A percentage on its own tells a vendor what the model
/// thinks; the driver tells them whether to believe it.
class DriverBadge extends StatelessWidget {
  const DriverBadge({
    super.key,
    required this.driver,
    required this.effect,
    this.compact = false,
  });

  final String driver;

  final double effect;

  final bool compact;

  bool get _isWeather {
    final lower = driver.toLowerCase();
    return lower.contains('rain') || lower.contains('weather');
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final rising = effect >= 0;
    // Attention amber for a rise, teal for a fall: marigold text is the
    // mic's, and is not borrowed for a number.
    final figure = rising ? colors.warningText : colors.accentText;

    final icon = _isWeather
        ? (rising ? Icons.water_drop_outlined : Icons.wb_cloudy_outlined)
        : Icons.celebration_outlined;

    final magnitude = '${rising ? '+' : ''}${(effect * 100).round()}%';
    final style = compact ? v360.text.label : v360.text.caption;

    // A plain reason line in ink — icon, the lift, the cause — rather than an
    // outlined chip: it explains the number, it is not a control.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(icon, size: compact ? 13 : 15, color: colors.inkMuted),
        SizedBox(width: v360.spacing.xs),
        Text(
          magnitude,
          style: style.copyWith(color: figure).weight(FontWeight.w700),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            driver,
            style: style.copyWith(color: colors.ink),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}

/// The heads-up worth acting on — a festival coming, a surge nearby — as a
/// flat marigold band, the way a pack prints its "20% extra" flash.
///
/// Flat, full-width and ink on marigold: no gradient, no icon in a tinted
/// square, no border. It is meant to be the one loud thing below the band,
/// so a screen should carry at most one.
class SignalBanner extends StatelessWidget {
  const SignalBanner({
    super.key,
    required this.title,
    required this.detail,
    this.icon = Icons.trending_up_rounded,
    this.onTap,
  });

  final String title;
  final String detail;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    // One corner cut away, the way a pack's "20% extra" flash is cut, rather
    // than another rounded rectangle.
    return Material(
      color: colors.flash,
      shape: const BeveledRectangleBorder(
        borderRadius: BorderRadius.only(
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(2),
          topLeft: Radius.circular(2),
          bottomRight: Radius.circular(2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.lg,
            v360.spacing.md,
            v360.spacing.sm,
            v360.spacing.md,
          ),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 22, color: colors.onFlash),
              SizedBox(width: v360.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: v360.text.bodyStrong
                          .copyWith(color: colors.onFlash)
                          .weight(FontWeight.w700),
                    ),
                    if (detail.isNotEmpty)
                      Text(
                        detail,
                        style: v360.text.caption
                            .copyWith(color: colors.onFlash),
                      ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right_rounded, color: colors.onFlash),
            ],
          ),
        ),
      ),
    );
  }
}
