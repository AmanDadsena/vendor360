import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/order_widgets.dart';

/// Answering one order.
///
/// The part-fill control is the point of this screen. A wholesaler who is
/// short of stock can commit to less than was asked, and saying so here —
/// while the shop can still source the rest elsewhere — is the honest move.
/// It also costs them: the difference feeds the fill rate that ranks them on
/// every future sourcing screen, which is exactly the incentive that should
/// exist.
class DistOrderDetailScreen extends ConsumerStatefulWidget {
  const DistOrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  ConsumerState<DistOrderDetailScreen> createState() =>
      _DistOrderDetailScreenState();
}

class _DistOrderDetailScreenState
    extends ConsumerState<DistOrderDetailScreen> {
  final Map<String, double> _amended = <String, double>{};
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final order = ref.watch(distOrderProvider(widget.orderId));

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/dist/orders'),
        ),
        title: Text(
          order.value?.code ?? 'Order',
          style: v360.text.titleM.copyWith(color: colors.ink),
        ),
      ),
      body: SafeArea(
        child: order.when(
          loading: () => Padding(
            padding: EdgeInsets.all(v360.spacing.gutter),
            child: const V360Skeleton(height: 320),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load this order',
            body: '$error',
          ),
          data: _body,
        ),
      ),
    );
  }

  Widget _body(PurchaseOrder order) {
    final v360 = context.v360;
    final colors = v360.colors;
    final editing = order.status == OrderStatus.placed;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              v360.spacing.gutter,
              0,
              v360.spacing.gutter,
              v360.spacing.lg,
            ),
            children: <Widget>[
              V360Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            order.vendorName,
                            style:
                                v360.text.titleM.copyWith(color: colors.ink),
                          ),
                        ),
                        OrderStatusChip(
                          label: order.status.distributorLabel,
                          tone: toneFor(order.status),
                        ),
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Placed ${shortDate(order.placedAt)} · '
                      '${order.paymentTermsDays == 0 ? 'cash on delivery' : '${order.paymentTermsDays}-day terms'}',
                      style:
                          v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                    if (order.note != null) ...<Widget>[
                      SizedBox(height: v360.spacing.md),
                      Container(
                        width: double.infinity,
                        padding: EdgeInsets.all(v360.spacing.md),
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(V360Radius.md),
                        ),
                        child: Text(
                          '“${order.note}”',
                          style: v360.text.caption
                              .copyWith(color: colors.inkMuted),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              SizedBox(height: v360.spacing.lg),
              SectionLabel(editing ? 'What you can supply' : 'Items'),
              if (editing)
                Padding(
                  padding: EdgeInsets.only(top: v360.spacing.xs),
                  child: Text(
                    'Short of something? Lower the count — they will see it '
                    'now, while they can still source the rest.',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ),
              SizedBox(height: v360.spacing.sm),
              V360Card(
                child: Column(
                  children: <Widget>[
                    for (final line in order.lines)
                      OrderLineRow(
                        line: line,
                        trailing: editing
                            ? PackStepper(
                                dense: true,
                                packs: (_amended[line.id] ?? line.packsOrdered)
                                    .round(),
                                packSize: line.packSize,
                                unit: line.unit,
                                minPacks: 0,
                                maxPacks: line.packsOrdered.round(),
                                onChanged: (packs) => setState(
                                  () => _amended[line.id] = packs.toDouble(),
                                ),
                              )
                            : null,
                      ),
                  ],
                ),
              ),

              SizedBox(height: v360.spacing.lg),
              SectionLabel('History'),
              V360Card(
                child: OrderTimeline(
                  steps: <TimelineStep>[
                    for (final event in order.events)
                      TimelineStep(
                        label: event.toStatus.distributorLabel,
                        timestamp: shortTime(event.createdAt),
                        actor: event.actorRole == 'distributor'
                            ? 'You'
                            : order.vendorName,
                        detail: event.note,
                        isTerminal: event.toStatus == OrderStatus.cancelled,
                      ),
                  ],
                  pending: switch (order.status) {
                    OrderStatus.placed => 'Waiting on you',
                    OrderStatus.confirmed => 'Ready to send out',
                    OrderStatus.dispatched => 'With the shop to confirm',
                    _ => null,
                  },
                ),
              ),
            ],
          ),
        ),
        if (_actionFor(order) != null) _bar(order),
      ],
    );
  }

  ({String label, String action})? _actionFor(PurchaseOrder order) =>
      switch (order.status) {
        OrderStatus.placed => (label: 'Accept order', action: 'confirm'),
        OrderStatus.confirmed => (label: 'Send out', action: 'dispatch'),
        OrderStatus.dispatched => (label: 'Mark delivered', action: 'deliver'),
        _ => null,
      };

  Widget _bar(PurchaseOrder order) {
    final v360 = context.v360;
    final colors = v360.colors;
    final action = _actionFor(order)!;

    return Container(
      padding: EdgeInsets.all(v360.spacing.gutter),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
        boxShadow: V360Elevation.floating(v360.brightness),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            if (order.status == OrderStatus.placed)
              Padding(
                padding: EdgeInsets.only(right: v360.spacing.sm),
                child: V360Button.ghost(
                  label: 'Decline',
                  onPressed: () => _reject(order),
                ),
              ),
            Expanded(
              child: V360Button.primary(
                label: action.label,
                expand: true,
                loading: _busy,
                onPressed: _busy ? null : () => _advance(order, action.action),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _advance(PurchaseOrder order, String action) => _run(
        () => ref.read(marketplaceProvider).advanceOrder(
              order.id,
              action,
              amended: action == 'dispatch' ? const {} : _amended,
            ),
        switch (action) {
          'confirm' => 'Accepted — ${order.vendorName} has been told',
          'dispatch' => 'On its way',
          _ => 'Marked delivered',
        },
      );

  Future<void> _reject(PurchaseOrder order) async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _RejectDialog(),
    );
    if (reason == null) return;
    await _run(
      () => ref.read(marketplaceProvider).rejectOrder(order.id, reason: reason),
      'Order declined',
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref
        ..invalidate(distOrderProvider(widget.orderId))
        ..invalidate(distInboxProvider)
        ..invalidate(distSummaryProvider)
        ..invalidate(distLedgerProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(success)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _RejectDialog extends StatefulWidget {
  const _RejectDialog();

  @override
  State<_RejectDialog> createState() => _RejectDialogState();
}

class _RejectDialogState extends State<_RejectDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Decline this order?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'Consider lowering the quantities instead — a part-fill keeps '
            'the shop supplied and keeps the order.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Reason (they will see this)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Go back'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Decline'),
        ),
      ],
    );
  }
}
