import 'package:flutter/widgets.dart';

import '../tokens/v360_motion.dart';

/// Motion durations already resolved against the reduce-motion setting.
@immutable
class ResolvedMotion {
  const ResolvedMotion({
    required this.instant,
    required this.fast,
    required this.base,
    required this.slow,
    required this.deliberate,
    required this.standard,
    required this.emphasized,
    required this.decelerate,
    required this.overshoot,
    required this.spring,
    required this.reduced,
  });

  final Duration instant;
  final Duration fast;
  final Duration base;
  final Duration slow;
  final Duration deliberate;
  final Curve standard;
  final Curve emphasized;
  final Curve decelerate;
  final Curve overshoot;
  final SpringDescription spring;

  /// True when the platform has asked for reduced motion.
  ///
  /// Widgets that would otherwise translate or scale should cross-fade
  /// instead when this is set.
  final bool reduced;

  factory ResolvedMotion.from(V360Motion m, {required bool reduced}) {
    Duration d(Duration value) => reduced ? Duration.zero : value;
    return ResolvedMotion(
      instant: d(m.instant),
      fast: d(m.fast),
      base: d(m.base),
      slow: d(m.slow),
      deliberate: d(m.deliberate),
      standard: m.standard,
      emphasized: m.emphasized,
      decelerate: m.decelerate,
      overshoot: m.overshoot,
      spring: m.spring,
      reduced: reduced,
    );
  }
}

/// Resolves [V360Motion] against `MediaQuery.disableAnimations`.
///
/// Place once above the app. Every animated Vendor360 component reads its
/// durations from here, so honouring the accessibility setting is a single
/// switch rather than a per-widget obligation.
class MotionScope extends InheritedWidget {
  const MotionScope({
    super.key,
    this.motion = const V360Motion(),
    required super.child,
  });

  final V360Motion motion;

  static ResolvedMotion of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<MotionScope>();
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return ResolvedMotion.from(
      scope?.motion ?? const V360Motion(),
      reduced: reduced,
    );
  }

  @override
  bool updateShouldNotify(MotionScope oldWidget) => motion != oldWidget.motion;
}
