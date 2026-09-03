import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';

/// Hyperlocal demand intensity across the city.
///
/// From the Future Scope's zero-logistics mediator track: a vendor can see
/// whether their shortage is local or general, and a distributor can see where
/// a category is moving. Cells only appear once at least three stores
/// contribute, so no individual shop's sales are exposed to a competitor.
class HeatmapScreen extends ConsumerWidget {
  const HeatmapScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final data = ref.watch(heatmapProvider);
    final category = ref.watch(heatmapCategoryProvider);

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
          'Demand map',
          style: v360.text.titleM.copyWith(color: colors.ink),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter,
            0,
            v360.spacing.gutter,
            v360.spacing.x5,
          ),
          children: <Widget>[
            Text(
              'Where demand is concentrated across Pune, and which suppliers '
              'are nearest to it.',
              style: v360.text.body.copyWith(color: colors.inkMuted),
            ),
            SizedBox(height: v360.spacing.lg),

            _CategoryPicker(selected: category),
            SizedBox(height: v360.spacing.lg),

            data.when(
              loading: () => const V360Skeleton(height: 320, radius: V360Radius.lg),
              error: (error, _) => EmptyState(
                icon: Icons.map_outlined,
                title: 'Map unavailable',
                body: '$error',
              ),
              data: (result) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  V360Reveal(
                    child: DemandHeatmap(
                      cells: result.cells,
                      suppliers: result.suppliers,
                      height: 340,
                      onCellTap: (cell) => _showCell(context, cell),
                    ),
                  ),
                  SizedBox(height: v360.spacing.lg),
                  const HeatmapLegend(),
                  SizedBox(height: v360.spacing.xl),

                  V360Reveal(
                    delayIndex: 1,
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: StatTile(
                            label: 'Active zones',
                            value: '${result.cells.length}',
                            caption: 'with 3+ contributing stores',
                            icon: Icons.grid_view_rounded,
                            compact: true,
                          ),
                        ),
                        SizedBox(width: v360.spacing.md),
                        Expanded(
                          child: StatTile(
                            label: 'Suppliers',
                            value: '${result.suppliers.length}',
                            caption: 'mandis and distributors',
                            icon: Icons.local_shipping_outlined,
                            compact: true,
                          ),
                        ),
                      ],
                    ),
                  ),

                  if (result.suppressed > 0) ...<Widget>[
                    SizedBox(height: v360.spacing.lg),
                    V360Banner(
                      icon: Icons.lock_outline_rounded,
                      title: '${result.suppressed} zones hidden',
                      body: 'A zone is only shown once at least three stores '
                          'contribute to it, so no single shop can be '
                          'identified from the map.',
                    ),
                  ],

                  SizedBox(height: v360.spacing.xl),
                  const SectionLabel('Nearest suppliers'),
                  SizedBox(height: v360.spacing.sm),
                  for (var i = 0; i < result.suppliers.length; i++)
                    V360Reveal(
                      delayIndex: i,
                      child: _SupplierRow(pin: result.suppliers[i]),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCell(BuildContext context, HeatCell cell) {
    final v360 = context.v360;
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: v360.colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.all(v360.spacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              cell.topSku ?? 'This zone',
              style: v360.text.titleL.copyWith(color: v360.colors.ink),
            ),
            SizedBox(height: v360.spacing.xs),
            Text(
              '${cell.lat.toStringAsFixed(3)}, ${cell.lon.toStringAsFixed(3)}',
              style: v360.text.caption.copyWith(color: v360.colors.inkSubtle),
            ),
            SizedBox(height: v360.spacing.xl),
            Row(
              children: <Widget>[
                Expanded(
                  child: StatTile(
                    label: 'Units sold',
                    value: cell.demandQty.toStringAsFixed(0),
                    caption: 'last 30 days',
                    compact: true,
                  ),
                ),
                SizedBox(width: v360.spacing.md),
                Expanded(
                  child: StatTile(
                    label: 'Stores',
                    value: '${cell.vendorCount}',
                    caption: cell.shortageCount > 0
                        ? '${cell.shortageCount} need restocking'
                        : 'all well stocked',
                    compact: true,
                  ),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.xl),
          ],
        ),
      ),
    );
  }
}

class _CategoryPicker extends ConsumerWidget {
  const _CategoryPicker({required this.selected});

  final String? selected;

  static const List<({String? key, String label})> _options = <({String? key, String label})>[
    (key: null, label: 'All'),
    (key: 'dairy', label: 'Dairy'),
    (key: 'produce', label: 'Produce'),
    (key: 'staples', label: 'Staples'),
    (key: 'snacks', label: 'Snacks'),
    (key: 'sweets', label: 'Sweets'),
    (key: 'monsoon', label: 'Monsoon'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _options.length,
        separatorBuilder: (_, _) => SizedBox(width: v360.spacing.sm),
        itemBuilder: (context, index) {
          final option = _options[index];
          final active = option.key == selected;
          return V360Pressable(
            onTap: () {
              HapticFeedback.selectionClick();
              ref.read(heatmapCategoryProvider.notifier).value = option.key;
            },
            borderRadius: BorderRadius.circular(V360Radius.pill),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: v360.spacing.lg,
                vertical: v360.spacing.sm,
              ),
              decoration: BoxDecoration(
                color: active ? v360.colors.accent : v360.colors.surface,
                borderRadius: BorderRadius.circular(V360Radius.pill),
                border: Border.all(
                  color: active ? v360.colors.accent : v360.colors.hairline,
                ),
              ),
              child: Text(
                option.label,
                style: v360.text.caption.copyWith(
                  color: active ? v360.colors.onFill : v360.colors.inkMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SupplierRow extends StatelessWidget {
  const _SupplierRow({required this.pin});

  final SupplierPin pin;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final isMandi = pin.kind == 'mandi';

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.sm),
      child: V360Card(
        padding: EdgeInsets.all(v360.spacing.lg),
        child: Row(
          children: <Widget>[
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isMandi ? colors.voiceSurface : colors.accentSurface,
                borderRadius: BorderRadius.circular(V360Radius.sm),
              ),
              child: Icon(
                isMandi ? Icons.storefront_outlined : Icons.local_shipping_outlined,
                size: 18,
                color: isMandi ? colors.voiceText : colors.accentText,
              ),
            ),
            SizedBox(width: v360.spacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    pin.name,
                    style: v360.text.bodyStrong.copyWith(color: colors.ink),
                  ),
                  Text(
                    isMandi ? 'Wholesale mandi' : 'Distributor',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ),
            StatusPill(
              label: '${pin.leadDays}-day lead',
              tone: pin.leadDays <= 1 ? PillTone.healthy : PillTone.neutral,
              icon: Icons.schedule_rounded,
              dense: true,
            ),
          ],
        ),
      ),
    );
  }
}
