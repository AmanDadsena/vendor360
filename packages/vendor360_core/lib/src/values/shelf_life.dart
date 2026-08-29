/// Time remaining before stock spoils.
///
/// Days-remaining and the urgency band derived from it live together, because
/// every screen that shows one needs the other, and two screens disagreeing
/// about what "critical" means is how an expiry board loses a vendor's trust.
class ShelfLife {
  const ShelfLife({required this.expiresOn, required this.today});

  final DateTime expiresOn;
  final DateTime today;

  int get daysLeft =>
      DateTime(expiresOn.year, expiresOn.month, expiresOn.day)
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;

  bool get isExpired => daysLeft < 0;

  ExpiryUrgency get urgency {
    if (daysLeft < 0) return ExpiryUrgency.expired;
    if (daysLeft <= 1) return ExpiryUrgency.critical;
    if (daysLeft <= 3) return ExpiryUrgency.warning;
    if (daysLeft <= 7) return ExpiryUrgency.watch;
    return ExpiryUrgency.fine;
  }

  /// Markdown depth that clears stock before it is written off entirely.
  /// Steepens as the window closes: 10% on the last day clears nothing, and
  /// unsold stock is a total loss rather than a discounted sale.
  int get suggestedDiscountPct => switch (daysLeft) {
        <= 0 => 50,
        1 => 40,
        2 => 30,
        3 => 20,
        <= 5 => 10,
        _ => 0,
      };

  String get label {
    if (daysLeft < -1) return 'Expired ${-daysLeft} days ago';
    if (daysLeft == -1) return 'Expired yesterday';
    if (daysLeft == 0) return 'Expires today';
    if (daysLeft == 1) return 'Expires tomorrow';
    return 'Expires in $daysLeft days';
  }
}

enum ExpiryUrgency { expired, critical, warning, watch, fine }
