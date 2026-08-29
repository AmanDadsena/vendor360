/// Rupees, stored as integer paise.
///
/// Currency is never a `double`. 0.1 + 0.2 is not 0.3 in binary floating
/// point, and a Health Score built on turnover and waste values sums thousands
/// of line items — the drift is not theoretical at that scale.
class Money implements Comparable<Money> {
  const Money(this.paise);

  factory Money.rupees(num value) => Money((value * 100).round());

  final int paise;

  static const Money zero = Money(0);

  double get rupees => paise / 100;
  bool get isZero => paise == 0;

  Money operator +(Money other) => Money(paise + other.paise);
  Money operator -(Money other) => Money(paise - other.paise);
  Money operator *(num factor) => Money((paise * factor).round());

  @override
  int compareTo(Money other) => paise.compareTo(other.paise);

  bool operator >(Money other) => paise > other.paise;
  bool operator <(Money other) => paise < other.paise;

  /// Indian digit grouping: the last three digits, then pairs.
  /// 1234567 renders as 12,34,567 — not 1,234,567, which reads as wrong here.
  String get display {
    final whole = (paise.abs() / 100).floor();
    final digits = whole.toString();

    String grouped;
    if (digits.length <= 3) {
      grouped = digits;
    } else {
      final last3 = digits.substring(digits.length - 3);
      var rest = digits.substring(0, digits.length - 3);
      final parts = <String>[];
      while (rest.length > 2) {
        parts.insert(0, rest.substring(rest.length - 2));
        rest = rest.substring(0, rest.length - 2);
      }
      if (rest.isNotEmpty) parts.insert(0, rest);
      grouped = '${parts.join(',')},$last3';
    }

    return '${paise < 0 ? '-' : ''}₹$grouped';
  }

  @override
  bool operator ==(Object other) => other is Money && other.paise == paise;

  @override
  int get hashCode => paise.hashCode;

  @override
  String toString() => display;
}
