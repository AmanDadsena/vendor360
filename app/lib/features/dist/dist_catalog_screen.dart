import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';

/// The price list.
///
/// A wholesaler with no catalogue is invisible to every sourcing screen in the
/// product, so the fastest possible path from "nothing" to "listed" matters
/// more here than anywhere else — hence paste-a-spreadsheet as a first-class
/// option rather than a settings-menu afterthought.
class DistCatalogScreen extends ConsumerWidget {
  const DistCatalogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final catalog = ref.watch(distCatalogProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text('Catalog', style: v360.text.titleM.copyWith(color: colors.ink)),
        actions: <Widget>[
          IconButton(
            icon: const Icon(Icons.upload_file_rounded),
            tooltip: 'Paste a price list',
            onPressed: () => _import(context, ref),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: colors.actionFill,
        foregroundColor: colors.onActionFill,
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add item'),
      ),
      body: SafeArea(
        child: catalog.when(
          loading: () => ListView.builder(
            padding: EdgeInsets.all(v360.spacing.gutter),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: const V360Skeleton(height: 80),
            ),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load your catalog',
            body: '$error',
          ),
          data: (entries) => entries.isEmpty
              ? EmptyState(
                  icon: Icons.sell_outlined,
                  title: 'No price list yet',
                  body: 'Shops can only order what you have listed. Paste '
                      'your existing price list and you are trading in a '
                      'minute.',
                  action: V360Button.primary(
                    label: 'Paste a price list',
                    onPressed: () => _import(context, ref),
                  ),
                )
              : RefreshIndicator(
                  color: colors.accent,
                  onRefresh: () async {
                    HapticFeedback.lightImpact();
                    ref.invalidate(distCatalogProvider);
                  },
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      v360.spacing.gutter,
                      0,
                      v360.spacing.gutter,
                      100,
                    ),
                    children: <Widget>[
                      for (final entry in entries)
                        Padding(
                          padding: EdgeInsets.only(bottom: v360.spacing.md),
                          child: _EntryCard(entry: entry),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  void _import(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ImportSheet(),
    );
  }

  void _add(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddSheet(),
    );
  }
}

class _EntryCard extends ConsumerWidget {
  const _EntryCard({required this.entry});

  final CatalogEntry entry;

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
                  entry.skuName,
                  style: v360.text.bodyStrong.copyWith(color: colors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  '${entry.packLabel}'
                  '${entry.moqPacks > 1 ? ' · min ${entry.moqPacks}' : ''}'
                  '${entry.availablePacks == null ? '' : ' · ${entry.availablePacks!.round()} in stock'}',
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
          SizedBox(width: v360.spacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                entry.packMoney.display,
                style: v360.text.titleS.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                '₹${entry.unitPrice.toStringAsFixed(2)}/${entry.unit}',
                style: v360.text.label.copyWith(color: colors.inkSubtle),
              ),
              SizedBox(height: v360.spacing.xs),
              V360IconButton(
                icon: Icons.edit_outlined,
                size: 34,
                semanticLabel: 'Edit ${entry.skuName}',
                onPressed: () => _edit(context, ref),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final controller =
        TextEditingController(text: entry.packPrice.toStringAsFixed(0));

    final price = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(entry.skuName),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Price per ${entry.packLabel}',
            prefixText: '₹ ',
            border: const OutlineInputBorder(),
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
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (price == null || price <= 0) return;

    await ref
        .read(marketplaceProvider)
        .updateCatalogEntry(entry.id, packPrice: price);
    ref.invalidate(distCatalogProvider);
  }
}

/// Paste-a-spreadsheet import, preview first.
class _ImportSheet extends ConsumerStatefulWidget {
  const _ImportSheet();

  @override
  ConsumerState<_ImportSheet> createState() => _ImportSheetState();
}

class _ImportSheetState extends ConsumerState<_ImportSheet> {
  final TextEditingController _csv = TextEditingController();
  PriceListPreview? _preview;
  bool _busy = false;

  @override
  void dispose() {
    _csv.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        child: ListView(
          controller: controller,
          padding: EdgeInsets.all(v360.spacing.gutter),
          children: <Widget>[
            Text(
              'Paste your price list',
              style: v360.text.titleM.copyWith(color: colors.ink),
            ),
            SizedBox(height: v360.spacing.xs),
            Text(
              'One row per item. Column names are matched loosely — "rate", '
              '"price" and "pack price" all work, and rupee signs and commas '
              'are fine.',
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
            SizedBox(height: v360.spacing.md),
            TextField(
              controller: _csv,
              maxLines: 7,
              style: v360.text.code.copyWith(color: colors.ink),
              decoration: InputDecoration(
                hintText: 'item,packing,rate,moq\nMilk,12,276,1',
                filled: true,
                fillColor: colors.surfaceMuted,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(V360Radius.md),
                  borderSide: BorderSide(color: colors.hairline),
                ),
              ),
            ),
            SizedBox(height: v360.spacing.md),

            if (_preview != null) ...<Widget>[
              _PreviewSummary(preview: _preview!),
              SizedBox(height: v360.spacing.md),
              for (final row in _preview!.rows)
                _PreviewRow(row: row),
              SizedBox(height: v360.spacing.md),
            ],

            Row(
              children: <Widget>[
                Expanded(
                  child: V360Button.secondary(
                    label: 'Check it',
                    expand: true,
                    loading: _busy && _preview == null,
                    onPressed: _busy ? null : () => _run(commit: false),
                  ),
                ),
                if (_preview != null && _preview!.valid > 0) ...<Widget>[
                  SizedBox(width: v360.spacing.sm),
                  Expanded(
                    child: V360Button.primary(
                      label: 'Import ${_preview!.valid}',
                      expand: true,
                      loading: _busy,
                      onPressed: _busy ? null : () => _run(commit: true),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _run({required bool commit}) async {
    if (_csv.text.trim().isEmpty) return;
    setState(() => _busy = true);

    try {
      final result = await ref
          .read(marketplaceProvider)
          .importPriceList(_csv.text, commit: commit);

      if (!mounted) return;
      if (commit) {
        ref.invalidate(distCatalogProvider);
        Navigator.of(context).pop();
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.willCreate} added, ${result.willUpdate} updated',
            ),
          ),
        );
      } else {
        setState(() => _preview = result);
      }
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

class _PreviewSummary extends StatelessWidget {
  const _PreviewSummary({required this.preview});

  final PriceListPreview preview;

  @override
  Widget build(BuildContext context) {
    return V360Banner(
      icon: preview.invalid > 0
          ? Icons.warning_amber_rounded
          : Icons.check_circle_outline_rounded,
      tone: preview.invalid > 0
          ? V360BannerTone.warning
          : V360BannerTone.success,
      title: '${preview.willCreate} new, ${preview.willUpdate} updated'
          '${preview.invalid > 0 ? ', ${preview.invalid} skipped' : ''}',
      body: preview.invalid > 0
          ? 'Nothing is saved until you import. The skipped rows are marked '
              'below — fix them and paste again, or import the rest.'
          : 'Nothing has been saved yet.',
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.row});

  final PriceListRow row;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: v360.spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            row.ok ? Icons.check_rounded : Icons.close_rounded,
            size: 15,
            color: row.ok ? colors.accentText : colors.dangerText,
          ),
          SizedBox(width: v360.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  row.skuName.isEmpty ? 'Row ${row.row}' : row.skuName,
                  style: v360.text.body.copyWith(color: colors.ink),
                ),
                if (row.errors.isNotEmpty)
                  Text(
                    row.errors.join(' · '),
                    style: v360.text.label.copyWith(color: colors.dangerText),
                  ),
              ],
            ),
          ),
          if (row.ok)
            Text(
              '₹${row.packPrice.round()}',
              style: v360.text.label.copyWith(color: colors.inkMuted),
            ),
        ],
      ),
    );
  }
}

class _AddSheet extends ConsumerStatefulWidget {
  const _AddSheet();

  @override
  ConsumerState<_AddSheet> createState() => _AddSheetState();
}

class _AddSheetState extends ConsumerState<_AddSheet> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _packSize = TextEditingController(text: '12');
  final TextEditingController _price = TextEditingController();
  String _category = 'staples';
  String _unit = 'pc';
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _packSize.dispose();
    _price.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        padding: EdgeInsets.all(v360.spacing.gutter),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Add an item',
              style: v360.text.titleM.copyWith(color: colors.ink),
            ),
            SizedBox(height: v360.spacing.md),
            TextField(
              controller: _name,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: v360.spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _packSize,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Units per case',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: v360.spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(
                      labelText: 'Unit',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'kg', child: Text('kg')),
                      DropdownMenuItem(value: 'l', child: Text('litre')),
                      DropdownMenuItem(value: 'pkt', child: Text('packet')),
                      DropdownMenuItem(value: 'pc', child: Text('piece')),
                      DropdownMenuItem(value: 'btl', child: Text('bottle')),
                    ],
                    onChanged: (v) => setState(() => _unit = v ?? 'pc'),
                  ),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Price per case',
                      prefixText: '₹ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                SizedBox(width: v360.spacing.sm),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _category,
                    decoration: const InputDecoration(
                      labelText: 'Aisle',
                      border: OutlineInputBorder(),
                    ),
                    items: const <DropdownMenuItem<String>>[
                      DropdownMenuItem(value: 'staples', child: Text('Staples')),
                      DropdownMenuItem(value: 'dairy', child: Text('Dairy')),
                      DropdownMenuItem(value: 'produce', child: Text('Produce')),
                      DropdownMenuItem(value: 'snacks', child: Text('Snacks')),
                      DropdownMenuItem(
                          value: 'beverages', child: Text('Beverages')),
                      DropdownMenuItem(value: 'bakery', child: Text('Bakery')),
                      DropdownMenuItem(value: 'sweets', child: Text('Sweets')),
                      DropdownMenuItem(
                          value: 'personal_care', child: Text('Personal care')),
                      DropdownMenuItem(
                          value: 'household', child: Text('Household')),
                      DropdownMenuItem(value: 'monsoon', child: Text('Monsoon')),
                    ],
                    onChanged: (v) => setState(() => _category = v ?? 'staples'),
                  ),
                ),
              ],
            ),
            SizedBox(height: v360.spacing.lg),
            V360Button.primary(
              label: 'Add to catalog',
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _save,
            ),
            SizedBox(height: v360.spacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final packSize = double.tryParse(_packSize.text.trim()) ?? 0;
    final price = double.tryParse(_price.text.trim()) ?? 0;

    if (name.isEmpty || packSize <= 0 || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, case size and price are needed')),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      await ref.read(marketplaceProvider).addCatalogEntry(
            skuName: name,
            category: _category,
            unit: _unit,
            packSize: packSize,
            packPrice: price,
          );
      ref.invalidate(distCatalogProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    }
  }
}
