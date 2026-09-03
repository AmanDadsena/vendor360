import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/models.dart';

/// Collective bargaining.
///
/// When several nearby stores are short of the same SKU, their orders are
/// batched into one wholesale order that clears a bulk discount none of them
/// reaches alone. The quoted price is recomputed whenever a member joins or
/// leaves, because a pool that loses volume loses the discount that volume
/// bought — quoting a stale price would be quoting one the supplier will not
/// honour.
class PoolsScreen extends ConsumerWidget {
  const PoolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final pools = ref.watch(poolsProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text('Bulk deals', style: v360.text.titleM.copyWith(color: colors.ink)),
      ),
      body: SafeArea(
        child: pools.when(
          loading: () => ListView.builder(
            padding: EdgeInsets.all(v360.spacing.gutter),
            itemCount: 2,
            itemBuilder: (_, _) => Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: const V360Skeleton(height: 190),
            ),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load deals',
            body: '$error',
          ),
          data: (list) => list.isEmpty
              ? const EmptyState(
                  icon: Icons.groups_outlined,
                  title: 'No group orders right now',
                  body: 'A deal appears when three or more stores near you '
                      'run short of the same item. Keep logging stock and '
                      'you will be included automatically.',
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    ref.invalidate(poolsProvider);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      v360.spacing.gutter, 0, v360.spacing.gutter, v360.spacing.x5,
                    ),
                    children: <Widget>[
                      Text(
                        'Stores near you are short of the same items. '
                        'Order together, pay wholesale rates.',
                        style: v360.text.body.copyWith(color: colors.inkMuted),
                      ),
                      SizedBox(height: v360.spacing.xl),
                      for (var i = 0; i < list.length; i++)
                        V360Reveal(
                          delayIndex: i,
                          child: _PoolCard(pool: list[i]),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

class _PoolCard extends ConsumerStatefulWidget {
  const _PoolCard({required this.pool});

  final BargainPool pool;

  @override
  ConsumerState<_PoolCard> createState() => _PoolCardState();
}

class _PoolCardState extends ConsumerState<_PoolCard> {
  double _qty = 10;
  bool _busy = false;

  Future<void> _toggle() async {
    HapticFeedback.selectionClick();
    setState(() => _busy = true);
    final repo = ref.read(repositoryProvider);
    try {
      if (widget.pool.joined) {
        await repo.leavePool(widget.pool.id);
      } else {
        await repo.joinPool(widget.pool.id, _qty);
      }
      ref.invalidate(poolsProvider);
      ref.invalidate(dashboardProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final pool = widget.pool;
    final remaining = (pool.targetQty - pool.committedQty).clamp(0, double.infinity);

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.lg),
      child: V360Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        pool.skuName,
                        style: v360.text.titleM.copyWith(color: colors.ink),
                      ),
                      Text(
                        '${pool.memberCount} stores in ${pool.locality}',
                        style: v360.text.caption.copyWith(color: colors.inkMuted),
                      ),
                    ],
                  ),
                ),
                if (pool.discountPct > 0)
                  StatusPill(
                    label: '${pool.discountPct}% off',
                    tone: PillTone.healthy,
                    icon: Icons.savings_outlined,
                  ),
              ],
            ),
            SizedBox(height: v360.spacing.lg),

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: <Widget>[
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const SectionLabel('Group price'),
                    SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: <Widget>[
                        Text(
                          pool.bulkUnitPrice.display,
                          style: v360.text.titleL.copyWith(color: colors.accentText),
                        ),
                        SizedBox(width: v360.spacing.sm),
                        Text(
                          pool.baseUnitPrice.display,
                          style: v360.text.caption.copyWith(
                            color: colors.inkSubtle,
                            decoration: TextDecoration.lineThrough,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'per ${pool.unit}',
                  style: v360.text.caption.copyWith(color: colors.inkSubtle),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.lg),

            CapacityBar(fraction: pool.progress),
            SizedBox(height: v360.spacing.sm),
            Text(
              '${pool.committedQty.toStringAsFixed(0)} of '
              '${pool.targetQty.toStringAsFixed(0)} ${pool.unit} committed',
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
            SizedBox(height: v360.spacing.xs),
            Text(
              remaining > 0
                  ? '${remaining.toStringAsFixed(0)} ${pool.unit} more unlocks the next tier'
                  : 'Target reached — the discount is locked in',
              style: v360.text.caption.copyWith(
                color: remaining > 0 ? colors.inkMuted : colors.accentText,
              ),
            ),
            SizedBox(height: v360.spacing.lg),

            if (!pool.joined) ...<Widget>[
              Row(
                children: <Widget>[
                  const SectionLabel('Your share'),
                  const Spacer(),
                  V360IconButton(
                    icon: Icons.remove_rounded,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _qty = (_qty - 5).clamp(5, 999));
                    },
                    size: 40,
                    semanticLabel: 'Decrease',
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: v360.spacing.md),
                    child: Text(
                      '${_qty.toStringAsFixed(0)} ${pool.unit}',
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                  ),
                  V360IconButton(
                    icon: Icons.add_rounded,
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      setState(() => _qty += 5);
                    },
                    size: 40,
                    semanticLabel: 'Increase',
                  ),
                ],
              ),
              SizedBox(height: v360.spacing.sm),
              Text(
                'You save ${(pool.savingsPerUnit * _qty).display} on this order',
                style: v360.text.caption.copyWith(color: colors.accentText),
              ),
              SizedBox(height: v360.spacing.lg),
            ],

            pool.joined
                ? V360Button.secondary(
                    label: 'Leave this group',
                    expand: true,
                    loading: _busy,
                    onPressed: _toggle,
                  )
                : V360Button.primary(
                    label: 'Join group order',
                    expand: true,
                    loading: _busy,
                    leadingIcon: Icons.group_add_outlined,
                    onPressed: _toggle,
                  ),

            if (pool.joined) ...<Widget>[
              SizedBox(height: v360.spacing.sm),
              Text(
                'Leaving adjusts the group total — the price above recalculates '
                'for everyone.',
                style: v360.text.caption.copyWith(color: colors.inkSubtle),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
