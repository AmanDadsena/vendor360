import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';

/// The expiry command centre.
///
/// Ranked by days remaining, then by value at risk. That ordering is the point
/// of the screen: 3 kg of paneer outranks 40 kg of potatoes even though the
/// potato pile looks bigger, and a vendor clearing stock before it spoils is
/// making a money decision, not a volume one.
///
/// This is the mechanism behind the PRD's 20% waste-reduction target.
class ExpiryScreen extends ConsumerWidget {
  const ExpiryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final entries = ref.watch(expiryProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text('Expiry', style: v360.text.titleM.copyWith(color: colors.ink)),
      ),
      body: SafeArea(
        child: entries.when(
          loading: () => ListView.builder(
            padding: EdgeInsets.all(v360.spacing.gutter),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: const V360Skeleton(height: 150),
            ),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load expiry data',
            body: '$error',
          ),
          data: (list) {
            if (list.isEmpty) {
              return const EmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing expiring soon',
                body: 'No perishable stock is within a week of its shelf life.',
              );
            }

            final totalAtRisk = list.fold<Money>(
              Money.zero,
              (sum, e) => sum + e.valueAtRisk,
            );

            return RefreshIndicator(
              color: colors.accent,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(expiryProvider);
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  v360.spacing.gutter, 0, v360.spacing.gutter, v360.spacing.x5,
                ),
                children: <Widget>[
                  V360Reveal(
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'Value at risk',
                            value: totalAtRisk.display,
                            caption: 'across ${list.length} items',
                            icon: Icons.warning_amber_rounded,
                            tone: colors.danger,
                            compact: true,
                          ),
                        ),
                        SizedBox(width: v360.spacing.md),
                        Expanded(
                          child: StatTile(
                            label: 'Expiring today',
                            value: '${list.where((e) => e.daysLeft <= 0).length}',
                            caption: 'discount now to recover cost',
                            icon: Icons.timer_outlined,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: v360.spacing.xl),
                  const SectionLabel('Clear these first'),
                  SizedBox(height: v360.spacing.md),
                  for (var i = 0; i < list.length; i++)
                    V360Reveal(
                      delayIndex: i,
                      child: ExpiryRow(
                        skuName: list[i].skuName,
                        quantityLabel: list[i].quantity.display,
                        daysLeft: list[i].daysLeft,
                        valueAtRisk: list[i].valueAtRisk.display,
                        suggestedDiscountPct: list[i].suggestedDiscountPct,
                        onDiscount: () => _confirmDiscount(context, list[i]),
                        onMarkWasted: () => _markWasted(context, ref, list[i]),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _confirmDiscount(BuildContext context, dynamic entry) {
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${entry.skuName}: mark ${entry.suggestedDiscountPct}% off on the shelf',
        ),
      ),
    );
  }

  Future<void> _markWasted(
    BuildContext context, WidgetRef ref, dynamic entry,
  ) async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Record as waste?'),
        content: Text(
          'This removes ${entry.quantity.display} of ${entry.skuName} from '
          'stock and records the loss.\n\n'
          'Recording waste honestly is what keeps your Health Score accurate.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Record waste'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    HapticFeedback.mediumImpact();
    await ref.read(repositoryProvider).recordMovement(
          itemId: entry.itemId as String,
          qty: (entry.quantity as Quantity).amount,
          movement: 'wastage',
        );
    ref.read(syncProvider.notifier).refresh();
    ref.invalidate(expiryProvider);
    ref.invalidate(inventoryProvider);
    ref.invalidate(dashboardProvider);
  }
}
