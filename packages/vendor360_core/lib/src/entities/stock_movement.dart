import '../values/confidence.dart';
import '../values/quantity.dart';

/// One change to stock: a sale, a restock, or spoilage.
///
/// Wastage is its own kind rather than a negative sale. The Health Score has
/// to tell spoilage apart from turnover — collapsing them would let a vendor
/// who throws away half their stock score like one who sold it.
enum MovementKind { sale, restock, wastage }

extension MovementKindX on MovementKind {
  /// Direction this movement moves the shelf.
  double get sign => this == MovementKind.restock ? 1.0 : -1.0;

  String get label => switch (this) {
        MovementKind.sale => 'Sold',
        MovementKind.restock => 'Restocked',
        MovementKind.wastage => 'Wasted',
      };

  String get wire => name;
}

MovementKind movementFromWire(String raw) => switch (raw) {
      'restock' => MovementKind.restock,
      'wastage' => MovementKind.wastage,
      _ => MovementKind.sale,
    };

enum CaptureSource { voice, ocr, manual, seed }

class StockMovement {
  const StockMovement({
    required this.id,
    required this.itemId,
    required this.kind,
    required this.quantity,
    required this.occurredAt,
    this.source = CaptureSource.manual,
    this.confidence = Confidence.certain,
    this.rawText,
  });

  final String id;
  final String itemId;
  final MovementKind kind;
  final Quantity quantity;
  final DateTime occurredAt;
  final CaptureSource source;
  final Confidence confidence;

  /// What was heard or read, kept so a vendor reviewing a correction can see
  /// the original rather than only the parsed result.
  final String? rawText;

  bool get needsReview => confidence.needsReview;

  /// The signed delta this applies to the shelf.
  ///
  /// Deltas, never absolute quantities: two offline devices each recording
  /// part of a day's sales must both count, and deltas commute where absolute
  /// values overwrite each other (TRD 7.2).
  Quantity get delta => Quantity(quantity.amount * kind.sign, quantity.unit);
}
