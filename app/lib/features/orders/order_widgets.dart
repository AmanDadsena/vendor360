import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';

/// Shared order presentation, used by both shells.
///
/// The two sides read the same rows differently — a shop's "waiting" is a
/// wholesaler's "new" — so the vocabulary is a parameter rather than baked in,
/// and everything else is common.

/// Maps a status to the design system's tone vocabulary.
OrderTone toneFor(OrderStatus status) => switch (status) {
      OrderStatus.draft => OrderTone.draft,
      OrderStatus.placed => OrderTone.pending,
      OrderStatus.confirmed || OrderStatus.dispatched => OrderTone.active,
      OrderStatus.delivered => OrderTone.done,
      OrderStatus.cancelled => OrderTone.cancelled,
    };

/// A short, human date. "Today" and "Tomorrow" beat a numeral for the two
/// cases a shopkeeper actually cares about.
String shortDate(DateTime? when) {
  if (when == null) return '—';
  final now = DateTime.now();
  final day = DateTime(when.year, when.month, when.day);
  final today = DateTime(now.year, now.month, now.day);
  final delta = day.difference(today).inDays;

  return switch (delta) {
    0 => 'today',
    1 => 'tomorrow',
    -1 => 'yesterday',
    _ when delta < 0 && delta > -7 => '${-delta} days ago',
    _ when delta > 0 && delta < 7 => 'in $delta days',
    _ => '${when.day}/${when.month}',
  };
}

String shortTime(DateTime when) {
  final h = when.hour % 12 == 0 ? 12 : when.hour % 12;
  final m = when.minute.toString().padLeft(2, '0');
  return '$h:$m ${when.hour < 12 ? 'am' : 'pm'}';
}

/// One order in a list.
class OrderCard extends StatelessWidget {
  const OrderCard({
    super.key,
    required this.order,
    required this.onTap,
    this.distributorView = false,
  });

  final PurchaseOrder order;
  final VoidCallback onTap;

