import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/api_client.dart';
import '../../data/marketplace_models.dart';

/// The order about to be placed.
///
/// Held in memory only. A cart that survived a relaunch would quietly
/// re-order yesterday's shortage — the stock position that justified it has
/// moved on, and an order nobody remembers placing is the worst kind.
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  bool _placing = false;
  final TextEditingController _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final lines = ref.watch(cartProvider);
    final cart = ref.read(cartProvider.notifier);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.go('/'),
        ),
        title: Text(
          'Your order',
          style: v360.text.titleM.copyWith(color: colors.ink),
        ),
        actions: <Widget>[
          if (lines.isNotEmpty)
            TextButton(
              onPressed: () {
                cart.clear();
                HapticFeedback.selectionClick();
              },
              child: Text('Clear', style: TextStyle(color: colors.dangerText)),
            ),
        ],
      ),
      body: SafeArea(
        child: lines.isEmpty
            ? EmptyState(
                icon: Icons.shopping_basket_outlined,
                title: 'Nothing to order yet',
                body: 'Tap Order on any low-stock item and it lands here.',
                action: V360Button.secondary(
                  label: 'See what is low',
                  onPressed: () => context.go('/inventory'),
                ),
              )
            : Column(
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
                          child: Row(
                            children: <Widget>[
                              Icon(Icons.local_shipping_outlined,
                                  color: colors.accentText, size: 20),
                              SizedBox(width: v360.spacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Text(
                                      cart.supplierName ?? '',
                                      style: v360.text.bodyStrong
                                          .copyWith(color: colors.ink),
                                    ),
                                    Text(
                                      'One order goes to one wholesaler',
                                      style: v360.text.caption
                                          .copyWith(color: colors.inkMuted),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(height: v360.spacing.md),
                        for (final line in lines)
                          Padding(
                            padding: EdgeInsets.only(bottom: v360.spacing.md),
                            child: _CartRow(line: line),
                          ),
                        SizedBox(height: v360.spacing.sm),
                        TextField(
                          controller: _note,
                          maxLength: 140,
                          style: v360.text.body.copyWith(color: colors.ink),
                          decoration: InputDecoration(
                            labelText: 'Note for the wholesaler (optional)',
                            hintText: 'e.g. deliver before 9am',
                            filled: true,
                            fillColor: colors.surface,
                            border: OutlineInputBorder(
                              borderRadius:
                                  BorderRadius.circular(V360Radius.md),
                              borderSide: BorderSide(color: colors.hairline),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _Footer(
                    total: cart.total,
                    placing: _placing,
                    onPlace: _place,
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _place() async {
    final cart = ref.read(cartProvider.notifier);
    final lines = ref.read(cartProvider);
    final supplierId = cart.supplierId;
    if (supplierId == null || lines.isEmpty) return;

    setState(() => _placing = true);
    try {
      final order = await ref.read(marketplaceProvider).placeOrder(
            supplierId: supplierId,
            lines: lines,
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );

      cart.clear();
      ref.invalidate(ordersProvider);
      ref.invalidate(dashboardProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.go('/orders/${order.id}');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${order.code} sent to ${order.supplierName}')),
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() => _placing = false);
      // Writes never fall back silently — the vendor is told, and the cart is
      // kept so a retry costs nothing.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.message),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _placing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not reach the wholesaler. Your order is still here — '
            'try again when you have signal.',
          ),
        ),
      );
    }
  }
}

class _CartRow extends ConsumerWidget {
  const _CartRow({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  line.option.skuName,
                  style: v360.text.bodyStrong.copyWith(color: colors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  '₹${line.option.packPrice.toStringAsFixed(0)} per case '
                  'of ${Quantity(line.option.packSize, line.option.unit).display}',
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
                SizedBox(height: v360.spacing.sm),
                V360IconButton(
                  icon: Icons.delete_outline_rounded,
                  onPressed: () => ref
                      .read(cartProvider.notifier)
                      .remove(line.option.catalogEntryId),
                  semanticLabel: 'Remove ${line.option.skuName}',
                ),
              ],
            ),
          ),
          PackStepper(
            packs: line.packs,
            packSize: line.option.packSize,
            unit: line.option.unit,
            minPacks: line.option.moqPacks,
            unitPrice: line.option.unitPrice,
            onChanged: (packs) => ref
                .read(cartProvider.notifier)
                .setPacks(line.option.catalogEntryId, packs),
          ),
        ],
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer({
    required this.total,
    required this.placing,
    required this.onPlace,
  });

  final double total;
  final bool placing;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      padding: EdgeInsets.fromLTRB(
        v360.spacing.gutter,
        v360.spacing.lg,
        v360.spacing.gutter,
        v360.spacing.lg,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
        boxShadow: V360Elevation.floating(v360.brightness),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  'Total',
                  style: v360.text.body.copyWith(color: colors.inkMuted),
                ),
                Text(
                  Money.rupees(total).display,
                  style: v360.text.titleM.copyWith(
                    color: colors.ink,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.md),
            V360Button.primary(
              label: 'Send order',
              expand: true,
              loading: placing,
              onPressed: placing ? null : onPlace,
            ),
          ],
        ),
      ),
    );
  }
}
