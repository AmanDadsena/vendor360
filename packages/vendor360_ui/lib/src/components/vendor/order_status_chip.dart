import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import '../feedback/status_mark.dart';

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

    final color = switch (tone) {
      // Marigold: something is owed to the shop and nobody has answered.
      OrderTone.pending => colors.warning,
      OrderTone.active => colors.accent,
      OrderTone.done => colors.inkSubtle,
      OrderTone.cancelled => colors.danger,
      OrderTone.draft => colors.hairline,
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : v360.spacing.sm,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.sm),
        border: Border.all(color: colors.hairline),
      ),
      child: StatusMark(label: label, color: color, icon: icon, dense: dense),
    );
  }
}
