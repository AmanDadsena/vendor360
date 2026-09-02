import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import 'order_widgets.dart';

/// One order, its history, and the one action available on it.
///
/// The receive flow is the important part. When the delivery arrives the
/// vendor counts what is actually on the doorstep, and *their* count wins over
/// the wholesaler's — they are the one standing in front of the crates. That
/// count both restocks the shelf and feeds the fill rate that ranks this
/// supplier next time.
class OrderDetailScreen extends ConsumerWidget {
  const OrderDetailScreen({super.key, required this.orderId});

  final String orderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final order = ref.watch(orderDetailProvider(orderId));

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/orders'),
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
            child: const V360Skeleton(height: 300),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load this order',
            body: '$error',
          ),
          data: (data) => _Detail(order: data),
        ),
      ),
    );
  }
}

class _Detail extends ConsumerStatefulWidget {
  const _Detail({required this.order});

  final PurchaseOrder order;

  @override
  ConsumerState<_Detail> createState() => _DetailState();
}

class _DetailState extends ConsumerState<_Detail> {
  /// Line id → cases actually counted. Empty means "everything as confirmed",
  /// which is the common case and one the vendor should not have to type out.
  final Map<String, double> _counted = <String, double>{};
  bool _busy = false;

  PurchaseOrder get order => widget.order;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;

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
              _Header(order: order),
              SizedBox(height: v360.spacing.lg),

              if (order.isLate)
                Padding(
                  padding: EdgeInsets.only(bottom: v360.spacing.md),
                  child: V360Banner(
                    icon: Icons.warning_amber_rounded,
                    tone: V360BannerTone.danger,
                    title: 'This is late',
                    body: 'It was due ${shortDate(order.expectedAt)}. '
                        '${order.supplierPhone == null ? '' : 'Call them on ${order.supplierPhone}.'}',
                  ),
                ),

              SectionLabel(
                order.status == OrderStatus.dispatched
                    ? 'Count what arrives'
                    : 'Items',
              ),
              V360Card(
                child: Column(
                  children: <Widget>[
                    for (final line in order.lines)
                      OrderLineRow(
                        line: line,
                        trailing: _isReceiving
                            ? PackStepper(
                                dense: true,
                                packs: (_counted[line.id] ??
                                        line.effectivePacks)
                                    .round(),
                                packSize: line.packSize,
                                unit: line.unit,
                                minPacks: 0,
                                onChanged: (packs) => setState(
                                  () => _counted[line.id] = packs.toDouble(),
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
                        label: event.toStatus.vendorLabel,
                        timestamp: shortTime(event.createdAt),
                        actor: event.actorRole == 'vendor'
                            ? 'You'
                            : order.supplierName,
                        detail: event.note,
                        isTerminal: event.toStatus == OrderStatus.cancelled,
                      ),
                  ],
                  pending: _pendingLabel,
                ),
              ),
            ],
          ),
        ),
        if (_action != null) _actionBar(context),
      ],
    );
  }

  bool get _isReceiving => order.status == OrderStatus.dispatched;

  String? get _pendingLabel => switch (order.status) {
        OrderStatus.placed => 'Waiting for them to confirm',
        OrderStatus.confirmed => 'Waiting for dispatch',
        OrderStatus.dispatched => 'Out for delivery',
        _ => null,
      };

  ({String label, Future<void> Function() run})? get _action =>
      switch (order.status) {
        OrderStatus.draft => (label: 'Send order', run: _place),
        OrderStatus.dispatched => (label: 'Mark as received', run: _receive),
        _ => null,
      };

  Widget _actionBar(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final action = _action!;

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
            if (order.status.isOpen && order.status != OrderStatus.dispatched)
              Padding(
                padding: EdgeInsets.only(right: v360.spacing.sm),
                child: V360Button.ghost(label: 'Cancel', onPressed: _cancel),
              ),
            Expanded(
              child: V360Button.primary(
                label: action.label,
                expand: true,
                loading: _busy,
                onPressed: _busy ? null : action.run,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _place() => _run(
        () => ref.read(marketplaceProvider).placeOrder(
              supplierId: order.supplierId,
              lines: const <CartLine>[],
            ),
        'Order sent',
      );

  Future<void> _receive() => _run(
        () => ref
            .read(marketplaceProvider)
            .receiveOrder(order.id, received: _counted),
        'Stock added to your shelf',
      );

  Future<void> _cancel() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => const _CancelDialog(),
    );
    if (reason == null) return;
    await _run(
      () => ref.read(marketplaceProvider).cancelOrder(order.id, reason: reason),
      'Order cancelled',
    );
  }

  Future<void> _run(Future<void> Function() action, String success) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(orderDetailProvider(order.id));
      ref.invalidate(ordersProvider);
      ref.invalidate(inventoryProvider);
      ref.invalidate(dashboardProvider);
      ref.invalidate(ledgerProvider);

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

class _Header extends StatelessWidget {
  const _Header({required this.order});

  final PurchaseOrder order;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  order.supplierName,
                  style: v360.text.titleM.copyWith(color: colors.ink),
                ),
              ),
              OrderStatusChip(
                label: order.status.vendorLabel,
                tone: toneFor(order.status),
              ),
            ],
          ),
          SizedBox(height: v360.spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: StatTile(
                  label: 'Total',
                  value: order.total.display,
                  compact: true,
                ),
              ),
              SizedBox(width: v360.spacing.md),
              Expanded(
                child: StatTile(
                  label: order.amountDue > 0 ? 'Still owed' : 'Paid',
                  value: order.amountDue > 0
                      ? order.due.display
                      : order.total.display,
                  tone: order.amountDue > 0 ? colors.warningText : null,
                  compact: true,
                ),
              ),
            ],
          ),
          if (order.note != null) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            Text(
              '“${order.note}”',
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _CancelDialog extends StatefulWidget {
  const _CancelDialog();

  @override
  State<_CancelDialog> createState() => _CancelDialogState();
}

class _CancelDialogState extends State<_CancelDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Cancel this order?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Text(
            'The wholesaler will be told. Let them know why so the '
            'relationship survives it.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Reason (optional)',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Keep it'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_controller.text.trim()),
          child: const Text('Cancel order'),
        ),
      ],
    );
  }
}
