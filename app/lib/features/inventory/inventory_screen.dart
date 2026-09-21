import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/sourcing_sheet.dart';
import '../../core/strings.dart';

/// Current stock, with live reorder thresholds.
///
/// The reorder point is shown as a computed threshold rather than a setting,
/// because it is recomputed from sales velocity, lead time and shelf life on
/// every read (UI/UX 5.4). Presenting it as an editable number would invite a
/// vendor to fix it in place, which is exactly the fixed-threshold behaviour
/// this replaces.
class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final items = ref.watch(filteredInventoryProvider);
    final lowOnly = ref.watch(lowOnlyProvider);
    final category = ref.watch(inventoryFilterProvider);

    final count = items.value?.length;

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: Column(
        children: <Widget>[
          PackHeader(
            title: s.inventory,
            subtitle: count == null
                ? null
                : lowOnly
                    ? '$count ${s.runningOut.toLowerCase()}'
                    : '$count items',
            bottom: const _InventorySearchBar(),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
              v360.spacing.gutter,
              v360.spacing.md,
              v360.spacing.gutter,
              v360.spacing.sm,
            ),
            child: Row(
              children: <Widget>[
                V360Segmented<bool>(
                  value: lowOnly,
                  onChanged: (value) =>
                      ref.read(lowOnlyProvider.notifier).value = value,
                  segments: <V360Segment<bool>>[
                    V360Segment<bool>(value: false, label: s.allItems),
                    V360Segment<bool>(value: true, label: s.runningOut),
                  ],
                ),
              ],
            ),
          ),
          _CategoryFilter(selected: category),
          const Divider(),
          Expanded(
            child: items.when(
              loading: () => ListView.builder(
                padding: EdgeInsets.all(v360.spacing.gutter),
                itemCount: 6,
                itemBuilder: (context, _) => Padding(
                  padding: EdgeInsets.only(bottom: v360.spacing.md),
                  child: const V360Skeleton(height: 64),
                ),
              ),
              error: (error, _) => EmptyState(
                icon: Icons.cloud_off_rounded,
                title: 'Could not load stock',
                body: '$error',
                action: V360Button.primary(
                  label: s.retry,
                  onPressed: () => ref.invalidate(inventoryProvider),
                ),
              ),
              data: (list) {
                final searchQ = ref.watch(inventorySearchQueryProvider);
                final isSearching = searchQ != null && searchQ.isNotEmpty;
                if (list.isEmpty) {
                  return EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: isSearching
                        ? 'No items matching "$searchQ"'
                        : (lowOnly ? 'Nothing needs reordering' : s.noData),
                    body: isSearching
                        ? 'Try a different name, or clear the search.'
                        : (lowOnly
                            ? s.allAboveReorder
                            : 'Log a sale or scan a receipt to get started.'),
                    action: isSearching
                        ? V360Button.ghost(
                            label: 'Clear search',
                            onPressed: () => ref
                                .read(inventorySearchQueryProvider.notifier)
                                .value = null,
                          )
                        : null,
                  );
                }
                return RefreshIndicator(
                  color: v360.colors.accent,
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    await ref.read(syncProvider.notifier).flush();
                    ref.invalidate(inventoryProvider);
                  },
                  // One ruled list, not a stack of cards: a shop's stock is a
                  // long list read top to bottom, and a card per item spends
                  // a third of every row on borders and gaps.
                  child: ListView.separated(
                    padding: EdgeInsets.only(bottom: v360.spacing.x5),
                    itemCount: list.length,
                    separatorBuilder: (_, _) =>
                        Divider(indent: v360.spacing.gutter),
                    itemBuilder: (context, index) =>
                        _ItemRow(item: list[index], strings: s),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryFilter extends ConsumerWidget {
  const _CategoryFilter({required this.selected});

  final String? selected;

  static const List<({String? key, String label})> _categories = <({String? key, String label})>[
    (key: null, label: 'All'),
    (key: 'dairy', label: 'Dairy'),
    (key: 'produce', label: 'Produce'),
    (key: 'staples', label: 'Staples'),
    (key: 'snacks', label: 'Snacks'),
    (key: 'beverages', label: 'Drinks'),
    (key: 'sweets', label: 'Sweets'),
    (key: 'household', label: 'Household'),
    (key: 'personal_care', label: 'Personal'),
    (key: 'monsoon', label: 'Monsoon'),
    (key: 'bakery', label: 'Bakery'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.gutter,
          vertical: v360.spacing.xs + 2,
        ),
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        separatorBuilder: (_, _) => SizedBox(width: v360.spacing.xs + 2),
        itemBuilder: (context, index) {
          final category = _categories[index];
          final active = category.key == selected;

          return Semantics(
            button: true,
            selected: active,
            label: category.label,
            excludeSemantics: true,
            child: V360Pressable(
              onTap: () {
                HapticFeedback.selectionClick();
                ref.read(inventoryFilterProvider.notifier).value =
                    category.key;
              },
              borderRadius: BorderRadius.circular(V360Radius.sm),
              child: Container(
                alignment: Alignment.center,
                padding: EdgeInsets.symmetric(horizontal: v360.spacing.md),
                decoration: BoxDecoration(
                  color: active ? v360.colors.ink : v360.colors.surface,
                  borderRadius: BorderRadius.circular(V360Radius.sm),
                  border: Border.all(
                    color: active ? v360.colors.ink : v360.colors.hairline,
                  ),
                ),
                child: Text(
                  category.label,
                  style: v360.text.caption
                      .copyWith(
                        color: active ? v360.colors.canvas : v360.colors.ink,
                      )
                      .weight(FontWeight.w600),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ItemRow extends ConsumerWidget {
  const _ItemRow({required this.item, required this.strings});

  final InventoryItem item;
  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final state = item.state(DateTime.now());

    final (Color tone, String label) = switch (state) {
      StockState.expired => (colors.danger, 'Expired'),
      StockState.out => (colors.danger, strings.outOfStock),
      StockState.expiringSoon => (colors.danger, 'Use today'),
      StockState.low => (colors.warning, strings.reorderNow),
      StockState.healthy => (colors.accent, strings.inStock),
    };
    final needsAction = state != StockState.healthy;

    // Fill relative to twice the reorder point, so a healthy item sits around
    // half rather than pinned at 100% and telling the vendor nothing.
    final ceiling = (item.reorderPoint * 2).clamp(1, double.infinity);
    final fill = (item.quantity.amount / ceiling).clamp(0.0, 1.0);

    return InkWell(
      onTap: () => _openSheet(context, ref),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          v360.spacing.gutter,
          v360.spacing.md,
          v360.spacing.gutter,
          needsAction ? v360.spacing.xs : v360.spacing.md,
        ),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        item.skuName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: v360.text.titleS.copyWith(color: colors.ink),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        children: <Widget>[
                          StatusMark(label: label, color: tone, dense: true),
                          Flexible(
                            child: Text(
                              '  ·  ${strings.reorderAt} '
                              '${item.reorderPoint.toStringAsFixed(0)} '
                              '${item.quantity.unit}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: v360.text.caption
                                  .copyWith(color: colors.inkMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: v360.spacing.md),
                Text(
                  item.quantity.display,
                  style: v360.text.titleM
                      .copyWith(color: colors.ink)
                      .weight(FontWeight.w700)
                      .narrow(86),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.sm),
            // The level against the reorder line, as a thin printed rule
            // rather than a rounded progress pill.
            SizedBox(
              height: 3,
              child: LinearProgressIndicator(
                value: fill,
                backgroundColor: colors.surfaceMuted,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),

            // The two things a shopkeeper does at a shelf that needs them,
            // without opening anything. Healthy rows stay quiet; their
            // adjustments live in the sheet a tap away.
            if (needsAction)
              Row(
                children: <Widget>[
                  if (item.quantity.amount > 0)
                    TextButton(
                      onPressed: () => _markSoldOut(context, ref),
                      child: const Text('Sold out'),
                    ),
                  TextButton(
                    onPressed: () =>
                        showSourcingSheet(context, itemId: item.id),
                    child: const Text('Compare suppliers'),
                  ),
                  const Spacer(),
                  V360Button.tonal(
                    label: '1-tap order',
                    size: V360ButtonSize.sm,
                    onPressed: () => _quickReorder(context, ref),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// Zero the shelf in one tap.
  ///
  /// Confirmed first, because it is destructive in the way that matters: it
  /// writes a sale for everything left, which lands in the day's takings and
  /// in every forecast built from them. Recorded as a sale rather than a
  /// silent adjustment precisely so the numbers stay honest -- stock that
  /// left the shelf is stock that left.
  Future<void> _markSoldOut(BuildContext context, WidgetRef ref) async {
    final remaining = item.quantity;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${item.skuName} sold out?'),
        content: Text(
          'This records the remaining ${remaining.display} as sold and takes '
          'the shelf to zero.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sold out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(repositoryProvider).recordMovement(
            itemId: item.id,
            qty: remaining.amount,
            movement: 'sale',
            source: 'manual',
          );
      ref
        ..invalidate(inventoryProvider)
        ..invalidate(dashboardProvider);

      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${item.skuName} marked sold out'),
          action: SnackBarAction(
            label: 'Order',
            onPressed: () => showSourcingSheet(context, itemId: item.id),
          ),
        ),
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

  Future<void> _quickReorder(BuildContext context, WidgetRef ref) async {
    try {
      final sourcing = await ref.read(marketplaceProvider).sourcing(item.id);
      if (sourcing.options.isEmpty) {
        if (context.mounted) {
          showSourcingSheet(context, itemId: item.id);
        }
        return;
      }
      final topOption = sourcing.options.first;
      final plan = PackQuantity.forShortfall(
        shortfall: sourcing.shortfall,
        packSize: topOption.packSize,
        unit: topOption.unit,
        moqPacks: topOption.moqPacks,
      );
      final cart = ref.read(cartProvider.notifier);
      if (cart.wouldReplace(topOption.supplierId)) {
        if (context.mounted) {
          showSourcingSheet(context, itemId: item.id);
        }
        return;
      }
      cart.add(
        CartLine(
          option: topOption,
          itemId: item.id,
          packs: plan.packs,
        ),
      );
      HapticFeedback.mediumImpact();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Added ${plan.packDisplay} to order (${topOption.supplierName})',
            ),
            action: SnackBarAction(
              label: 'View Cart',
              onPressed: () => context.go('/cart'),
            ),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        showSourcingSheet(context, itemId: item.id);
      }
    }
  }

  void _openSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _QuickEditSheet(item: item),
    );
  }
}

/// Fast restock / sale / waste logging without leaving the list.
class _QuickEditSheet extends ConsumerStatefulWidget {
  const _QuickEditSheet({required this.item});

  final InventoryItem item;

  @override
  ConsumerState<_QuickEditSheet> createState() => _QuickEditSheetState();
}

class _QuickEditSheetState extends ConsumerState<_QuickEditSheet> {
  double _qty = 1;
  String _movement = 'sale';
  bool _saving = false;

  Future<void> _save() async {
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);
    await ref.read(repositoryProvider).recordMovement(
          itemId: widget.item.id,
          qty: _qty,
          movement: _movement,
        );
    ref.read(syncProvider.notifier).refresh();
    ref.invalidate(inventoryProvider);
    ref.invalidate(dashboardProvider);

    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      padding: EdgeInsets.all(v360.spacing.xxl),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(V360Radius.xl)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.hairline,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            SizedBox(height: v360.spacing.xl),
            Text(
              widget.item.skuName,
              style: v360.text.titleL.copyWith(color: colors.ink),
            ),
            Text(
              'In stock: ${widget.item.quantity.display}',
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
            SizedBox(height: v360.spacing.xl),

            V360Segmented<String>(
              value: _movement,
              onChanged: (value) => setState(() => _movement = value),
              segments: const <V360Segment<String>>[
                V360Segment<String>(value: 'sale', label: 'Sold'),
                V360Segment<String>(value: 'restock', label: 'Restocked'),
                V360Segment<String>(value: 'wastage', label: 'Wasted'),
              ],
            ),
            SizedBox(height: v360.spacing.xl),

            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                V360IconButton(
                  icon: Icons.remove_rounded,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _qty = (_qty - 1).clamp(1, 9999));
                  },
                  semanticLabel: 'Decrease',
                ),
                SizedBox(width: v360.spacing.xl),
                Column(
                  children: <Widget>[
                    Text(
                      _qty.toStringAsFixed(0),
                      style: v360.text.figure.copyWith(color: colors.ink),
                    ),
                    Text(
                      widget.item.quantity.unit,
                      style: v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
                SizedBox(width: v360.spacing.xl),
                V360IconButton(
                  icon: Icons.add_rounded,
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() => _qty += 1);
                  },
                  semanticLabel: 'Increase',
                ),
              ],
            ),
            SizedBox(height: v360.spacing.xl),

            V360Button.primary(
              label: 'Save',
              expand: true,
              loading: _saving,
              onPressed: _save,
            ),
          ],
        ),
      ),
    );
  }
}

class _InventorySearchBar extends ConsumerStatefulWidget {
  const _InventorySearchBar();

  @override
  ConsumerState<_InventorySearchBar> createState() => _InventorySearchBarState();
}

class _InventorySearchBarState extends ConsumerState<_InventorySearchBar> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: ref.read(inventorySearchQueryProvider) ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final query = ref.watch(inventorySearchQueryProvider);

    // White on the band, with no border: the band is the frame.
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: v360.colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.md),
      ),
      padding: EdgeInsets.symmetric(horizontal: v360.spacing.md),
      child: Row(
        children: <Widget>[
          Icon(Icons.search_rounded, size: 18, color: v360.colors.inkSubtle),
          SizedBox(width: v360.spacing.sm),
          Expanded(
            child: TextField(
              controller: _controller,
              style: v360.text.body.copyWith(color: v360.colors.ink),
              decoration: InputDecoration(
                hintText: 'Search stock: milk, atta…',
                hintStyle:
                    v360.text.body.copyWith(color: v360.colors.inkSubtle),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (val) {
                ref.read(inventorySearchQueryProvider.notifier).value =
                    val.trim().isEmpty ? null : val.trim();
              },
            ),
          ),
          if (query != null && query.isNotEmpty)
            GestureDetector(
              onTap: () {
                _controller.clear();
                ref.read(inventorySearchQueryProvider.notifier).value = null;
              },
              child: Icon(Icons.close_rounded,
                  size: 16, color: v360.colors.inkSubtle),
            ),
        ],
      ),
    );
  }
}
