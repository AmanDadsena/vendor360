import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';

/// Who a shop can buy from, and who it already does.
///
/// Connecting is one explicit, revocable tap that grants demand visibility —
/// scoped to the aisles that wholesaler actually stocks, and frozen at that
/// moment. The dialog says so in those words, because consent a vendor did
/// not understand is not consent.
class DistributorsScreen extends ConsumerWidget {
  const DistributorsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final all = ref.watch(distributorsProvider);
    final connections = ref.watch(connectionsProvider);

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
          'Distributors',
          style: v360.text.titleM.copyWith(color: colors.ink),
        ),
      ),
      body: SafeArea(
        child: all.when(
          loading: () => ListView.builder(
            padding: EdgeInsets.all(v360.spacing.gutter),
            itemCount: 4,
            itemBuilder: (_, __) => Padding(
              padding: EdgeInsets.only(bottom: v360.spacing.md),
              child: const V360Skeleton(height: 120),
            ),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load distributors',
            body: '$error',
          ),
          data: (list) {
            final linked = connections.value ?? const <Connection>[];
            final byId = <String, Connection>{
              for (final c in linked) c.supplierId: c,
            };
            final connected = list.where((s) => s.connected).toList();
            final rest = list.where((s) => !s.connected).toList();

            return RefreshIndicator(
              color: colors.accent,
              onRefresh: () async {
                HapticFeedback.lightImpact();
                ref
                  ..invalidate(distributorsProvider)
                  ..invalidate(connectionsProvider);
              },
              child: ListView(
                padding: EdgeInsets.fromLTRB(
                  v360.spacing.gutter,
                  0,
                  v360.spacing.gutter,
                  v360.spacing.x5,
                ),
                children: <Widget>[
                  if (connected.isNotEmpty) ...<Widget>[
                    SectionLabel('You buy from'),
                    SizedBox(height: v360.spacing.sm),
                    for (final supplier in connected)
                      Padding(
                        padding: EdgeInsets.only(bottom: v360.spacing.md),
                        child: _SupplierCardView(
                          supplier: supplier,
                          connection: byId[supplier.id],
                        ),
                      ),
                    SizedBox(height: v360.spacing.lg),
                  ],
                  if (rest.isNotEmpty) ...<Widget>[
                    SectionLabel('Near you'),
                    SizedBox(height: v360.spacing.sm),
                    for (final supplier in rest)
                      Padding(
                        padding: EdgeInsets.only(bottom: v360.spacing.md),
                        child: _SupplierCardView(supplier: supplier),
                      ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SupplierCardView extends ConsumerWidget {
  const _SupplierCardView({required this.supplier, this.connection});

  final SupplierCard supplier;
  final Connection? connection;

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
                      supplier.name,
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                    SizedBox(height: 2),
                    Text(
                      <String>[
                        supplier.locality,
                        if (supplier.distanceKm != null)
                          '${supplier.distanceKm!.toStringAsFixed(1)} km',
                        '${supplier.leadDays}-day delivery',
                      ].join(' · '),
                      style: v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              if (supplier.isMandi)
                const OrderStatusChip(
                  label: 'Mandi',
                  tone: OrderTone.draft,
                  dense: true,
                ),
            ],
          ),

          SizedBox(height: v360.spacing.md),

          Wrap(
            spacing: v360.spacing.xs,
            runSpacing: v360.spacing.xs,
            children: <Widget>[
              _Fact(
                icon: Icons.inventory_2_outlined,
                text: '${supplier.catalogSize} items',
              ),
              if (supplier.fillRate != null)
                _Fact(
                  icon: Icons.check_circle_outline_rounded,
                  text: 'fills ${(supplier.fillRate! * 100).round()}%',
                ),
              if (supplier.minOrderValue > 0)
                _Fact(
                  icon: Icons.currency_rupee_rounded,
                  text: '${supplier.minOrderValue.round()} minimum',
                ),
            ],
          ),

          if (connection != null) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(v360.spacing.md),
              decoration: BoxDecoration(
                color: colors.surfaceMuted,
                borderRadius: BorderRadius.circular(V360Radius.md),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    connection!.termsLabel,
                    style: v360.text.label.copyWith(color: colors.inkMuted),
                  ),
                  SizedBox(height: 2),
                  Text(
                    connection!.sharesDemand
                        ? 'They can see what you will need in '
                            '${_aisles(connection!.scopeCategories)}'
                        : 'They cannot see your stock or forecasts',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                  if (connection!.outstanding > 0) ...<Widget>[
                    SizedBox(height: v360.spacing.xs),
                    Text(
                      '₹${connection!.outstanding.round()} outstanding',
                      style: v360.text.label.copyWith(color: colors.warningText),
                    ),
                  ],
                ],
              ),
            ),
          ],

          SizedBox(height: v360.spacing.md),
          Row(
            children: <Widget>[
              if (supplier.phone != null)
                Padding(
                  padding: EdgeInsets.only(right: v360.spacing.sm),
                  child: V360IconButton(
                    icon: Icons.phone_outlined,
                    semanticLabel: 'Call ${supplier.name}',
                    onPressed: () => _copy(context, supplier.phone!),
                  ),
                ),
              Expanded(
                child: supplier.connected
                    ? V360Button.ghost(
                        label: 'Stop buying from them',
                        expand: true,
                        onPressed: () => _disconnect(context, ref),
                      )
                    : V360Button.primary(
                        label: 'Connect',
                        expand: true,
                        onPressed: () => _connect(context, ref),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _aisles(List<String> categories) {
    if (categories.isEmpty) return 'nothing yet';
    final pretty = categories.map((c) => c.replaceAll('_', ' ')).toList();
    if (pretty.length == 1) return pretty.first;
    if (pretty.length == 2) return '${pretty[0]} and ${pretty[1]}';
    return '${pretty.take(pretty.length - 1).join(', ')} and ${pretty.last}';
  }

  void _copy(BuildContext context, String phone) {
    Clipboard.setData(ClipboardData(text: phone));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$phone copied')),
    );
  }

  Future<void> _connect(BuildContext context, WidgetRef ref) async {
    final choice = await showDialog<({bool share, int terms})>(
      context: context,
      builder: (_) => _ConnectDialog(supplier: supplier),
    );
    if (choice == null) return;

    try {
      await ref.read(marketplaceProvider).connect(
            supplier.id,
            sharesDemand: choice.share,
            creditTermsDays: choice.terms,
          );
      ref
        ..invalidate(distributorsProvider)
        ..invalidate(connectionsProvider);

      if (!context.mounted) return;
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Connected to ${supplier.name}')),
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

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Stop buying from ${supplier.name}?'),
        content: const Text(
          'They will no longer see what you need. Your past orders and any '
          'money owed both stay on record.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(marketplaceProvider).disconnect(supplier.id);
      ref
        ..invalidate(distributorsProvider)
        ..invalidate(connectionsProvider);
    } catch (error) {
      if (!context.mounted) return;
      // The server refuses while an order is still in flight, and says why.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    }
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: v360.spacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 12, color: colors.inkMuted),
          SizedBox(width: v360.spacing.xs),
          Text(text, style: v360.text.label.copyWith(color: colors.inkMuted)),
        ],
      ),
    );
  }
}

/// The consent decision, stated in words a shopkeeper can act on.
class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog({required this.supplier});

  final SupplierCard supplier;

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  bool _share = true;
  int _terms = 0;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final aisles = widget.supplier.categories
        .map((c) => c.replaceAll('_', ' '))
        .join(', ');

    return AlertDialog(
      title: Text('Connect to ${widget.supplier.name}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _share,
            onChanged: (v) => setState(() => _share = v),
            title: const Text('Let them see what you will need'),
            subtitle: Text(
              aisles.isEmpty
                  ? 'They have no price list yet, so nothing is shared.'
                  : 'Only $aisles — the aisles they stock today. Adding to '
                      'their price list later will not widen this.',
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
          ),
          SizedBox(height: v360.spacing.md),
          Text(
            'Payment terms',
            style: v360.text.label.copyWith(color: colors.inkMuted),
          ),
          SizedBox(height: v360.spacing.sm),
          Wrap(
            spacing: v360.spacing.sm,
            children: <Widget>[
              for (final days in <int>[0, 7, 14, 21])
                ChoiceChip(
                  label: Text(days == 0 ? 'Cash' : '$days days'),
                  selected: _terms == days,
                  onSelected: (_) => setState(() => _terms = days),
                ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop((share: _share, terms: _terms)),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}
