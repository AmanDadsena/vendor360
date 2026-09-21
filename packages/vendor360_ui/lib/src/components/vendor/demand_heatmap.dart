import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_colors.dart';
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

/// Hyperlocal demand intensity, drawn like a printed district map.
///
/// Drawn on a canvas rather than over map tiles, deliberately: the app is
/// offline-first, and a heatmap that renders as grey squares whenever the
/// network is down would be worse than no heatmap. Everything here is computed
/// from the returned coordinates, so it looks identical on a 2G connection and
/// in airplane mode.
///
/// Each cell is a flat disc sized by demand and filled from a five-step ramp,
/// the way a printed map shows quantities at places. It used to be glowing
/// radial blobs added together on a near-black ground with neon markers —
/// the look of every generated analytics screen, and harder to read: two
/// adjacent glows summed into a hot spot that neither cell had. A disc says
/// "about this much, about here", which is exactly what a privacy-sized
/// aggregate can honestly claim.
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
              Icon(Icons.map_outlined, size: 28, color: colors.inkSubtle),
              SizedBox(height: v360.spacing.md),
              Text(
                'No demand data for this filter',
                style: v360.text.bodyStrong.copyWith(color: colors.ink),
              ),
              SizedBox(height: v360.spacing.xs),
              Text(
                'Cells appear once at least three nearby stores contribute, '
                'so no single shop can be identified.',
                textAlign: TextAlign.center,
                style: v360.text.caption.copyWith(color: colors.inkMuted),
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
          child: Container(
            height: height,
            width: size.width,
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V360Radius.lg),
              border: Border.all(color: colors.hairline),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(V360Radius.lg),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: motion.reduced ? Duration.zero : motion.base,
                curve: motion.decelerate,
                builder: (context, t, _) => CustomPaint(
                  size: size,
                  painter: _HeatPainter(
                    cells: cells,
                    suppliers:
                        showSuppliers ? suppliers : const <SupplierPin>[],
                    bounds: bounds,
                    progress: t,
                    ramp: V360Colors.heatRamp,
                    grid: colors.hairline,
                    paper: colors.surface,
                    ink: colors.ink,
                    shortage: colors.danger,
                    labelStyle: v360.text.label
                        .copyWith(color: colors.ink)
                        .weight(FontWeight.w600),
                    pinStyle: v360.text.label
                        .copyWith(color: colors.ink)
                        .weight(FontWeight.w700),
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
    required this.ramp,
    required this.grid,
    required this.paper,
    required this.ink,
    required this.shortage,
    required this.labelStyle,
    required this.pinStyle,
  });

  final List<HeatCell> cells;
  final List<SupplierPin> suppliers;
  final _Bounds bounds;
  final double progress;
  final List<Color> ramp;
  final Color grid;
  final Color paper;
  final Color ink;
  final Color shortage;
  final TextStyle labelStyle;
  final TextStyle pinStyle;

  /// Stepped, not blended: a printed map shows five classes, and a
  /// continuous blend makes neighbouring values look like different things.
  Color _step(double t) {
    final i = (t.clamp(0.0, 0.9999) * ramp.length).floor();
    return ramp[i];
  }

  @override
  void paint(Canvas canvas, Size size) {
    _paintGrid(canvas, size);

    // Radius scales with the canvas so the map reads the same on a phone and
    // on a tablet, and with the square root of intensity so a disc's *area*
    // tracks demand — twice the demand is twice the ink, not four times.
    final maxRadius = math.min(size.width, size.height) * 0.09;

    // Biggest first, so a small cell is never buried under a large one.
    final ordered = <HeatCell>[...cells]
      ..sort((a, b) => b.intensity.compareTo(a.intensity));

    for (final cell in ordered) {
      final centre = bounds.project(cell.lat, cell.lon, size);
      final radius =
          maxRadius * (0.32 + 0.68 * math.sqrt(cell.intensity)) * progress;
      if (radius <= 0.5) continue;

      canvas.drawCircle(
        centre,
        radius,
        Paint()..color = _step(cell.intensity).withValues(alpha: 0.92),
      );
      // A paper keyline, so overlapping discs stay separate shapes.
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = paper,
      );

      // Shortage: a dashed ring marking cells where restocking pressure is
      // building even if sales have not spiked yet.
      if (cell.shortageCount > 0 && progress > 0.5) {
        const segments = 18;
        for (var i = 0; i < segments; i += 2) {
          final start = (i / segments) * 2 * math.pi;
          canvas.drawArc(
            Rect.fromCircle(center: centre, radius: radius + 5),
            start,
            (2 * math.pi / segments) * 0.9,
            false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2
              ..color = shortage,
          );
        }
      }
    }

    for (final pin in suppliers) {
      _paintSupplier(canvas, size, pin);
    }

    // Labels last, and only where they fit: suppliers first (they are the
    // places you can call), then the busiest cells' top item. A label that
    // would land on another is left off rather than printed over it — a
    // printed map chooses which names to set; it never stacks them.
    if (progress > 0.9) {
      // Pins are reserved first, so no label is ever printed over one.
      final placed = <Rect>[
        for (final pin in suppliers)
          Rect.fromCenter(
            center: bounds.project(pin.lat, pin.lon, size),
            width: 18,
            height: 18,
          ),
      ];
      for (final pin in suppliers) {
        final at = bounds.project(pin.lat, pin.lon, size);
        // Above the pin if there is room, otherwise below it.
        // Clear of the pin's own reserved box either way.
        if (!_paintLabel(canvas, size, pin.name, Offset(at.dx, at.dy - 31),
            pinStyle, placed)) {
          _paintLabel(canvas, size, pin.name, Offset(at.dx, at.dy + 14),
              pinStyle, placed);
        }
      }
      for (final cell in ordered) {
        if (cell.topSku == null) continue;
        final centre = bounds.project(cell.lat, cell.lon, size);
        final radius = maxRadius * (0.32 + 0.68 * math.sqrt(cell.intensity));
        _paintLabel(canvas, size, cell.topSku!,
            Offset(centre.dx, centre.dy + radius + 3), labelStyle, placed);
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = grid
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

  void _paintSupplier(Canvas canvas, Size size, SupplierPin pin) {
    final at = bounds.project(pin.lat, pin.lon, size);
    final isMandi = pin.kind == 'mandi';

    // Shape, not colour, separates the layers: demand is a disc, a
    // distributor an ink square, a mandi an ink diamond.
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (isMandi) canvas.rotate(math.pi / 4);
    final rect = Rect.fromCenter(center: Offset.zero, width: 11, height: 11);
    canvas.drawRect(rect.inflate(1.5), Paint()..color = paper);
    canvas.drawRect(rect, Paint()..color = ink.withValues(alpha: progress));
    canvas.restore();
  }

  /// Paints [text] at [at] unless it would land on something already set.
  /// Returns whether it was painted.
  bool _paintLabel(
    Canvas canvas,
    Size size,
    String text,
    Offset at,
    TextStyle style,
    List<Rect> placed,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 120);

    final origin = Offset(
      (at.dx - painter.width / 2).clamp(4, size.width - painter.width - 4),
      at.dy.clamp(2, size.height - painter.height - 2),
    );
    final box = Rect.fromLTWH(
      origin.dx - 4,
      origin.dy - 1,
      painter.width + 8,
      painter.height + 2,
    );
    if (placed.any((r) => r.overlaps(box.inflate(2)))) return false;
    placed.add(box);

    // A paper plate behind the label, like a printed map's label knock-out,
    // so text stays readable over a disc.
    canvas.drawRRect(
      RRect.fromRectAndRadius(box, const Radius.circular(2)),
      Paint()..color = paper.withValues(alpha: 0.92),
    );

    painter.paint(canvas, origin);
    return true;
  }

  @override
  bool shouldRepaint(_HeatPainter old) =>
      old.progress != progress ||
      old.cells != cells ||
      old.suppliers != suppliers ||
      old.paper != paper;
}

/// Key for the heatmap's steps and marker shapes.
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
            Text('Low', style: v360.text.label.copyWith(color: colors.inkMuted)),
            SizedBox(width: v360.spacing.sm),
            // Five printed swatches, one per step, rather than a gradient bar:
            // the map draws steps, so the key shows steps.
            for (final swatch in V360Colors.heatRamp) ...<Widget>[
              Container(width: 22, height: 12, color: swatch),
              const SizedBox(width: 2),
            ],
            SizedBox(width: v360.spacing.sm - 2),
            Text('High', style: v360.text.label.copyWith(color: colors.inkMuted)),
          ],
        ),
        if (showSuppliers) ...<Widget>[
          SizedBox(height: v360.spacing.md),
          Wrap(
            spacing: v360.spacing.lg,
            runSpacing: v360.spacing.sm,
            children: <Widget>[
              _LegendKey(colour: colors.ink, label: 'Distributor', square: true),
              _LegendKey(colour: colors.ink, label: 'Mandi', diamond: true),
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
    this.diamond = false,
    this.ring = false,
  });

  final Color colour;
  final String label;
  final bool square;
  final bool diamond;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    Widget mark = ring
        // Dashed, because the map draws restock pressure as a dashed ring.
        ? CustomPaint(
            size: const Size(12, 12),
            painter: _DashedRingPainter(colour),
          )
        : Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colour,
              shape: square || diamond ? BoxShape.rectangle : BoxShape.circle,
            ),
          );
    if (diamond) mark = Transform.rotate(angle: math.pi / 4, child: mark);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SizedBox(width: 14, height: 14, child: Center(child: mark)),
        SizedBox(width: v360.spacing.xs),
        Text(
          label,
          style: v360.text.caption.copyWith(color: v360.colors.inkMuted),
        ),
      ],
    );
  }
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    const segments = 10;
    final rect = Offset.zero & size;
    for (var i = 0; i < segments; i += 2) {
      canvas.drawArc(
        rect.deflate(1),
        (i / segments) * 2 * math.pi,
        (2 * math.pi / segments) * 0.9,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = colour,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.colour != colour;
}
