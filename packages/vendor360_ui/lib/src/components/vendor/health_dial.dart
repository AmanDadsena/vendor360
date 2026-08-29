import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// The Health Score dial.
///
/// An arc rather than a full ring, so the empty portion reads as "room to
/// improve" rather than as a loading state that never finishes.
///
/// A provisional score is drawn dashed. That is a deliberate visual claim: the
/// guide requires a thin-history score to be legible as *not yet firm*, and a
/// solid arc with a small caption underneath would be read as a real number by
/// anyone glancing at it — including a lender.
class HealthDial extends StatelessWidget {
  const HealthDial({
    super.key,
    required this.score,
    this.provisional = false,
    this.size = 176,
    this.bandLabel,
  });

  final double score;
  final bool provisional;
  final double size;
  final String? bandLabel;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final tone = switch (score) {
      >= 75 => colors.accent,
      >= 55 => colors.accent,
      >= 35 => colors.warning,
      _ => colors.danger,
    };

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: score.clamp(0, 100)),
      duration: motion.reduced ? Duration.zero : motion.deliberate,
      curve: motion.emphasized,
      builder: (context, value, _) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CustomPaint(
              size: Size.square(size),
              painter: _DialPainter(
                value: value / 100,
                track: colors.hairline,
                tone: provisional ? colors.inkSubtle : tone,
                dashed: provisional,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  value.round().toString(),
                  // Tabular figures keep the number from jittering as it
                  // counts up — the whole reason the type scale sets them.
                  style: v360.text.display.copyWith(
                    fontSize: size * 0.28,
                    height: 1.0,
                    color: colors.ink,
                  ),
                ),
                Text(
                  'out of 100',
                  style: v360.text.caption.copyWith(color: colors.inkSubtle),
                ),
                if (bandLabel != null) ...<Widget>[
                  SizedBox(height: v360.spacing.sm),
                  Text(
                    bandLabel!.toUpperCase(),
                    style: v360.text.label.copyWith(
                      color: provisional ? colors.inkSubtle : tone,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter({
    required this.value,
    required this.track,
    required this.tone,
    required this.dashed,
  });

  final double value;
  final Color track;
  final Color tone;
  final bool dashed;

  // A 270-degree arc opening at the bottom, so the gap reads as a scale with
  // a start and an end rather than as an incomplete circle.
  static const double _start = math.pi * 0.75;
  static const double _sweep = math.pi * 1.5;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = size.width * 0.075;
    final rect = Rect.fromLTWH(
      stroke / 2,
      stroke / 2,
      size.width - stroke,
      size.height - stroke,
    );

    canvas.drawArc(
      rect,
      _start,
      _sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = track,
    );

    if (value <= 0) return;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..color = tone;

    if (!dashed) {
      canvas.drawArc(rect, _start, _sweep * value, false, paint);
      return;
    }

    // Dashes are drawn as short arcs rather than with a path effect, which
    // Flutter's Canvas does not offer for arcs.
    const int segments = 26;
    final filled = (segments * value).floor();
    const segment = _sweep / segments;

    for (var i = 0; i < filled; i++) {
      canvas.drawArc(
        rect,
        _start + i * segment,
        segment * 0.55,
        false,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) =>
      old.value != value || old.tone != tone || old.dashed != dashed;
}

/// One weighted factor behind the score.
///
/// The bar is drawn to the component's own 0-100 value while the trailing text
/// shows its weighted contribution. Showing only the contribution would make
/// waste (max 20 points) look permanently worse than consistency (max 40),
/// which is a weighting artefact rather than anything the vendor did.
class ScoreFactorBar extends StatelessWidget {
  const ScoreFactorBar({
    super.key,
    required this.label,
    required this.value,
    required this.weight,
    required this.contribution,
    required this.detail,
    this.delayIndex = 0,
  });

  final String label;
  final double value;
  final double weight;
  final double contribution;
  final String detail;
  final int delayIndex;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final tone = switch (value) {
      >= 75 => colors.accent,
      >= 45 => colors.warning,
      _ => colors.danger,
    };

    return Padding(
      padding: EdgeInsets.symmetric(vertical: v360.spacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  style: v360.text.bodyStrong.copyWith(color: colors.ink),
                ),
              ),
              Text(
                '${value.round()}',
                style: v360.text.bodyStrong.copyWith(color: tone),
              ),
              Text(
                ' × ${weight.toStringAsFixed(2)} = ${contribution.toStringAsFixed(1)}',
                style: v360.text.caption.copyWith(color: colors.inkSubtle),
              ),
            ],
          ),
          SizedBox(height: v360.spacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: (value / 100).clamp(0, 1)),
              duration: motion.reduced
                  ? Duration.zero
                  : motion.slow + Duration(milliseconds: 60 * delayIndex),
              curve: motion.emphasized,
              builder: (context, t, _) => LinearProgressIndicator(
                value: t,
                minHeight: 8,
                backgroundColor: colors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
          ),
          SizedBox(height: v360.spacing.xs),
          Text(detail, style: v360.text.caption.copyWith(color: colors.inkMuted)),
        ],
      ),
    );
  }
}
