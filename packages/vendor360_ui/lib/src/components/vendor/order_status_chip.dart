import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// How an order's stage should read, independent of what it is called.
///
/// The design system takes a tone rather than an order status because the two
/// sides of the marketplace use different words for the same row — a shop's
/// "waiting" is a wholesaler's "new" — and the package must not know that
/// either vocabulary exists.
enum OrderTone {
  /// Sent, nobody has answered yet.
  pending,

  /// Accepted and moving.
  active,

  /// Arrived.
  done,

  /// Called off by either side.
  cancelled,

  /// Not yet sent.
  draft,
}

/// A compact status pill for an order row.
class OrderStatusChip extends StatelessWidget {
  const OrderStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.dense = false,
    this.icon,
  });

  final String label;
  final OrderTone tone;
  final bool dense;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final (Color fill, Color text) = switch (tone) {
      // Saffron: something is owed to the shop and nobody has answered.
      OrderTone.pending => (colors.voiceSurface, colors.voiceText),
      OrderTone.active => (colors.accentSurface, colors.accentText),
      OrderTone.done => (colors.surfaceMuted, colors.inkMuted),
      OrderTone.cancelled => (colors.dangerSurface, colors.dangerText),
      OrderTone.draft => (colors.surfaceMuted, colors.inkSubtle),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? v360.spacing.sm : v360.spacing.md,
        vertical: dense ? 2 : v360.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: dense ? 11 : 13, color: text),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: v360.text.label.copyWith(
              color: text,
              fontWeight: FontWeight.w700,
              fontSize: dense ? 10 : null,
            ),
          ),
        ],
      ),
    );
  }
}
