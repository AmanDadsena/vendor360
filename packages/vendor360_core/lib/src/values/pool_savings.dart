import 'money.dart';

/// Pure value object computing savings and margin improvements on collective wholesale buying pools.
///
/// When multiple merchants aggregate their demand into a single wholesale
/// buying pool, they achieve bulk pricing tiers otherwise inaccessible to solo
/// stores. [PoolSavings] encapsulates the margin recovery, percentage discount,
/// and total savings for any order size without floating-point rounding errors.
class PoolSavings {
  PoolSavings({
    required this.baseUnitPrice,
    required this.bulkUnitPrice,
  }) : assert(
          baseUnitPrice.paise >= bulkUnitPrice.paise,
          'Bulk unit price cannot exceed base retail unit price',
        );

  final Money baseUnitPrice;
  final Money bulkUnitPrice;

  /// Savings per single unit/pack.
  Money get savingsPerUnit => baseUnitPrice - bulkUnitPrice;

  /// Percentage discount realized through the collective bargaining pool.
  int get discountPct => baseUnitPrice.paise == 0
      ? 0
      : ((savingsPerUnit.paise / baseUnitPrice.paise) * 100).round();

  /// Total rupee amount saved for a given order quantity.
  Money totalSaved(double qty) {
    if (qty <= 0) return Money.zero;
    final savedPaise = (savingsPerUnit.paise * qty).round();
    return Money(savedPaise);
  }

  /// Formats human-readable benefit string (e.g. "Save ₹40/pc (20% off)").
  String formatSavingsBenefit(String unit) =>
      'Save ${savingsPerUnit.display}/$unit ($discountPct% off)';
}
