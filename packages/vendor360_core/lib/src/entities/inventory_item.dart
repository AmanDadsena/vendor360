import '../values/money.dart';
import '../values/quantity.dart';
import '../values/shelf_life.dart';

/// A stocked product.
///
/// `reorderPoint` is server-computed and never edited on the device; the app
/// displays it as a live threshold rather than a setting, which is what
/// distinguishes dynamic safety stock from the fixed thresholds ledger apps
/// use (UI/UX 5.4).
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.skuName,
    required this.category,
    required this.quantity,
    required this.reorderPoint,
    required this.unitCost,
    required this.unitPrice,
    this.shelfLifeDays,
    this.expiresOn,
    this.syncStatus = SyncStatus.synced,
    this.lastUpdated,
  });

  final String id;
  final String skuName;
  final String category;
  final Quantity quantity;
  final double reorderPoint;
  final Money unitCost;
  final Money unitPrice;
  final int? shelfLifeDays;
  final DateTime? expiresOn;
  final SyncStatus syncStatus;
  final DateTime? lastUpdated;

  bool get isLow => quantity.amount <= reorderPoint;
  bool get isOut => quantity.isZero;
  bool get isPerishable => shelfLifeDays != null;

  ShelfLife? shelfLife(DateTime today) =>
      expiresOn == null ? null : ShelfLife(expiresOn: expiresOn!, today: today);

  Money get valueAtCost => unitCost * quantity.amount;

  /// How many days the current shelf lasts at a given daily rate.
  double? daysOfCover(double dailyDemand) =>
      dailyDemand <= 0 ? null : quantity.amount / dailyDemand;

  /// The single state a row should render as.
  ///
  /// Ordered by severity rather than by field, so a perishable that is both
  /// low and expired reports `expired` — the more urgent fact, and the one
  /// that changes what the vendor should do.
  StockState state(DateTime today) {
    final life = shelfLife(today);
    if (life != null && life.isExpired) return StockState.expired;
    if (isOut) return StockState.out;
    if (life != null && life.urgency == ExpiryUrgency.critical) {
      return StockState.expiringSoon;
    }
    if (isLow) return StockState.low;
    return StockState.healthy;
  }

  InventoryItem copyWith({
    Quantity? quantity,
    double? reorderPoint,
    SyncStatus? syncStatus,
    DateTime? expiresOn,
    DateTime? lastUpdated,
  }) =>
      InventoryItem(
        id: id,
        skuName: skuName,
        category: category,
        quantity: quantity ?? this.quantity,
        reorderPoint: reorderPoint ?? this.reorderPoint,
        unitCost: unitCost,
        unitPrice: unitPrice,
        shelfLifeDays: shelfLifeDays,
        expiresOn: expiresOn ?? this.expiresOn,
        syncStatus: syncStatus ?? this.syncStatus,
        lastUpdated: lastUpdated ?? this.lastUpdated,
      );
}

enum StockState { healthy, low, out, expiringSoon, expired }

enum SyncStatus { synced, pending, conflict }
