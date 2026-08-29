import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// A shimmering placeholder shown while content loads.
///
/// Sized like the thing it stands in for, so the layout does not jump when
/// real content arrives — a list of parcel cards should not reflow the
/// moment the network answers.
class V360Skeleton extends StatefulWidget {
  const V360Skeleton({
    super.key,
    this.width,
    this.height = 16,
    this.radius = V360Radius.sm,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  State<V360Skeleton> createState() => _V360SkeletonState();
}

class _V360SkeletonState extends State<V360Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sweep = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Under reduce-motion the block renders flat rather than sweeping, and
    // the controller is stopped so it schedules no frames.
    if (MotionScope.of(context).reduced) {
      if (_sweep.isAnimating) _sweep.stop();
    } else if (!_sweep.isAnimating) {
      _sweep.repeat();
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    final reduced = MotionScope.of(context).reduced;

    final base = Container(
      width: widget.width ?? double.infinity,
      height: widget.height,
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );

    if (reduced) return base;

    // A shimmer repaints every frame forever. Without a boundary that
    // repaint propagates to the whole list it sits in, so a screen of
    // skeletons costs far more than the skeletons themselves.
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.radius),
        child: Stack(
          children: <Widget>[
            base,
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _sweep,
                builder: (context, _) => ShaderMask(
                  blendMode: BlendMode.srcATop,
                  shaderCallback: (rect) => LinearGradient(
                    begin: Alignment(-1 - (_sweep.value * 2), 0),
                    end: Alignment(1 - (_sweep.value * 2), 0),
                    colors: <Color>[
                      const Color(0x00000000),
                      colors.accent.withValues(alpha: 0.14),
                      const Color(0x00000000),
                    ],
                  ).createShader(rect),
                  child: Container(color: colors.surfaceMuted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
