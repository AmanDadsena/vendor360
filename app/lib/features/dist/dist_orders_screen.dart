import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/order_widgets.dart';

/// The wholesaler's inbox.
///
/// Defaults to what needs answering rather than to everything, because an
/// inbox that opens on history is one nobody clears. Drafts never appear:
/// a draft is a shop still deciding, and showing it would be reading over
/// their shoulder.
class DistOrdersScreen extends ConsumerWidget {
  const DistOrdersScreen({super.key});

  static const List<(String?, String)> _filters = <(String?, String)>[
    ('placed', 'New'),
    ('confirmed', 'To dispatch'),
    ('dispatched', 'In transit'),
    (null, 'All'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final orders = ref.watch(distInboxProvider);
    final filter = ref.watch(distInboxFilterProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text('Orders', style: v360.text.titleM.copyWith(color: colors.ink)),
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
                      child: _Chip(
                        label: label,
                        selected: filter == value,
                        onTap: () => ref
                            .read(distInboxFilterProvider.notifier)
                            .value = value,
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
                  title: 'Could not load the inbox',
                  body: '$error',
                ),
                data: (list) {
                  final shown = filter == null
                      ? list
                      : list.where((o) => o.status.wire == filter).toList();

                  if (shown.isEmpty) {
                    return EmptyState(
                      icon: Icons.inbox_outlined,
                      title: switch (filter) {
                        'placed' => 'Nothing waiting on you',
                        'confirmed' => 'Nothing to send out',
                        'dispatched' => 'Nothing in transit',
                        _ => 'No orders yet',
                      },
                      body: filter == null
                          ? 'Orders appear here as soon as a connected shop '
                              'sends one.'
                          : 'Good — you are clear at this stage.',
                    );
                  }

                  return RefreshIndicator(
                    color: colors.accent,
                    onRefresh: () async {
                      HapticFeedback.lightImpact();
                      ref
                        ..invalidate(distInboxProvider)
                        ..invalidate(distSummaryProvider);
                    },
                    child: ListView(
                      padding: EdgeInsets.fromLTRB(
                        v360.spacing.gutter,
                        0,
                        v360.spacing.gutter,
                        v360.spacing.x5,
                      ),
                      children: <Widget>[
                        for (final order in shown)
                          Padding(
                            padding: EdgeInsets.only(bottom: v360.spacing.md),
                            child: OrderCard(
                              order: order,
                              distributorView: true,
                              onTap: () =>
                                  context.go('/dist/orders/${order.id}'),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
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
          border: Border.all(color: selected ? colors.accent : colors.hairline),
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
