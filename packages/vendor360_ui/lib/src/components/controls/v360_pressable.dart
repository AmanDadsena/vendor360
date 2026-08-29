import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// How hard a target reacts to a finger.
///
/// The scale is deliberately gentler on larger surfaces: a chip that shrinks
/// six percent feels crisp, and a full-width card that shrinks six percent
/// looks broken.
enum V360PressFeel {
  /// Small targets — chips, icon buttons, tiles.
  firm(0.94),

  /// Standard controls — buttons, rows.
  normal(0.955),

  /// Large surfaces where a big scale would look wrong — cards, list rows.
  soft(0.985),

  /// No scale, just a dip in opacity. For text links and inline targets.
  flat(1.0);

  const V360PressFeel(this.scale);

  final double scale;
}

/// Wraps any widget with the app's press response.
///
/// Borrowed from the sender app, where every tappable surface goes through
/// the same treatment. The crew app's cards used a bare `GestureDetector`,
/// so nothing acknowledged a finger at all — which matters more here than in
/// the sender, not less: a conductor taps this standing on a moving bus,
/// sometimes in gloves, and needs to know the tap landed without stopping to
/// read the screen.
///
/// The gesture is asymmetric, which is what makes it read as physical rather
/// than mechanical: the press sinks fast on a decelerating curve, and the
/// release travels back over roughly three times as long on a spring, so the
/// control passes a hair beyond its resting size and settles. That reads as
/// weight rather than as a bounce.
///
/// Honours reduced-motion: the scale is dropped entirely, the tap is not.
class V360Pressable extends StatefulWidget {
  const V360Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.feel = V360PressFeel.normal,
    this.haptic = true,
    this.enabled = true,
    this.semanticLabel,
    this.behavior = HitTestBehavior.opaque,
    this.highlight = false,
    this.borderRadius,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final V360PressFeel feel;
  final bool haptic;
  final bool enabled;
  final String? semanticLabel;
  final HitTestBehavior behavior;

  /// Washes the target while it is held. For rows and cards, where scale
  /// alone is too subtle to confirm which of several stacked surfaces the
  /// finger actually landed on.
  final bool highlight;

  /// The radius the highlight is clipped to, so it cannot bleed past a
  /// rounded card's corners.
  final BorderRadius? borderRadius;

  @override
  State<V360Pressable> createState() => _V360PressableState();
}

class _V360PressableState extends State<V360Pressable> {
  bool _down = false;

  /// Sinking is quick — the control has to acknowledge the finger before the
  /// finger has finished landing.
  static const Duration _sink = Duration(milliseconds: 90);

  /// Returning is slower, and overshoots. This is the part that reads as mass
  /// rather than as a state change.
  static const Duration _settle = Duration(milliseconds: 300);

  bool get _active =>
      widget.enabled && (widget.onTap != null || widget.onLongPress != null);

  void _set(bool value) {
    if (!_active || _down == value) return;
    setState(() => _down = value);
  }

  void _handleTap() {
    if (!_active) return;
    if (widget.haptic) {
      // Weight-matched: a full-width control gets a knock, a chip gets the
      // lighter selection tick. Identical feedback everywhere would flatten
      // the hierarchy the layout works to establish.
      switch (widget.feel) {
        case V360PressFeel.normal:
          HapticFeedback.lightImpact();
        case V360PressFeel.firm:
        case V360PressFeel.soft:
        case V360PressFeel.flat:
          HapticFeedback.selectionClick();
      }
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final flat = widget.feel == V360PressFeel.flat;
    final motion = MotionScope.of(context);
    // Reduced motion collapses the durations to zero, so the tap still
    // registers and only the movement goes away.
    Duration at(Duration value) => motion.reduced ? Duration.zero : value;
    final colors = context.v360.colors;

    Widget child = widget.child;

    if (widget.highlight) {
      child = Stack(
        children: <Widget>[
          child,
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedContainer(
                duration: at(_down ? _sink : _settle),
                curve: motion.decelerate,
                decoration: BoxDecoration(
                  color: colors.ink.withValues(alpha: _down ? 0.045 : 0.0),
                  borderRadius: widget.borderRadius,
                ),
              ),
            ),
          ),
        ],
      );
    }

    child = AnimatedOpacity(
      duration: at(_down ? _sink : _settle),
      opacity: _down && flat ? 0.62 : 1,
      child: child,
    );

    if (!flat) {
      child = AnimatedScale(
        duration: at(_down ? _sink : _settle),
        // `spring` rises past 1 before resting, so releasing carries the
        // control a fraction beyond its resting size. Sinking uses a plain
        // decelerate, because overshooting *into* a press feels loose.
        curve: _down ? motion.decelerate : motion.overshoot,
        scale: _down ? widget.feel.scale : 1.0,
        child: child,
      );
    }

    return Semantics(
      button: _active,
      label: widget.semanticLabel,
      child: GestureDetector(
        behavior: widget.behavior,
        onTap: _active ? _handleTap : null,
        onLongPress: _active ? widget.onLongPress : null,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        child: child,
      ),
    );
  }
}
