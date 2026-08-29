import 'package:flutter/widgets.dart';

import 'motion_scope.dart';

/// Fades and lifts a widget in on first build.
///
/// Borrowed from the sender's `CoReveal`. The crew app was doing this by
/// hand in five places with `.animate(delay: Duration(milliseconds: 40 * i))`
/// — same intent, five chances to pick a different delay, and no shared
/// answer for what reduced-motion should do.
///
/// Give siblings ascending [delayIndex] values and they arrive in sequence.
/// The index is clamped, so a hundred-row manifest does not make the last row
/// wait four seconds: past [maxStagger] everything lands together, which is
/// what a long list wants anyway.
///
/// Under reduced motion the child is rendered immediately and unanimated.
/// Content is never gated behind an animation that may not run.
class V360Reveal extends StatefulWidget {
  const V360Reveal({
    super.key,
    required this.child,
    this.delayIndex = 0,
    this.offset = 12,
  });

  final Widget child;

  /// Position in the stagger. 0 starts immediately.
  final int delayIndex;

  /// How far the child rises, in logical pixels.
  final double offset;

  /// Beyond this many steps, everything arrives at once.
  static const int maxStagger = 6;

  /// The gap between neighbours.
  static const Duration step = Duration(milliseconds: 40);

  @override
  State<V360Reveal> createState() => _V360RevealState();
}

class _V360RevealState extends State<V360Reveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;

    if (MotionScope.of(context).reduced) {
      _controller.value = 1;
      return;
    }

    final delay = V360Reveal.step *
        widget.delayIndex.clamp(0, V360Reveal.maxStagger);
    Future<void>.delayed(delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: MotionScope.of(context).decelerate,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) => Opacity(
        opacity: curved.value,
        child: Transform.translate(
          offset: Offset(0, (1 - curved.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
