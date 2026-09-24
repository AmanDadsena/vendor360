import 'package:vendor360_core/vendor360_core.dart';

/// The day, closed, and the series a chart is drawn from.

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class SoldItem {
  const SoldItem({
    required this.skuName,
    required this.quantity,
    required this.value,
  });

  final String skuName;
  final Quantity quantity;
  final Money value;

  factory SoldItem.fromJson(Map<String, dynamic> j) => SoldItem(
        skuName: j['sku_name'] as String? ?? '',
        quantity: Quantity(_d(j['qty']), j['unit'] as String? ?? ''),
        value: Money.rupees(_d(j['value'])),
      );
}

class DayClose {
  const DayClose({
    required this.on,
    required this.salesValue,
    required this.transactionCount,
    required this.cashIn,
    required this.wastageValue,
    required this.restockValue,
    required this.udhaarGiven,
    required this.udhaarCollected,
    required this.lowStockCount,
    required this.topItems,
  });

  final DateTime on;
  final Money salesValue;
  final int transactionCount;

  /// Sales less what went out on the book, plus what came back. Not the same
  /// as sales, and the difference is the point.
  final Money cashIn;

  final Money wastageValue;
  final Money restockValue;
  final Money udhaarGiven;
  final Money udhaarCollected;
  final int lowStockCount;
  final List<SoldItem> topItems;

  factory DayClose.fromJson(Map<String, dynamic> j) => DayClose(
        on: DateTime.tryParse('${j['on']}') ?? DateTime.now(),
        salesValue: Money.rupees(_d(j['sales_value'])),
        transactionCount: _i(j['transaction_count']),
        cashIn: Money.rupees(_d(j['cash_in'])),
        wastageValue: Money.rupees(_d(j['wastage_value'])),
        restockValue: Money.rupees(_d(j['restock_value'])),
        udhaarGiven: Money.rupees(_d(j['udhaar_given'])),
        udhaarCollected: Money.rupees(_d(j['udhaar_collected'])),
        lowStockCount: _i(j['low_stock_count']),
        topItems: <SoldItem>[
          for (final i in (j['top_items'] as List? ?? const <Object?>[]))
            SoldItem.fromJson(Map<String, dynamic>.from(i as Map)),
        ],
      );
}

/// One day of takings.
class SalesPoint {
  const SalesPoint({required this.on, required this.value, required this.count});

  final DateTime on;
  final Money value;
  final int count;

  factory SalesPoint.fromJson(Map<String, dynamic> j) => SalesPoint(
        on: DateTime.tryParse('${j['on']}') ?? DateTime.now(),
        value: Money.rupees(_d(j['value'])),
        count: _i(j['count']),
      );
}
