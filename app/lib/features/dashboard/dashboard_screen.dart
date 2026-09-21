import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/models.dart';
import '../alerts/alerts_sheet.dart';
import '../alerts/live_dot.dart';
import '../orders/sourcing_sheet.dart';

/// Home — the two-second read on "how is my store doing right now".
///
/// The top of the phone is the front of the pack: today's money printed
/// large on the teal band, qualified by a ruled strip of the facts behind
/// it. Below, on white, only what asks for action — the one heads-up worth
/// acting on, the items about to run out with a way to reorder each, and
/// what is about to expire. Then the places to go.
///
/// Logging a sale is the highest-frequency action in the product, so it is
/// the marigold disc in the bottom bar, reachable from every tab, rather
/// than another tile here (UI/UX 5.1).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(dashboardProvider);

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await ref.read(syncProvider.notifier).flush();
          ref
            ..invalidate(dashboardProvider)
            ..invalidate(runningOutProvider);
        },
        color: v360.colors.accent,
        child: snapshot.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, _) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) => _DashboardBody(data: data, strings: s),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data, required this.strings});

  final DashboardSnapshot data;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final gap = SizedBox(height: v360.spacing.x3);

    return CustomScrollView(
      // Always scrollable so pull-to-refresh works even when the content fits.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(child: _Front(data: data, strings: strings)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter,
            v360.spacing.xl,
            v360.spacing.gutter,
            v360.spacing.x5,
          ),
          sliver: SliverList.list(
            children: <Widget>[
              if (data.topSignal != null) ...<Widget>[
                SignalBanner(
                  title: data.topSignal!,
                  detail: data.topSignalDetail ?? '',
                  onTap: () => context.go('/forecast'),
                ),
                SizedBox(height: v360.spacing.xxl),
              ],
              _RunningOut(strings: strings, lowCount: data.lowStockCount),
              if (data.expiringSoonCount > 0) ...<Widget>[
                SizedBox(height: v360.spacing.md),
                _ExpiringRow(data: data, strings: strings),
              ],
              gap,
              SectionLabel(strings.quickActions),
              SizedBox(height: v360.spacing.md),
              _Places(strings: strings, data: data),
            ],
          ),
        ),
      ],
    );
  }
}

/// The band: who, today's money, and the ruled facts behind it.
class _Front extends ConsumerWidget {
  const _Front({required this.data, required this.strings});

  final DashboardSnapshot data;
  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final sync = ref.watch(syncProvider);
    final vendor = data.vendor;
    final quiet = data.todayTransactionCount == 0;

    return PackHeader(
      title: vendor.storeName,
      subtitle: vendor.locality ?? vendor.city,
      actions: <Widget>[
        // Sync says whether *your* writes have landed; live says whether you
        // are being told about anyone else's. Adjacent because they answer
        // the same question — how current is this screen.
        SyncBadge(queued: sync.queued, syncing: sync.syncing),
        const LiveDot(onBand: true),
        AlertBell(onBand: true, onTap: () => showAlerts(context)),
        V360IconButton(
          icon: v360.isDark
              ? Icons.light_mode_outlined
              : Icons.dark_mode_outlined,
          color: colors.onBand,
          onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          semanticLabel: 'Switch theme',
        ),
      ],
      figure: RollingNumber(
        value: data.todaySalesValue.rupees,
        // Money.display carries the rupee symbol and the lakh grouping;
        // passing the raw number would render ₹12012.0 on the most-read
        // figure in the product.
        format: (_) => data.todaySalesValue.display,
        style: v360.text.display.copyWith(color: colors.onBand),
      ),
      figureCaption: quiet ? strings.noSalesYet : strings.todaySales,
      facts: <PackFact>[
        // Labels in one case: the strip reads as three facts, not three
        // headings. A no-op for Devanagari, which has no case.
        PackFact('${data.todayTransactionCount}', strings.entries),
        PackFact(data.weekSalesValue.display, strings.thisWeek.toLowerCase()),
        PackFact(
          data.healthScore == null ? '—' : '${data.healthScore!.round()}',
          strings.healthScore.toLowerCase(),
          onTap: () => context.go('/health'),
        ),
      ],
    );
  }
}

