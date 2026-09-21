import 'package:flutter/widgets.dart';

/// The 4pt spacing scale.
@immutable
class V360Spacing {
  const V360Spacing();

  double get xs => 4;
  double get sm => 8;
  double get md => 12;
  double get lg => 16;
  double get xl => 20;
  double get xxl => 24;
  double get x3 => 32;
  double get x4 => 40;
  double get x5 => 48;

  /// Horizontal screen padding. Material's compact-width margin, so rows
  /// line up with the system's own sheets, snackbars and dialogs.
  double get gutter => 16;

  /// Every value on the scale, for tests and iteration.
  List<double> get all => [xs, sm, md, lg, xl, xxl, x3, x4, x5];
}

/// Corner radii, cut like a carton's dieline.
///
/// Printed packs have tight corners; a 24px radius on everything is what
/// makes an interface read as a generated template. The scale is small and
/// the step is small: markers and badges at [sm], controls at [md], panels
/// and sheets at [lg] and [xl].
///
/// [pill] is deliberately larger than any component height, so
/// `BorderRadius.circular(pill)` always resolves to a true circle or pill —
/// kept for the few things that are round in life, like the microphone.
abstract final class V360Radius {
  static const double sm = 4;
  static const double md = 6;
  static const double lg = 8;
  static const double xl = 12;
  static const double pill = 999;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
  static final BorderRadius pillAll = BorderRadius.circular(pill);
}
