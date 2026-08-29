import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// One day of a forecast, as the chart needs it.
class SparkPoint {
  const SparkPoint({
    required this.label,
    required this.value,
    required this.lower,
    required this.upper,
    this.hasSignal = false,
  });

  final String label;
  final double value;
  final double lower;
  final double upper;

  /// Marks the day as driven by a named festival or weather signal, so it can
  /// be picked out of the line.
  final bool hasSignal;
}

/// A forecast line with its confidence band.
///
/// The band is drawn, not implied. A bare line would claim a precision the
/// model does not have, and a vendor deciding how much dairy to buy needs to
/// see the range rather than a single confident-looking number.
///
/// Days carrying a named driver get a filled marker; everything else is a
/// plain vertex. That is what connects this chart to the sentence above it.
class ForecastSpark extends StatelessWidget {
  const ForecastSpark({
    super.key,
    required this.points,
    this.height = 132,
    this.showLabels = true,
  });

  final List<SparkPoint> points;
  final double height;
  final bool showLabels;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final motion = MotionScope.of(context);

    if (points.isEmpty) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'Not enough history to forecast yet',
            style: v360.text.caption.copyWith(color: v360.colors.inkSubtle),
          ),
        ),
      );
    }

    return Column(
      children: <Widget>[
        SizedBox(
          height: height,
          width: double.infinity,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: motion.reduced ? Duration.zero : motion.deliberate,
            curve: motion.emphasized,
            builder: (context, t, _) => CustomPaint(
              painter: _SparkPainter(
                points: points,
                progress: t,
                line: v360.colors.accent,
                band: v360.colors.accent.withValues(alpha: 0.14),
                signal: v360.colors.voice,
                grid: v360.colors.hairline,
              ),
            ),
          ),
        ),
        if (showLabels) ...<Widget>[
          SizedBox(height: v360.spacing.sm),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              for (final p in points)
                Expanded(
                  child: Text(
                    p.label,
                    textAlign: TextAlign.center,
                    style: v360.text.label.copyWith(
                      color: p.hasSignal
                          ? v360.colors.voiceText
                          : v360.colors.inkSubtle,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.points,
    required this.progress,
    required this.line,
    required this.band,
    required this.signal,
    required this.grid,
  });

  final List<SparkPoint> points;
  final double progress;
  final Color line;
  final Color band;
  final Color signal;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    // Scale to the widest upper bound so the band never clips, and start the
    // axis at zero — a truncated axis exaggerates a modest change into a
    // dramatic one, which on a restocking decision is actively misleading.
    var maxValue = 0.0;
    for (final p in points) {
      if (p.upper > maxValue) maxValue = p.upper;
    }
    if (maxValue <= 0) maxValue = 1;

    final stepX = points.length == 1 ? 0.0 : size.width / (points.length - 1);
    double x(int i) => points.length == 1 ? size.width / 2 : i * stepX;
    double y(double v) => size.height - (v / maxValue) * size.height * 0.88;

    // Baseline.
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = grid
        ..strokeWidth = 1,
    );

    final shown = (points.length * progress).ceil().clamp(1, points.length);

    // Confidence band.
    if (shown > 1) {
      final area = Path()..moveTo(x(0), y(points[0].upper));
      for (var i = 1; i < shown; i++) {
        area.lineTo(x(i), y(points[i].upper));
      }
      for (var i = shown - 1; i >= 0; i--) {
        area.lineTo(x(i), y(points[i].lower));
      }
      area.close();
      canvas.drawPath(area, Paint()..color = band);
    }

    // Predicted line.
    final path = Path()..moveTo(x(0), y(points[0].value));
    for (var i = 1; i < shown; i++) {
      path.lineTo(x(i), y(points[i].value));
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = line,
    );

    // Markers. Signal days are filled in saffron and drawn larger, so the day
    // the recommendation refers to is findable at a glance.
    for (var i = 0; i < shown; i++) {
      final point = points[i];
      final centre = Offset(x(i), y(point.value));
      if (point.hasSignal) {
        canvas.drawCircle(centre, 5.5, Paint()..color = signal);
        canvas.drawCircle(
          centre,
          5.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white.withValues(alpha: 0.85),
        );
      } else {
        canvas.drawCircle(centre, 3, Paint()..color = line);
      }
    }
  }

  @override
  bool shouldRepaint(_SparkPainter old) =>
      old.progress != progress || old.points != points || old.line != line;
}
