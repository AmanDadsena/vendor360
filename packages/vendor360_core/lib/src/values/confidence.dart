/// Extraction confidence for a voice or OCR capture.
///
/// The design guide forbids silently committing a low-confidence transcription
/// or receipt line. Encoding the threshold here — rather than as a magic number
/// at each call site — means every screen asks the same question and gets the
/// same answer, and the rule can be changed in one place.
class Confidence {
  const Confidence(this.value);

  final double value;

  /// Below this, the vendor must confirm before anything is committed.
  static const double reviewThreshold = 0.72;

  static const Confidence certain = Confidence(1.0);

  bool get needsReview => value < reviewThreshold;
  bool get isCertain => value >= 0.999;

  /// Bucketed for the UI, so a pill colour never has to reimplement the bands.
  ConfidenceBand get band {
    if (value >= 0.9) return ConfidenceBand.high;
    if (value >= reviewThreshold) return ConfidenceBand.medium;
    if (value >= 0.5) return ConfidenceBand.low;
    return ConfidenceBand.veryLow;
  }

  String get percentLabel => '${(value * 100).round()}%';

  @override
  bool operator ==(Object other) =>
      other is Confidence && (other.value - value).abs() < 0.0001;

  @override
  int get hashCode => (value * 10000).round().hashCode;
}

enum ConfidenceBand { high, medium, low, veryLow }
