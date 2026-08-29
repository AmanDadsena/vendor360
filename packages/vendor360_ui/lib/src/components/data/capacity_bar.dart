import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_colors.dart';
import '../../tokens/v360_theme.dart';

/// A boot-capacity progress bar.
///
/// Colour communicates urgency: mint while there is room, amber as the boot
/// fills, coral when effectively full. Thresholds match the "filling fast"
/// treatment in the design.
class CapacityBar extends StatelessWidget {
  const CapacityBar({
    super.key,
    required this.fraction,
    this.height = 6,
    this.animate = true,
  });

  /// 0..1. Values outside the range are clamped.
  final double fraction;
  final double height;
  final bool animate;

  static Color colorFor(V360Colors colors, double fraction) {
    final f = fraction.clamp(0.0, 1.0);
    if (f >= 0.95) return colors.danger;
    if (f >= 0.75) return colors.warning;
    return colors.accent;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    final motion = MotionScope.of(context);
    final target = fraction.clamp(0.0, 1.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: colors.hairline,
            borderRadius: BorderRadius.circular(height),
          ),
          alignment: Alignment.centerLeft,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: target),
            duration: animate ? motion.slow : Duration.zero,
            curve: motion.standard,
            builder: (context, value, _) => Container(
              width: constraints.maxWidth * value,
              height: height,
              decoration: BoxDecoration(
                color: colorFor(colors, value),
                borderRadius: BorderRadius.circular(height),
              ),
            ),
          ),
        );
      },
    );
  }
}
