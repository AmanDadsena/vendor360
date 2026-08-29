/// The micro-credit Health Score and its breakdown.
///
/// The breakdown is required, not optional: the UI/UX guide states the score
/// must never read as an opaque judgment, since it influences whether a vendor
/// can borrow. Modelling components as a non-nullable list means a screen
/// cannot render the number without having the reasons to hand.
class HealthScore {
  const HealthScore({
    required this.score,
    required this.band,
    required this.provisional,
    required this.daysOfHistory,
    required this.components,
    required this.explanation,
  });

  final double score;
  final ScoreBand band;

  /// True when history is too thin for a firm number. Displayed prominently:
  /// a provisional score shown as if it were final would mislead both the
  /// vendor and any lender they share it with (TC-H02).
  final bool provisional;

  final int daysOfHistory;
  final List<ScoreComponent> components;
  final String explanation;

  ScoreComponent get strongest =>
      components.reduce((a, b) => a.value >= b.value ? a : b);

  ScoreComponent get weakest =>
      components.reduce((a, b) => a.value <= b.value ? a : b);

  /// True when every component is near the ceiling, so naming a "weakest"
  /// would be misleading rather than helpful.
  bool get isUniformlyStrong => weakest.value >= 95;
}

enum ScoreBand { strong, stable, building, atRisk, provisional }

ScoreBand scoreBandFrom(String raw) => switch (raw) {
      'strong' => ScoreBand.strong,
      'stable' => ScoreBand.stable,
      'building' => ScoreBand.building,
      'at_risk' => ScoreBand.atRisk,
      _ => ScoreBand.provisional,
    };

extension ScoreBandX on ScoreBand {
  String get label => switch (this) {
        ScoreBand.strong => 'Strong',
        ScoreBand.stable => 'Stable',
        ScoreBand.building => 'Building',
        ScoreBand.atRisk => 'Needs attention',
        ScoreBand.provisional => 'Provisional',
      };
}

class ScoreComponent {
  const ScoreComponent({
    required this.key,
    required this.label,
    required this.value,
    required this.weight,
    required this.contribution,
    required this.detail,
  });

  final String key;
  final String label;

  /// 0-100 for this behaviour on its own.
  final double value;

  /// How much this behaviour counts toward the composite.
  final double weight;

  /// value * weight — shown so the arithmetic is checkable by the vendor.
  final double contribution;

  /// Plain-language evidence, e.g. "active 84/90 days, avg gap 1.1d".
  final String detail;
}

/// A lender's permission to see one vendor's score.
///
/// Absence of a grant means no access. Consent is modelled explicitly because
/// the PRD names data-sharing hesitancy as a risk, and the mitigation is that
/// the vendor sees the score before anyone else can (TC-H03).
class ScoreConsent {
  const ScoreConsent({
    required this.lenderId,
    required this.lenderName,
    required this.lenderKind,
    required this.granted,
    this.grantedAt,
  });

  final String lenderId;
  final String lenderName;
  final String lenderKind;
  final bool granted;
  final DateTime? grantedAt;
}
