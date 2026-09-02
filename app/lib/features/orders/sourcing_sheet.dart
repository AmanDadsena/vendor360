import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';

/// Who to buy a shortfall from, and why.
///
/// Opened from any low-stock row. Three decisions are visible on this sheet
/// rather than buried:
///
/// * **The rounding.** Wholesalers sell cases, so 12 kg becomes two 10 kg
///   cases and 20 kg arrives. Showing that up front prevents the single most
///   common surprise in wholesale ordering.
/// * **The reasoning.** Every option carries the reasons it ranked where it
///   did. A vendor who cannot see why the top option is on top has no way to
///   disagree with it, and will stop trusting the order.
/// * **The timing.** An option that cannot arrive before the shelf empties is
///   marked, however cheap it is.
Future<void> showSourcingSheet(
  BuildContext context, {
  required String itemId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _SourcingSheet(itemId: itemId),
  );
}

class _SourcingSheet extends ConsumerWidget {
  const _SourcingSheet({required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final sourcing = ref.watch(sourcingProvider(itemId));

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.symmetric(vertical: v360.spacing.md),
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(V360Radius.pill),
                ),
              ),
            ),
            Expanded(
              child: sourcing.when(
                loading: () => ListView(
                  controller: controller,
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  children: <Widget>[
                    const V360Skeleton(height: 60),
                    SizedBox(height: v360.spacing.md),
                    const V360Skeleton(height: 130),
                    SizedBox(height: v360.spacing.md),
                    const V360Skeleton(height: 130),
                  ],
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not check prices',
                  body: '$error',
                ),
                data: (data) => _Body(data: data, controller: controller),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.data, required this.controller});

  final Sourcing data;
  final ScrollController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    if (!data.hasOptions) {
      return Padding(
        padding: EdgeInsets.all(v360.spacing.gutter),
        child: EmptyState(
          icon: Icons.storefront_outlined,
          title: 'No connected supplier sells this',
          body: data.unconnectedCount > 0
              ? '${data.unconnectedCount} '
                  '${data.unconnectedCount == 1 ? 'wholesaler' : 'wholesalers'} '
                  'near you stock ${data.skuName}. Connect to one to order it '
                  'from here.'
              : 'None of the wholesalers near you list ${data.skuName} yet.',
          action: V360Button.secondary(
            label: 'Find distributors',
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/distributors');
            },
          ),
        ),
      );
    }

    return ListView(
      controller: controller,
      padding: EdgeInsets.fromLTRB(
        v360.spacing.gutter,
        0,
        v360.spacing.gutter,
        v360.spacing.x5,
      ),
      children: <Widget>[
        Text(
          data.skuName,
          style: v360.text.titleL.copyWith(color: colors.ink),
        ),
        SizedBox(height: v360.spacing.xs),
        Text(
          _shortfallLine(data),
          style: v360.text.body.copyWith(color: colors.inkMuted),
        ),
        SizedBox(height: v360.spacing.lg),
        for (var i = 0; i < data.options.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: v360.spacing.md),
            child: _OptionCard(
              option: data.options[i],
              itemId: data.itemId,
              isBest: i == 0,
              shortfall: data.shortfall,
            ),
          ),
        if (data.unconnectedCount > 0) ...<Widget>[
          SizedBox(height: v360.spacing.sm),
          V360Banner(
            icon: Icons.add_business_outlined,
            title: '${data.unconnectedCount} more '
                '${data.unconnectedCount == 1 ? 'wholesaler' : 'wholesalers'} '
                'stock this',
            body: 'Connect to compare their prices here too.',
            onTap: () {
              Navigator.of(context).pop();
              context.go('/distributors');
            },
          ),
        ],
      ],
    );
  }

  String _shortfallLine(Sourcing data) {
    final qty = Quantity(data.shortfall, data.unit).display;
    if (data.daysOfCover == null) return 'Suggested order: $qty';

    final cover = data.daysOfCover! < 3
        ? data.daysOfCover!.toStringAsFixed(1)
        : data.daysOfCover!.toStringAsFixed(0);
    return '$qty suggested · about $cover days of stock left';
  }
}

class _OptionCard extends ConsumerWidget {
  const _OptionCard({
    required this.option,
    required this.itemId,
    required this.isBest,
    required this.shortfall,
  });

