import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// One aggregated demand cell.
class HeatCell {
  const HeatCell({
    required this.lat,
    required this.lon,
    required this.intensity,
    required this.demandQty,
    required this.vendorCount,
    this.topSku,
    this.shortageCount = 0,
  });

  final double lat;
  final double lon;

  /// 0-1, normalised across the visible set.
  final double intensity;

  final double demandQty;
  final int vendorCount;
  final String? topSku;

  /// Vendors in this cell currently below their reorder point — where
  /// restocking pressure is building, as distinct from where sales already
  /// happened.
  final int shortageCount;
}

/// A supplier or mandi.
class SupplierPin {
  const SupplierPin({
    required this.name,
    required this.lat,
    required this.lon,
    required this.kind,
    this.leadDays = 2,
  });

  final String name;
  final double lat;
  final double lon;

  /// `mandi` or `distributor`.
  final String kind;
  final int leadDays;
}

/// Hyperlocal demand intensity.
///
/// Drawn on a canvas rather than over map tiles, deliberately: the app is
/// offline-first, and a heatmap that renders as grey squares whenever the
/// network is down would be worse than no heatmap. Everything here is computed
/// from the returned coordinates, so it looks identical on a 2G connection and
/// in airplane mode.
///
/// Cells are painted as radial falloffs and composited additively, so
/// neighbouring cells bleed into one another the way a real heat surface does.
/// A grid of hard squares would imply the underlying geography is quantised,
/// when the cell size is only a privacy artefact.
class DemandHeatmap extends StatelessWidget {
  const DemandHeatmap({
    super.key,
    required this.cells,
    this.suppliers = const <SupplierPin>[],
    this.height = 320,
    this.showSuppliers = true,
    this.onCellTap,
  });

