import 'package:vendor360_core/vendor360_core.dart';

/// The customer credit book, as the app reads it.
///
/// Balances arrive computed: the server owns the settlement rule (payments
/// against the oldest debt first), and a second implementation here would be
/// a second answer to "what does Suresh owe" — the one argument this screen
/// exists to settle.

double _d(Object? v) => (v as num?)?.toDouble() ?? 0;
int _i(Object? v) => (v as num?)?.toInt() ?? 0;

class Customer {
  const Customer({
    required this.id,
    required this.name,
    this.phone,
    this.note,
  });

  final String id;
  final String name;
  final String? phone;
  final String? note;

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
        id: '${j['id']}',
        name: j['name'] as String? ?? '',
        phone: j['phone'] as String?,
        note: j['note'] as String?,
      );

  /// Two letters for the row's mark, from whatever the shopkeeper wrote.
  String get initials {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) {
      final one = parts.first;
      return (one.length >= 2 ? one.substring(0, 2) : one).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }
}

/// One customer as the book lists them: who, how much, how long.
class UdhaarRow {
  const UdhaarRow({
    required this.customer,
    required this.owed,
    required this.daysOutstanding,
    required this.stale,
  });

  final Customer customer;
  final Money owed;
  final int daysOutstanding;

  /// Standing longer than a month — the one to chase first.
  final bool stale;

  factory UdhaarRow.fromJson(Map<String, dynamic> j) => UdhaarRow(
        customer: Customer.fromJson(Map<String, dynamic>.from(j['customer'] as Map)),
        owed: Money.rupees(_d(j['owed'])),
        daysOutstanding: _i(j['days_outstanding']),
        stale: j['stale'] as bool? ?? false,
      );
}

class UdhaarBook {
  const UdhaarBook({
    required this.outstanding,
    required this.customers,
    required this.oldestDays,
    required this.rows,
  });

  final Money outstanding;
  final int customers;
  final int oldestDays;
  final List<UdhaarRow> rows;

  static const UdhaarBook empty = UdhaarBook(
    outstanding: Money.zero,
    customers: 0,
    oldestDays: 0,
    rows: <UdhaarRow>[],
  );

  bool get isEmpty => rows.isEmpty;

  factory UdhaarBook.fromJson(Map<String, dynamic> j) => UdhaarBook(
        outstanding: Money.rupees(_d(j['outstanding'])),
        customers: _i(j['customers']),
        oldestDays: _i(j['oldest_days']),
        rows: <UdhaarRow>[
          for (final r in (j['rows'] as List? ?? const <Object?>[]))
            UdhaarRow.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

/// One line of a customer's page.
class UdhaarEntry {
  const UdhaarEntry({
    required this.id,
    required this.kind,
    required this.amount,
    required this.occurredAt,
    this.note,
  });

  final String id;

  /// `credit` — goods taken on the book. `payment` — money returned.
  final String kind;
  final Money amount;
  final DateTime occurredAt;
  final String? note;

  bool get isCredit => kind == 'credit';

  factory UdhaarEntry.fromJson(Map<String, dynamic> j) => UdhaarEntry(
        id: '${j['id']}',
        kind: j['kind'] as String? ?? 'credit',
        amount: Money.rupees(_d(j['amount'])),
        occurredAt:
            DateTime.tryParse('${j['occurred_at']}')?.toLocal() ?? DateTime.now(),
        note: j['note'] as String?,
      );
}

class UdhaarStatement {
  const UdhaarStatement({
    required this.customer,
    required this.owed,
    required this.daysOutstanding,
    required this.entries,
  });

  final Customer customer;
  final Money owed;
  final int daysOutstanding;
  final List<UdhaarEntry> entries;

  factory UdhaarStatement.fromJson(Map<String, dynamic> j) => UdhaarStatement(
        customer: Customer.fromJson(Map<String, dynamic>.from(j['customer'] as Map)),
        owed: Money.rupees(_d(j['owed'])),
        daysOutstanding: _i(j['days_outstanding']),
        entries: <UdhaarEntry>[
          for (final e in (j['entries'] as List? ?? const <Object?>[]))
            UdhaarEntry.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}
