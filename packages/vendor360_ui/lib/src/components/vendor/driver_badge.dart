import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
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

  /// The named signal — a festival, or a weather condition.
  final String driver;

  /// Signed magnitude. Negative signals matter as much as positive ones: rain
  /// suppresses cold drinks, and over-ordering on a wet week is waste.
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
    final fill = rising ? colors.voiceSurface : colors.accentSurface;
    final text = rising ? colors.voiceText : colors.accentText;

    final icon = _isWeather
        ? (rising ? Icons.water_drop_outlined : Icons.wb_cloudy_outlined)
        : Icons.celebration_outlined;

    final magnitude = '${rising ? '+' : ''}${(effect * 100).round()}%';

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? v360.spacing.sm : v360.spacing.md,
        vertical: compact ? 3 : v360.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: compact ? 12 : 14, color: text),
          SizedBox(width: v360.spacing.xs),
          Text(
            compact ? '$magnitude $driver' : '$magnitude · $driver',
            style: (compact ? v360.text.label : v360.text.caption).copyWith(
              color: text,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// The forward-looking headline on the dashboard.
///
/// One sentence, one action. The guide asks for a two-second read, so this
/// deliberately carries a single signal rather than a feed of them — a vendor
/// mid-transaction will read one line, not five.
class SignalBanner extends StatelessWidget {
  const SignalBanner({
    super.key,
    required this.title,
    required this.detail,
    this.icon = Icons.insights_rounded,
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

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V360Radius.lg),
      child: Container(
        padding: EdgeInsets.all(v360.spacing.xl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[colors.accentSurfaceStrong, colors.accentSurface],
          ),
          borderRadius: BorderRadius.circular(V360Radius.lg),
          border: Border.all(color: colors.accent.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: EdgeInsets.all(v360.spacing.md),
              decoration: BoxDecoration(
                color: colors.accent,
                borderRadius: BorderRadius.circular(V360Radius.sm),
              ),
              child: Icon(icon, size: 20, color: Colors.white),
            ),
            SizedBox(width: v360.spacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: v360.text.titleS.copyWith(color: colors.accentText),
                  ),
                  SizedBox(height: v360.spacing.xs),
                  Text(
                    detail,
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: colors.accentText),
          ],
        ),
      ),
    );
  }
}
