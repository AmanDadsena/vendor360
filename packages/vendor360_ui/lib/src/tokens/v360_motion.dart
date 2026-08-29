import 'package:flutter/widgets.dart';

/// Motion tokens.
///
/// Never read these directly inside a widget — go through `MotionScope.of`,
/// which resolves them against the platform's reduce-motion setting.
@immutable
class V360Motion {
  const V360Motion();

  Duration get instant => const Duration(milliseconds: 90);
  Duration get fast => const Duration(milliseconds: 140);
  Duration get base => const Duration(milliseconds: 220);
  Duration get slow => const Duration(milliseconds: 340);
  Duration get deliberate => const Duration(milliseconds: 520);

  /// General-purpose easing.
  Curve get standard => Curves.easeOutCubic;

  /// For movements that should feel intentional — page transitions, heroes.
  Curve get emphasized => const Cubic(0.2, 0, 0, 1);

  Curve get decelerate => Curves.decelerate;

  /// Overshoot, for things that snap into place — timeline nodes, scan checks.
  Curve get overshoot => Curves.easeOutBack;

  /// For anything representing a physical object — a parcel dropping into a
  /// bay, a request card springing back from a swipe.
  SpringDescription get spring =>
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.9);
}
