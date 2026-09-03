/// A stock quantity with its unit.
///
/// Units are a value object rather than a bare string because the offline
/// merge in TRD 7.2 adds quantities from separate devices, and adding 5 kg to
/// 5 packets is a bug that a `double` cannot catch. Making the unit part of
/// the type moves that failure from a silent wrong number to a thrown error.
class Quantity {
  const Quantity(this.amount, this.unit);

  final double amount;
  final String unit;

  static const Quantity zero = Quantity(0, 'pc');

  bool get isZero => amount.abs() < 0.0001;

  Quantity operator +(Quantity other) {
    _assertSameUnit(other, '+');
    return Quantity(amount + other.amount, unit);
  }

  Quantity operator -(Quantity other) {
    _assertSameUnit(other, '-');
    return Quantity(amount - other.amount, unit);
  }

  /// Never negative. A shelf cannot hold less than nothing, and a negative
  /// count corrupts every forecast and reorder point downstream.
  Quantity get floored => amount < 0 ? Quantity(0, unit) : this;

  void _assertSameUnit(Quantity other, String op) {
    if (other.unit != unit) {
      throw ArgumentError(
        'Cannot $op quantities with different units: $unit and ${other.unit}',
      );
    }
  }

  /// Display at a precision the number deserves.
  ///
  /// [display] keeps two decimals, which is right for a shopkeeper counting
  /// 2.5 kg off a shelf and wrong for an aggregated forecast: "528.79 kg
  /// across six shops" claims a precision the model does not have, and reads
  /// as false exactness next to the word "about". The threshold is
  /// magnitude-based because that is where the meaning changes — below ten
  /// units the fraction is real stock, above it it is noise.
  String get approx {
    if (amount >= 10) return '${amount.round()} $unit';
    final rounded = (amount * 10).round() / 10;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toStringAsFixed(1);
    return '$text $unit';
  }

  /// Trims a trailing `.0` so "5 kg" does not render as "5.0 kg".
  String get display {
    final rounded = (amount * 100).round() / 100;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toString();
    return '$text $unit';
  }

  @override
  bool operator ==(Object other) =>
      other is Quantity &&
      other.unit == unit &&
      (other.amount - amount).abs() < 0.0001;

  @override
  int get hashCode => Object.hash(unit, (amount * 10000).round());

  @override
  String toString() => display;
}