/// The items closest to running out, each with a way to reorder it.
class _RunningOut extends ConsumerWidget {
  const _RunningOut({required this.strings, required this.lowCount});

  final Strings strings;
  final int lowCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final items = ref.watch(runningOutProvider);
    // Counted from the same read the rows come from, so the header can never
    // say three over four rows.
    final count = items.value?.length ?? lowCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SectionLabel(
          count > 0 ? '${strings.runningOut} · $count' : strings.runningOut,
          action: count > 0
              ? TextButton(
                  onPressed: () {
                    ref.read(lowOnlyProvider.notifier).value = true;
                    context.go('/inventory');
                  },
                  child: Text(strings.seeAll),
                )
              : null,
        ),
        SizedBox(height: v360.spacing.sm),
        items.when(
          loading: () => const V360Skeleton(height: 132),
          error: (_, _) => const SizedBox.shrink(),
          data: (list) => list.isEmpty
              ? Padding(
                  padding: EdgeInsets.symmetric(vertical: v360.spacing.sm),
                  child: StatusMark(
                    label: strings.allAboveReorder,
                    color: colors.accent,
                    emphasis: false,
                  ),
                )
              : V360Card(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: <Widget>[
                      for (var i = 0; i < list.length && i < 4; i++) ...<Widget>[
                        if (i > 0) Divider(indent: v360.spacing.lg),
                        _RunningOutRow(item: list[i], strings: strings),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

class _RunningOutRow extends StatelessWidget {
  const _RunningOutRow({required this.item, required this.strings});

  final InventoryItem item;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final out = item.isOut;
    final unit = item.quantity.unit;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        v360.spacing.lg,
        v360.spacing.md,
        v360.spacing.md,
        v360.spacing.md,
      ),
      child: Row(
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
                    StatusMark(
                      label: out
                          ? strings.outOfStock
                          : '${item.quantity.display} ${strings.left}',
                      color: out ? colors.danger : colors.warning,
                      dense: true,
                    ),
                    Flexible(
                      child: Text(
                        '  ·  ${strings.reorderAt} '
                        '${item.reorderPoint.toStringAsFixed(0)} $unit',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            v360.text.caption.copyWith(color: colors.inkMuted),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          SizedBox(width: v360.spacing.sm),
          V360Button.tonal(
            label: strings.reorder,
            size: V360ButtonSize.md,
            onPressed: () => showSourcingSheet(context, itemId: item.id),
          ),
        ],
      ),
    );
  }
}

/// What is about to expire, and what it is worth — one ruled line.
class _ExpiringRow extends StatelessWidget {
  const _ExpiringRow({required this.data, required this.strings});

  final DashboardSnapshot data;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      onTap: () => context.go('/expiry'),
      semanticLabel: '${data.expiringSoonCount} ${strings.expiringSoonWindow}, '
          '${data.valueAtRisk.display} ${strings.atRisk}',
      padding: EdgeInsets.symmetric(
        horizontal: v360.spacing.lg,
        vertical: v360.spacing.md,
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.hourglass_bottom_rounded, size: 20, color: colors.warning),
          SizedBox(width: v360.spacing.md),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: <InlineSpan>[
                  TextSpan(
                    text: '${data.expiringSoonCount} ',
                    style: v360.text.bodyStrong.weight(FontWeight.w700),
                  ),
                  TextSpan(text: '${strings.expiringSoonWindow} · '),
                  TextSpan(
                    text: data.valueAtRisk.display,
                    // Still sellable at a discount, so attention, not loss.
                    style: v360.text.bodyStrong
                        .copyWith(color: colors.warningText),
                  ),
                  TextSpan(text: ' ${strings.atRisk}'),
                ],
              ),
              style: v360.text.body.copyWith(color: colors.ink),
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.inkSubtle),
        ],
      ),
    );
  }
}