  /// Switches the vocabulary and shows the shop rather than the wholesaler.
  final bool distributorView;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  distributorView ? order.vendorName : order.supplierName,
                  style: v360.text.titleS.copyWith(color: colors.ink),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: v360.spacing.sm),
              OrderStatusChip(
                label: distributorView
                    ? order.status.distributorLabel
                    : order.status.vendorLabel,
                tone: toneFor(order.status),
              ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            '${order.code} · ${order.lineCount} '
            '${order.lineCount == 1 ? 'item' : 'items'}'
            '${order.isPool ? ' · group order' : ''}',
            style: v360.text.caption.copyWith(color: colors.inkSubtle),
          ),

          SizedBox(height: v360.spacing.md),

          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(child: _timing(context)),
              Text(
                order.total.display,
                style: v360.text.titleS.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),

          if (order.hasShortfall) ...<Widget>[
            SizedBox(height: v360.spacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.info_outline_rounded,
                    size: 14, color: colors.warningText),
                SizedBox(width: v360.spacing.xs),
                Expanded(
                  child: Text(
                    distributorView
                        ? 'You could not fill this in full'
                        : 'Part-filled — some items short',
                    style:
                        v360.text.label.copyWith(color: colors.warningText),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timing(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final (String text, Color tint) = switch (order.status) {
      OrderStatus.draft => ('Not sent yet', colors.inkSubtle),
      OrderStatus.cancelled => ('Cancelled', colors.inkSubtle),
      OrderStatus.delivered => (
          'Received ${shortDate(order.deliveredAt)}',
          colors.inkMuted,
        ),
      _ when order.isLate => (
          'Was due ${shortDate(order.expectedAt)}',
          colors.dangerText,
        ),
      _ => ('Due ${shortDate(order.expectedAt)}', colors.inkMuted),
    };

    return Row(
      children: <Widget>[
        Icon(
          order.isLate
              ? Icons.warning_amber_rounded
              : Icons.schedule_rounded,
          size: 14,
          color: tint,
        ),
        SizedBox(width: v360.spacing.xs),
        Flexible(
          child: Text(
            text,
            style: v360.text.caption.copyWith(color: tint),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

/// One SKU on an order, with all three quantities where they differ.
class OrderLineRow extends StatelessWidget {
  const OrderLineRow({super.key, required this.line, this.trailing});

  final OrderLine line;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: v360.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.skuName,
                  style: v360.text.bodyStrong.copyWith(color: colors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  line.plan.packDisplay,
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
                // Only shown when they diverge. A line that arrived as ordered
                // needs no explanation, and printing "ordered 4, got 4" on
                // every row would bury the ones that did not.
                if (line.isShort) ...<Widget>[
                  SizedBox(height: v360.spacing.xs),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: v360.spacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colors.warningSurface,
                      borderRadius: BorderRadius.circular(V360Radius.pill),
                    ),
                    child: Text(
                      '${_n(line.shortBy)} '
                      '${line.shortBy == 1 ? 'case' : 'cases'} short of the '
                      '${_n(line.packsOrdered)} ordered',
                      style:
                          v360.text.label.copyWith(color: colors.warningText),
                    ),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: v360.spacing.md),
          trailing ??
              Text(
                line.total.display,
                style: v360.text.body.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

/// Money owed, for either side of the relationship.
class LedgerSheet extends ConsumerWidget {
  const LedgerSheet({super.key, this.distributorView = false});

  final bool distributorView;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final ledger =
        ref.watch(distributorView ? distLedgerProvider : ledgerProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        child: ledger.when(
          loading: () => Padding(
            padding: EdgeInsets.all(v360.spacing.gutter),
            child: const V360Skeleton(height: 160),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the ledger',
            body: '$error',
          ),
          data: (data) => ListView(
            controller: controller,
            padding: EdgeInsets.all(v360.spacing.gutter),
            children: <Widget>[
              Text(
                distributorView ? 'Money owed to you' : 'Money you owe',
                style: v360.text.titleM.copyWith(color: colors.ink),
              ),
              SizedBox(height: v360.spacing.lg),
              Row(
                children: <Widget>[
                  Expanded(
                    child: StatTile(
                      label: 'Outstanding',
                      value: data.outstandingMoney.display,
                      compact: true,
                    ),
                  ),
                  SizedBox(width: v360.spacing.md),
                  Expanded(
                    child: StatTile(
                      label: 'Overdue',
                      value: data.overdueMoney.display,
                      tone: data.overdue > 0 ? colors.dangerText : null,
                      compact: true,
                    ),
                  ),
                ],
              ),
              SizedBox(height: v360.spacing.lg),
              if (data.entries.isEmpty)
                EmptyState(
                  icon: Icons.check_circle_outline_rounded,
                  title: 'Nothing outstanding',
                  body: distributorView
                      ? 'Every delivery has been settled.'
                      : 'You are all paid up.',
                )
              else
                for (final entry in data.entries)
                  _LedgerRow(entry: entry),
            ],
          ),
        ),
      ),
    );
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({required this.entry});

  final LedgerLine entry;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: v360.spacing.sm),
      child: Row(
        children: <Widget>[
          Icon(
            entry.isPayment
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            size: 16,
            color: entry.isPayment ? colors.accentText : colors.inkMuted,
          ),
          SizedBox(width: v360.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  entry.counterparty,
                  style: v360.text.body.copyWith(color: colors.ink),
                ),
                Text(
                  <String>[
                    if (entry.orderCode != null) entry.orderCode!,
                    if (entry.dueOn != null && !entry.isPayment)
                      entry.overdue
                          ? 'overdue ${shortDate(entry.dueOn)}'
                          : 'due ${shortDate(entry.dueOn)}',
                    if (entry.isPayment) 'paid ${shortDate(entry.createdAt)}',
                  ].join(' · '),
                  style: v360.text.label.copyWith(
                    color: entry.overdue ? colors.dangerText : colors.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${entry.isPayment ? '−' : ''}${entry.money.display}',
            style: v360.text.bodyStrong.copyWith(
              color: entry.isPayment ? colors.accentText : colors.ink,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
