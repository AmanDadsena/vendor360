import 'dart:math' as math;

import 'quantity.dart';

/// A wholesale order expressed the way wholesalers actually sell: in cases.
///
/// A shop that needs 12 kg of atta against a 10 kg case buys two cases and
/// receives 20 kg. That rounding is the single most surprising thing about
/// ordering from a distributor, so it is modelled explicitly rather than left
/// as arithmetic scattered through the UI — and [surplus] exists so a screen
/// can *show* the surplus instead of quietly charging for it.
///
/// Lives in core rather than in the app because the same rounding has to
/// agree between the sourcing sheet, the cart, and the order confirmation. A
/// second implementation is a second chance to disagree with the server.
class PackQuantity {
  const PackQuantity({
    required this.packs,
    required this.packSize,
    required this.unit,
    this.moqApplied = false,
  });

  /// How many cases. Whole numbers — a distributor will not split a case.
  final int packs;

  /// Selling units in one case.
  final double packSize;

  final String unit;

  /// True when the case count was raised to meet a minimum order rather than
  /// determined by what the shop needs. Worth surfacing: it is the difference
  /// between "you need this" and "they will not sell you less".
  final bool moqApplied;

  static const PackQuantity none =
      PackQuantity(packs: 0, packSize: 1, unit: 'pc');

  /// The smallest whole number of cases covering [shortfall], respecting a
  /// minimum order quantity.
  ///
  /// Rounds up, always. Rounding to nearest would leave a shop short of the
  /// thing it just ordered, which is the one outcome the whole flow exists to
  /// prevent.
  factory PackQuantity.forShortfall({
    required double shortfall,
    required double packSize,
    required String unit,
    int moqPacks = 1,
  }) {
    if (packSize <= 0) {
      throw ArgumentError.value(packSize, 'packSize', 'must be greater than zero');
    }

    final needed = shortfall <= 0 ? 0 : (shortfall / packSize).ceil();
    final floor = math.max(moqPacks, 1);
    final packs = math.max(needed, floor);

    return PackQuantity(
      packs: packs,
      packSize: packSize,
      unit: unit,
      moqApplied: needed < floor,
    );
  }

  bool get isEmpty => packs <= 0;

  /// Total selling units delivered.
  double get quantity => packs * packSize;

  Quantity get asQuantity => Quantity(quantity, unit);

  /// How much more than asked for arrives, purely because of case sizing.
  double surplusOver(double shortfall) =>
      math.max(0, quantity - math.max(shortfall, 0));

  double costAt(double packPrice) => packs * packPrice;

  PackQuantity copyWith({int? packs}) => PackQuantity(
        packs: packs ?? this.packs,
        packSize: packSize,
        unit: unit,
        // Changing the count by hand means the minimum is no longer what
        // determined it, unless the new count is still at or below the floor.
        moqApplied: packs == null ? moqApplied : false,
      );

  /// "2 × 10 kg" — how a wholesaler quotes it over the phone.
  String get packDisplay {
    final size = packSize == packSize.roundToDouble()
        ? packSize.toStringAsFixed(0)
        : packSize.toString();
    return '$packs × $size $unit';
  }

  /// "2 cases · 20 kg" — the count and what it comes to.
  String get display => '$packs ${packs == 1 ? 'case' : 'cases'} · '
      '${asQuantity.display}';

  @override
  bool operator ==(Object other) =>
      other is PackQuantity &&
      other.packs == packs &&
      other.unit == unit &&
      (other.packSize - packSize).abs() < 0.0001;

  @override
  int get hashCode => Object.hash(packs, unit, (packSize * 10000).round());

  @override
  String toString() => display;
}