/// The places to go, as a ruled grid — the back-panel table of a pack, not
/// a wrap of pill chips.
class _Places extends StatelessWidget {
  const _Places({required this.strings, required this.data});

  final Strings strings;
  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;

    final places = <({IconData icon, String label, String route, int? badge})>[
      (
        icon: Icons.document_scanner_outlined,
        label: strings.scanReceipt,
        route: '/receipt',
        badge: null,
      ),
      (
        icon: Icons.receipt_long_outlined,
        label: strings.orders,
        route: '/orders',
        badge: null,
      ),
      (
        icon: Icons.local_shipping_outlined,
        label: strings.suppliers,
        route: '/distributors',
        badge: null,
      ),
      (
        icon: Icons.map_outlined,
        label: strings.demandMap,
        route: '/heatmap',
        badge: null,
      ),
      (
        icon: Icons.groups_outlined,
        label: strings.bulkDeals,
        route: '/pools',
        badge: data.pendingPools > 0 ? data.pendingPools : null,
      ),
      (
        icon: Icons.query_stats_rounded,
        label: strings.accuracy,
        route: '/accuracy',
        badge: null,
      ),
    ];

    const columns = 3;
    final rows = <Widget>[];
    for (var r = 0; r * columns < places.length; r++) {
      if (r > 0) rows.add(const Divider());
      final cells = <Widget>[];
      for (var c = 0; c < columns; c++) {
        final i = r * columns + c;
        if (c > 0) cells.add(Container(width: 1, color: colors.hairline));
        cells.add(
          Expanded(
            child: i < places.length
                ? _Place(
                    icon: places[i].icon,
                    label: places[i].label,
                    badge: places[i].badge,
                    onTap: () => context.go(places[i].route),
                  )
                : const SizedBox.shrink(),
          ),
        );
      }
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: cells,
          ),
        ),
      );
    }

    return V360Card(
      padding: EdgeInsets.zero,
      child: Column(children: rows),
    );
  }
}

class _Place extends StatelessWidget {
  const _Place({
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Semantics(
      button: true,
      label: badge == null ? label : '$label, $badge new',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: v360.spacing.sm,
            vertical: v360.spacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                clipBehavior: Clip.none,
                children: <Widget>[
                  Icon(icon, size: 26, color: colors.accentText),
                  if (badge != null)
                    Positioned(
                      right: -12,
                      top: -6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: colors.warning,
                          borderRadius: BorderRadius.circular(V360Radius.sm),
                        ),
                        child: Text(
                          '$badge',
                          style: v360.text.label
                              .copyWith(color: colors.onVoice, fontSize: 10)
                              .weight(FontWeight.w700),
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(height: v360.spacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: v360.text.caption
                    .copyWith(color: colors.ink)
                    .weight(FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return ListView(
      padding: EdgeInsets.zero,
      children: <Widget>[
        // The band is drawn at once so the screen keeps its shape while the
        // numbers load, instead of flashing white and then filling with teal.
        Container(height: 260, color: v360.colors.band),
        Padding(
          padding: EdgeInsets.all(v360.spacing.gutter),
          child: Column(
            children: <Widget>[
              const V360Skeleton(height: 64),
              SizedBox(height: v360.spacing.lg),
              const V360Skeleton(height: 132),
              SizedBox(height: v360.spacing.lg),
              const V360Skeleton(height: 180),
            ],
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return ListView(
      padding: EdgeInsets.all(v360.spacing.gutter),
      children: <Widget>[
        SizedBox(height: v360.spacing.x5),
        EmptyState(
          icon: Icons.cloud_off_rounded,
          title: 'Could not load your dashboard',
          body: message,
          action: V360Button.primary(label: 'Retry', onPressed: onRetry),
        ),
      ],
    );
  }
}
