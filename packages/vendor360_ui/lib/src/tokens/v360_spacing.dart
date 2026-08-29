import 'package:flutter/widgets.dart';

/// The 4pt spacing scale from the design PDF.
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

  /// Horizontal screen padding.
  double get gutter => 20;

  /// Every value on the scale, for tests and iteration.
  List<double> get all => [xs, sm, md, lg, xl, xxl, x3, x4, x5];
}

/// Corner radii.
///
/// [pill] is deliberately larger than any component height, so
/// `BorderRadius.circular(pill)` always resolves to a true pill regardless
/// of the widget's size.
abstract final class V360Radius {
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;

  static final BorderRadius smAll = BorderRadius.circular(sm);
  static final BorderRadius mdAll = BorderRadius.circular(md);
  static final BorderRadius lgAll = BorderRadius.circular(lg);
  static final BorderRadius xlAll = BorderRadius.circular(xl);
  static final BorderRadius pillAll = BorderRadius.circular(pill);
}