  final SourcingOption option;
  final String itemId;
  final bool isBest;
  final double shortfall;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    final plan = PackQuantity.forShortfall(
      shortfall: shortfall,
      packSize: option.packSize,
      unit: option.unit,
      moqPacks: option.moqPacks,
    );

    return V360Card(
      // The recommendation gets a tinted surface rather than a badge alone —
      // the difference has to survive a glance in a badly lit shop.
      color: isBest ? colors.accentSurface : null,
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
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            option.supplierName,
                            style: v360.text.titleS.copyWith(color: colors.ink),
                          ),
                        ),
                        if (isBest) ...<Widget>[
                          SizedBox(width: v360.spacing.sm),
                          const OrderStatusChip(
                            label: 'Best',
                            tone: OrderTone.active,
                            dense: true,
                            icon: Icons.star_rounded,
                          ),
                        ],
                      ],
                    ),
                    SizedBox(height: 2),
                    Text(
                      '₹${option.unitPrice.toStringAsFixed(2)} per ${option.unit}'
                      '${option.distanceKm == null ? '' : ' · ${option.distanceKm!.toStringAsFixed(1)} km'}',
                      style: v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    Money.rupees(plan.costAt(option.packPrice)).display,
                    style: v360.text.titleS.copyWith(
                      color: colors.ink,
                      fontFeatures: const <FontFeature>[
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                  Text(
                    plan.packDisplay,
                    style: v360.text.label.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: v360.spacing.md),

          // The rounding, stated plainly. This line is the reason a vendor is
          // not surprised at the doorstep.
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(v360.spacing.md),
            decoration: BoxDecoration(
              color: colors.surfaceMuted,
              borderRadius: BorderRadius.circular(V360Radius.md),
            ),
            child: Text(
              _roundingLine(plan),
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
          ),

          if (option.reasons.isNotEmpty) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            ReasonRow(reasons: option.reasons),
          ],

          SizedBox(height: v360.spacing.md),
          Row(
            children: <Widget>[
              Expanded(
                child: V360Button.secondary(
                  label: 'Add to order',
                  expand: true,
                  onPressed: () => _add(context, ref, plan, andGo: false),
                ),
              ),
              SizedBox(width: v360.spacing.sm),
              Expanded(
                child: V360Button.primary(
                  label: 'Order now',
                  expand: true,
                  onPressed: () => _add(context, ref, plan, andGo: true),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _roundingLine(PackQuantity plan) {
    final surplus = plan.surplusOver(shortfall);
    final arriving = plan.asQuantity.display;

    if (plan.moqApplied) {
      return 'Minimum order is ${plan.packs} '
          '${plan.packs == 1 ? 'case' : 'cases'} — $arriving arrives.';
    }
    if (surplus <= 0.01) {
      return 'You need ${Quantity(shortfall, plan.unit).display} — '
          '$arriving arrives, exactly.';
    }
    return 'You need ${Quantity(shortfall, plan.unit).display} — sold by the '
        '${Quantity(plan.packSize, plan.unit).display}, so $arriving arrives '
        '(${Quantity(surplus, plan.unit).display} extra).';
  }

  Future<void> _add(
    BuildContext context,
    WidgetRef ref,
    PackQuantity plan, {
    required bool andGo,
  }) async {
    final cart = ref.read(cartProvider.notifier);

    // A cart holds one supplier at a time: one basket that silently becomes
    // two deliveries is a worse surprise than being asked.
    if (cart.wouldReplace(option.supplierId)) {
      final replace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Start a new order?'),
          content: Text(
            'Your current order is with ${cart.supplierName}. '
            'Each order goes to one wholesaler, so adding '
            '${option.supplierName} will start a fresh one.',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Keep current'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Start new'),
            ),
          ],
        ),
      );
      if (replace != true) return;
    }

    HapticFeedback.lightImpact();
    cart.add(CartLine(option: option, itemId: itemId, packs: plan.packs));

    if (!context.mounted) return;
    Navigator.of(context).pop();

    if (andGo) {
      context.go('/cart');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${option.skuName} added to your order'),
          action: SnackBarAction(
            label: 'View',
            onPressed: () => context.go('/cart'),
          ),
        ),
      );
    }
  }
}
