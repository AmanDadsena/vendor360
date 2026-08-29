import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// A number whose digits slide vertically when the value changes.
///
/// Relies on the tabular figures set on every Vendor360 text style — with
/// proportional digits the columns jitter as different-width glyphs swap in.
class RollingNumber extends StatelessWidget {
  const RollingNumber({
    super.key,
    required this.value,
    this.style,
    this.prefix = '',
    this.suffix = '',
  });

  final num value;
  final TextStyle? style;
  final String prefix;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final motion = MotionScope.of(context);
    final effective =
        style ?? v360.text.display.copyWith(color: v360.colors.ink);
    final digits = value.toString().split('');

    // A four- or five-digit figure at display size can exceed a narrow
    // card. Scaling down preserves the design's big-number treatment
    // instead of overflowing or wrapping mid-number.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: AlignmentDirectional.centerStart,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: <Widget>[
          if (prefix.isNotEmpty) Text(prefix, style: effective),
          for (var i = 0; i < digits.length; i++)
            AnimatedSwitcher(
              duration: motion.base,
              switchInCurve: motion.standard,
              transitionBuilder: (child, animation) {
                if (motion.reduced) {
                  return FadeTransition(opacity: animation, child: child);
                }
                return ClipRect(
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 1),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Text(
                digits[i],
                key: ValueKey<String>('$i-${digits[i]}'),
                style: effective,
              ),
            ),
          if (suffix.isNotEmpty) Text(suffix, style: effective),
        ],
      ),
    );
  }
}

/// A large figure over a small uppercase label.
class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.prefix,
    this.valueColor,
  });

  final String label;
  final num value;
  final String? unit;

  /// Rendered before the digits. A currency symbol belongs in front of a
  /// figure, so `unit` alone could not express `₹1,180`; RollingNumber
  /// already supported this and MetricTile simply did not pass it through.
  final String? prefix;

  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Ellipsised here so a long label cannot overflow a narrow metric
        // card at any call site.
        Text(
          label.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: v360.text.label.copyWith(color: v360.colors.inkSubtle),
        ),
        SizedBox(height: v360.spacing.sm),
        RollingNumber(
          value: value,
          prefix: prefix ?? '',
          suffix: unit ?? '',
          style: v360.text.display.copyWith(
            color: valueColor ?? v360.colors.ink,
          ),
        ),
      ],
    );
  }
}
