import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import 'order_widgets.dart';

/// Every order this shop has placed.
///
/// Sorted newest first and filtered by stage, because the question a
/// shopkeeper actually has is "where is my delivery", not "show me history".
/// Anything late is surfaced at the top regardless of the filter — a promised
/// date that has passed is the one thing worth interrupting for.
class OrdersScreen extends ConsumerWidget {
  const OrdersScreen({super.key});

  static const List<(String?, String)> _filters = <(String?, String)>[
    (null, 'All'),
    ('placed', 'Waiting'),
    ('confirmed', 'Confirmed'),
    ('dispatched', 'On the way'),
    ('delivered', 'Received'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final orders = ref.watch(ordersProvider);
    final filter = ref.watch(orderFilterProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text('Orders', style: v360.text.titleM.copyWith(color: colors.ink)),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Money owed',
            onPressed: () => _showLedger(context, ref),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: EdgeInsets.symmetric(horizontal: v360.spacing.gutter),
                children: <Widget>[
                  for (final (value, label) in _filters)
                    Padding(
                      padding: EdgeInsets.only(right: v360.spacing.sm),
                      child: _FilterChip(
                        label: label,
                        selected: filter == value,
                        onTap: () =>
                            ref.read(orderFilterProvider.notifier).value = value,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: v360.spacing.sm),
            Expanded(
              child: orders.when(
                loading: () => ListView.builder(
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  itemCount: 3,
                  itemBuilder: (_, __) => Padding(
                    padding: EdgeInsets.only(bottom: v360.spacing.md),
                    child: const V360Skeleton(height: 110),
                  ),
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load orders',
                  body: '$error',
                ),
                data: (list) => list.isEmpty
                    ? EmptyState(
                        icon: Icons.receipt_long_outlined,
                        title: filter == null
                            ? 'No orders yet'
                            : 'Nothing at this stage',
                        body: filter == null
                            ? 'When something runs low, tap Order on it and '
                                'the order appears here.'
                            : 'Try another filter.',
                        action: filter == null
                            ? V360Button.secondary(
                                label: 'See what is low',
                                onPressed: () => context.go('/inventory'),
                              )
                            : null,
                      )
                    : RefreshIndicator(
                        color: colors.accent,
                        onRefresh: () async {
                          HapticFeedback.lightImpact();
                          ref.invalidate(ordersProvider);
                        },
                        child: ListView(
                          padding: EdgeInsets.fromLTRB(
                            v360.spacing.gutter,
                            0,
                            v360.spacing.gutter,
                            v360.spacing.x5,
                          ),
                          children: <Widget>[
                            for (final order in _ordered(list))
                              Padding(
                                padding:
                                    EdgeInsets.only(bottom: v360.spacing.md),
                                child: OrderCard(
                                  order: order,
                                  onTap: () =>
                                      context.go('/orders/${order.id}'),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Late orders first, then by recency. A promised date that has passed is
  /// the only thing worth pulling out of chronological order.
  List<PurchaseOrder> _ordered(List<PurchaseOrder> list) {
    final sorted = <PurchaseOrder>[...list];
    sorted.sort((a, b) {
      if (a.isLate != b.isLate) return a.isLate ? -1 : 1;
      final at = a.placedAt ?? DateTime(2000);
      final bt = b.placedAt ?? DateTime(2000);
      return bt.compareTo(at);
    });
    return sorted;
  }

  void _showLedger(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LedgerSheet(),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionScope.of(context).base,
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.lg,
          vertical: v360.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSurfaceStrong : colors.surface,
          borderRadius: BorderRadius.circular(V360Radius.pill),
          border: Border.all(
            color: selected ? colors.accent : colors.hairline,
          ),
        ),
        child: Text(
          label,
          style: v360.text.label.copyWith(
            color: selected ? colors.accentText : colors.inkMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