  final List<HeatCell> cells;
  final List<SupplierPin> suppliers;
  final double height;
  final bool showSuppliers;
  final void Function(HeatCell cell)? onCellTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    if (cells.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(V360Radius.lg),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: EdgeInsets.all(v360.spacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.map_outlined, size: 32, color: colors.inkSubtle),
              SizedBox(height: v360.spacing.md),
              Text(
                'No demand data for this filter',
                style: v360.text.bodyStrong.copyWith(color: colors.inkMuted),
              ),
              SizedBox(height: v360.spacing.xs),
              Text(
                'Cells appear once at least three nearby stores contribute, '
                'so no single shop can be identified.',
                textAlign: TextAlign.center,
                style: v360.text.caption.copyWith(color: colors.inkSubtle),
              ),
            ],
          ),
        ),
      );
    }

    final bounds = _Bounds.from(cells, showSuppliers ? suppliers : const []);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, height);

        return GestureDetector(
          onTapUp: onCellTap == null
              ? null
              : (details) {
                  final hit = _hitTest(details.localPosition, size, bounds);
                  if (hit != null) onCellTap!(hit);
                },
          child: ClipRRect(
            borderRadius: BorderRadius.circular(V360Radius.lg),
            child: Container(
              height: height,
              width: size.width,
              color: v360.isDark ? colors.surfaceMuted : const Color(0xFF0E1B18),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: motion.reduced ? Duration.zero : motion.deliberate,
                curve: motion.emphasized,
                builder: (context, t, _) => CustomPaint(
                  size: size,
                  painter: _HeatPainter(
                    cells: cells,
                    suppliers: showSuppliers ? suppliers : const <SupplierPin>[],
                    bounds: bounds,
                    progress: t,
                    labelStyle: v360.text.label.copyWith(
                      color: Colors.white.withValues(alpha: 0.75),
                    ),
                    pinStyle: v360.text.label.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  HeatCell? _hitTest(Offset point, Size size, _Bounds bounds) {
    HeatCell? best;
    var bestDistance = double.infinity;

    for (final cell in cells) {
      final centre = bounds.project(cell.lat, cell.lon, size);
      final distance = (centre - point).distance;
      if (distance < 44 && distance < bestDistance) {
        best = cell;
        bestDistance = distance;
      }
    }
    return best;
  }
}

/// Geographic extent of the plotted set, with padding so nothing sits on the
/// edge of the canvas.
class _Bounds {
  _Bounds(this.minLat, this.maxLat, this.minLon, this.maxLon);

  final double minLat, maxLat, minLon, maxLon;

  factory _Bounds.from(List<HeatCell> cells, List<SupplierPin> pins) {
    var minLat = double.infinity, maxLat = -double.infinity;
    var minLon = double.infinity, maxLon = -double.infinity;

    void include(double lat, double lon) {
      minLat = math.min(minLat, lat);
      maxLat = math.max(maxLat, lat);
      minLon = math.min(minLon, lon);
      maxLon = math.max(maxLon, lon);
    }

    for (final c in cells) {
      include(c.lat, c.lon);
    }
    for (final p in pins) {
      include(p.lat, p.lon);
    }

    // A single point has zero extent and would divide by zero; give it a
    // nominal window so it lands in the middle.
    final latPad = math.max((maxLat - minLat) * 0.18, 0.004);
    final lonPad = math.max((maxLon - minLon) * 0.18, 0.004);

    return _Bounds(
      minLat - latPad,
      maxLat + latPad,
      minLon - lonPad,
      maxLon + lonPad,
    );
  }

  Offset project(double lat, double lon, Size size) {
    final x = (lon - minLon) / (maxLon - minLon) * size.width;
    // Latitude increases northward but screen y increases downward.
    final y = size.height - (lat - minLat) / (maxLat - minLat) * size.height;
    return Offset(x, y);
  }
}

class _HeatPainter extends CustomPainter {
  _HeatPainter({
    required this.cells,
    required this.suppliers,
    required this.bounds,
    required this.progress,
    required this.labelStyle,
    required this.pinStyle,
  });

  final List<HeatCell> cells;
  final List<SupplierPin> suppliers;
  final _Bounds bounds;
  final double progress;
  final TextStyle labelStyle;
  final TextStyle pinStyle;

  /// Cool-to-hot ramp. Teal through saffron to red, so it stays inside the
  /// product palette instead of importing a generic rainbow — and because a
  /// rainbow ramp misleads by making mid-values look like a distinct category.
  static const List<Color> _ramp = <Color>[
    Color(0xFF0F7A6B),
    Color(0xFF3FA98C),
    Color(0xFFA8C34F),
    Color(0xFFD98A0F),
    Color(0xFFE85D4C),
  ];

  Color _rampColor(double t) {
    final clamped = t.clamp(0.0, 1.0);
    final scaled = clamped * (_ramp.length - 1);
    final index = scaled.floor().clamp(0, _ramp.length - 2);
    return Color.lerp(_ramp[index], _ramp[index + 1], scaled - index)!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    // Radius scales with the canvas so the surface looks the same on a phone
    // and on a tablet.
    final baseRadius = math.min(size.width, size.height) * 0.22;

    // Additive blending, so overlapping cells brighten rather than the later
    // one simply covering the earlier — that additive build is what makes a
    // heat surface read as continuous.
    canvas.saveLayer(Offset.zero & size, Paint()..blendMode = BlendMode.plus);

    for (final cell in cells) {
      final centre = bounds.project(cell.lat, cell.lon, size);
      final intensity = cell.intensity * progress;
      if (intensity <= 0.01) continue;

      final radius = baseRadius * (0.55 + 0.45 * cell.intensity);
      final colour = _rampColor(cell.intensity);

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = ui.Gradient.radial(
            centre,
            radius,
            <Color>[
              colour.withValues(alpha: 0.85 * intensity),
              colour.withValues(alpha: 0.35 * intensity),
              colour.withValues(alpha: 0.0),
            ],
            <double>[0.0, 0.45, 1.0],
          ),
      );
    }

    canvas.restore();

    for (final cell in cells) {
      _paintCellMarker(canvas, size, cell);
    }

    for (final pin in suppliers) {
      _paintSupplier(canvas, size, pin);
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.05)
      ..strokeWidth = 1;

    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (var i = 1; i < 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintCellMarker(Canvas canvas, Size size, HeatCell cell) {
    final centre = bounds.project(cell.lat, cell.lon, size);

    canvas.drawCircle(
      centre,
      5,
      Paint()..color = Colors.white.withValues(alpha: 0.9 * progress),
    );
    canvas.drawCircle(
      centre,
      5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.black.withValues(alpha: 0.35 * progress),
    );

    // Shortage ring: a dashed halo marking cells where restocking pressure is
    // building even if sales have not spiked yet.
    if (cell.shortageCount > 0) {
      const segments = 16;
      for (var i = 0; i < segments; i += 2) {
        final start = (i / segments) * 2 * math.pi;
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: 13),
          start,
          (2 * math.pi / segments) * 0.9,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFFE85D4C).withValues(alpha: 0.9 * progress),
        );
      }
    }

    if (cell.topSku != null && progress > 0.75) {
      _paintText(
        canvas,
        cell.topSku!,
        Offset(centre.dx, centre.dy + 12),
        labelStyle,
        centred: true,
      );
    }
  }

  void _paintSupplier(Canvas canvas, Size size, SupplierPin pin) {
    final at = bounds.project(pin.lat, pin.lon, size);
    final isMandi = pin.kind == 'mandi';

    // Suppliers are squares, demand cells are circles. Shape, not just colour,
    // separates the two layers — the same colour-blindness rule the pills follow.
    final rect = Rect.fromCenter(center: at, width: 13, height: 13);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..color = (isMandi ? const Color(0xFF8B5CF6) : const Color(0xFF38BDF8))
            .withValues(alpha: progress),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.white.withValues(alpha: 0.85 * progress),
    );

    if (progress > 0.8) {
      _paintText(
        canvas,
        pin.name,
        Offset(at.dx, at.dy - 22),
        pinStyle,
        centred: true,
      );
    }
  }

  void _paintText(
    Canvas canvas,
    String text,
    Offset at,
    TextStyle style, {
    bool centred = false,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);

    final origin = centred
        ? Offset(at.dx - painter.width / 2, at.dy)
        : at;

    // A dark plate behind the label, so text stays readable over a bright
    // patch of the heat surface.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx - 4,
          origin.dy - 2,
          painter.width + 8,
          painter.height + 4,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.black.withValues(alpha: 0.45 * progress),
    );

    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.progress != progress ||
      old.cells != cells ||
      old.suppliers != suppliers;
}

/// Key for the heatmap's colour ramp and marker shapes.
class HeatmapLegend extends StatelessWidget {
  const HeatmapLegend({super.key, this.showSuppliers = true});

  final bool showSuppliers;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text('Low', style: v360.text.label.copyWith(color: colors.inkSubtle)),
            SizedBox(width: v360.spacing.sm),
            Expanded(
              child: Container(
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  gradient: const LinearGradient(
                    colors: <Color>[
                      Color(0xFF0F7A6B),
                      Color(0xFF3FA98C),
                      Color(0xFFA8C34F),
                      Color(0xFFD98A0F),
                      Color(0xFFE85D4C),
                    ],
                  ),
                ),
              ),
            ),
            SizedBox(width: v360.spacing.sm),
            Text('High', style: v360.text.label.copyWith(color: colors.inkSubtle)),
          ],
        ),
        if (showSuppliers) ...<Widget>[
          SizedBox(height: v360.spacing.md),
          Wrap(
            spacing: v360.spacing.lg,
            runSpacing: v360.spacing.sm,
            children: <Widget>[
              const _LegendKey(
                colour: Color(0xFF38BDF8),
                label: 'Distributor',
                square: true,
              ),
              const _LegendKey(
                colour: Color(0xFF8B5CF6),
                label: 'Mandi',
                square: true,
              ),
              _LegendKey(
                colour: colors.danger,
                label: 'Restock pressure',
                ring: true,
              ),
            ],
          ),
        ],
      ],
    );
  }
}

class _LegendKey extends StatelessWidget {
  const _LegendKey({
    required this.colour,
    required this.label,
    this.square = false,
    this.ring = false,
  });

  final Color colour;
  final String label;
  final bool square;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(
            color: ring ? null : colour,
            border: ring ? Border.all(color: colour, width: 2) : null,
            shape: square ? BoxShape.rectangle : BoxShape.circle,
            borderRadius: square ? BorderRadius.circular(3) : null,
          ),
        ),
        SizedBox(width: v360.spacing.xs),
        Text(
          label,
          style: v360.text.caption.copyWith(color: v360.colors.inkMuted),
        ),
      ],
    );
  }
}
