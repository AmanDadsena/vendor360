import 'package:flutter/material.dart';

import 'motion_scope.dart';

/// Which way a transition should read.
enum V360Axis {
  /// Lateral moves between peers — switching tabs on the same level.
  horizontal,

  /// Vertical moves — a sheet or a stacked step.
  vertical,

  /// Drilling in or out — a list to its detail.
  depth,
}

/// Shared-axis transitions.
///
/// A plain cross-fade tells the eye nothing about where content went. These
/// pair a fade with a small movement along the axis the navigation actually
/// travelled, so a tab switch reads as sideways and a drill-in reads as
/// forward. The movement is deliberately small — 24px or a 4% scale — since
/// the goal is orientation, not spectacle.
///
/// Everything collapses to a plain fade under reduce-motion.
abstract final class V360Transitions {
  /// Wraps [child] so it animates whenever its key changes.
  ///
  /// Use for tab and section bodies, where the widget is replaced rather
  /// than pushed.
  static Widget switcher({
    required Widget child,
    required BuildContext context,
    V360Axis axis = V360Axis.horizontal,
    bool reverse = false,
  }) {
    final motion = MotionScope.of(context);
    return AnimatedSwitcher(
      duration: motion.base,
      switchInCurve: motion.emphasized,
      switchOutCurve: motion.standard,
      // The default layout stacks outgoing and incoming children centred,
      // which makes lists jump as they swap. Top-left alignment keeps the
      // first line of content still while the fade happens around it.
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: <Widget>[...previous, ?current],
      ),
      transitionBuilder: (child, animation) => _build(
        child: child,
        animation: animation,
        axis: axis,
        reverse: reverse,
        reduced: motion.reduced,
      ),
      child: child,
    );
  }

  /// A page transition for `go_router` or `PageRouteBuilder`.
  static Widget page({
    required Widget child,
    required Animation<double> animation,
    required BuildContext context,
    V360Axis axis = V360Axis.depth,
  }) {
    final motion = MotionScope.of(context);
    return _build(
      child: child,
      animation: animation,
      axis: axis,
      reverse: false,
      reduced: motion.reduced,
    );
  }

  static Widget _build({
    required Widget child,
    required Animation<double> animation,
    required V360Axis axis,
    required bool reverse,
    required bool reduced,
  }) {
    final fade = FadeTransition(opacity: animation, child: child);
    if (reduced) return fade;

    switch (axis) {
      case V360Axis.horizontal:
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(reverse ? -0.06 : 0.06, 0),
            end: Offset.zero,
          ).animate(animation),
          child: fade,
        );
      case V360Axis.vertical:
        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(0, reverse ? -0.04 : 0.04),
            end: Offset.zero,
          ).animate(animation),
          child: fade,
        );
      case V360Axis.depth:
        // Scale rather than slide: drilling in should feel like moving
        // toward the content, not past it.
        return ScaleTransition(
          scale: Tween<double>(begin: reverse ? 1.04 : 0.96, end: 1)
              .animate(animation),
          child: fade,
        );
    }
  }
}

/// Pull-to-refresh in the Vendor360 accent.
///
/// Material's stock indicator ignores the design system entirely — a
/// primary-coloured spinner on a themed surface is the most common way an
/// otherwise consistent app gives itself away.
class V360Refresh extends StatelessWidget {
  const V360Refresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RefreshIndicator(
      onRefresh: onRefresh,
      color: theme.colorScheme.primary,
      backgroundColor: theme.colorScheme.surface,
      strokeWidth: 2.5,
      displacement: 28,
      child: child,
    );
  }
}
