import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/order_widgets.dart';

/// The book: who buys, what they are worth, and who is slipping away.
///
/// Sorted by revenue, but a shop that has stopped ordering is flagged
/// wherever it lands — a customer quietly going quiet is the most expensive
/// thing on this screen and the easiest to miss in a list sorted by money.
class DistShopsScreen extends ConsumerWidget {
  const DistShopsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final book = ref.watch(distBookProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text('Shops', style: v360.text.titleM.copyWith(color: colors.ink)),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Money owed to you',
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const LedgerSheet(distributorView: true),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: book.when(
          loading: () => ListView.builder(
            padding: EdgeInsets.all(v360.spacing.gutter),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: const V360Skeleton(height: 110),
            ),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load your shops',
            body: '$error',
          ),
          data: (shops) {
            if (shops.isEmpty) {
              return const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No shops yet',
                body: 'Shops find you through the app when your catalog has '
                    'what they need nearby. Adding prices is the fastest way '
                    'to appear.',
              );
            }

            final sorted = <BookEntry>[...shops]
              ..sort((a, b) => b.revenue.compareTo(a.revenue));

            return RefreshIndicator(
              color: colors.accent,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref.invalidate(distBookProvider);
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  v360.spacing.gutter,
                  0,
                  v360.spacing.gutter,
                  v360.spacing.x5,
                ),
                children: <Widget>[
                  for (final shop in sorted)
                    Padding(
                      padding: EdgeInsets.only(bottom: v360.spacing.md),
                      child: _ShopCard(shop: shop),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ShopCard extends ConsumerWidget {
  const _ShopCard({required this.shop});

  final BookEntry shop;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      shop.storeName,
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${shop.ownerName} · ${shop.locality}',
                      style:
                          v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              Text(
                shop.revenueMoney.display,
                style: v360.text.titleS.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),

          SizedBox(height: v360.spacing.md),

          Wrap(
            spacing: v360.spacing.xs,
            runSpacing: v360.spacing.xs,
            children: <Widget>[
              _Pill(
                text: '${shop.orderCount} '
                    '${shop.orderCount == 1 ? 'order' : 'orders'}',
              ),
              if (shop.fillRate != null)
                _Pill(
                  text: 'you filled ${(shop.fillRate! * 100).round()}%',
                  warn: shop.fillRate! < 0.8,
                ),
              if (!shop.sharesDemand)
                const _Pill(text: 'numbers private', icon: Icons.lock_outline),
              if (shop.isLapsing)
                _Pill(
                  text: 'quiet ${shop.daysSinceLastOrder} days',
                  warn: true,
                ),
            ],
          ),

          if (shop.outstanding > 0) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${shop.outstandingMoney.display} outstanding',
                    style: v360.text.body.copyWith(color: colors.warningText),
                  ),
                ),
                V360Button.secondary(
                  label: 'Record payment',
                  onPressed: () => _recordPayment(context, ref),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _recordPayment(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: shop.outstanding.toStringAsFixed(0));

    final amount = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Payment from ${shop.storeName}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Amount received',
            prefixText: '₹ ',
            border: OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context)
                .pop(double.tryParse(controller.text.trim())),
            child: const Text('Record'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (amount == null || amount <= 0) return;

    try {
      await ref
          .read(marketplaceProvider)
          .recordPayment(vendorId: shop.vendorId, amount: amount);
      ref
        ..invalidate(distBookProvider)
        ..invalidate(distLedgerProvider)
        ..invalidate(distSummaryProvider);

      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('₹${amount.round()} recorded')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    }
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, this.warn = false, this.icon});

  final String text;
  final bool warn;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: v360.spacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: warn ? colors.warningSurface : colors.surfaceMuted,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 11, color: colors.inkMuted),
            SizedBox(width: 3),
          ],
          Text(
            text,
            style: v360.text.label.copyWith(
              color: warn ? colors.warningText : colors.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
