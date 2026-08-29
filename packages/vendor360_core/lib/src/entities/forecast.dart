/// A demand forecast for one item.
///
/// Every day carries the signal that moved it. A prediction without its driver
/// is a number a vendor has no reason to act on — the explanation is the
/// product, not decoration (UI/UX 5.5).
class Forecast {
  const Forecast({
    required this.itemId,
    required this.skuName,
    required this.category,
    required this.days,
    required this.headline,
    required this.modelVersion,
    required this.usedFallback,
    required this.historyDays,
  });

  final String itemId;
  final String skuName;
  final String category;
  final List<ForecastDay> days;

  /// One plain-language sentence: "Stock 20% more milk before Friday."
  final String headline;

  final String modelVersion;

  /// True when the item had too little history and borrowed its category's
  /// average. Surfaced in the UI so a vendor knows the claim is weaker
  /// (TC-F04).
  final bool usedFallback;

  final int historyDays;

  double get total => days.fold(0.0, (sum, d) => sum + d.predicted);

  ForecastDay? get peak => days.isEmpty
      ? null
      : days.reduce((a, b) => a.predicted >= b.predicted ? a : b);

  /// The strongest named driver across the horizon, if any.
  String? get dominantDriver {
    ForecastDay? best;
    for (final day in days) {
      if (day.driver == null) continue;
      if (best == null || day.driverEffect.abs() > best.driverEffect.abs()) {
        best = day;
      }
    }
    return best?.driver;
  }

  /// Largest predicted value, used to scale a sparkline. Falls back to 1 so a
  /// chart of an all-zero forecast divides by something.
  double get maxPredicted {
    if (days.isEmpty) return 1;
    final top = days.map((d) => d.upper).reduce((a, b) => a > b ? a : b);
    return top <= 0 ? 1 : top;
  }
}

class ForecastDay {
  const ForecastDay({
    required this.on,
    required this.predicted,
    required this.lower,
    required this.upper,
    this.driver,
    this.driverEffect = 0,
  });

  final DateTime on;
  final double predicted;

  /// The confidence band. A single number would imply precision the model
  /// does not have.
  final double lower;
  final double upper;

  final String? driver;
  final double driverEffect;

  bool get hasSignal => driver != null && driverEffect.abs() >= 0.05;
  bool get isPositiveSignal => hasSignal && driverEffect > 0;
}
