import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';
import '../../data/models.dart';

/// Home — the two-second read on "how is my store doing right now".
///
/// Ordered by what a vendor mid-transaction actually needs: today's money
/// first, then anything demanding action, then the forward-looking signal.
/// The voice button is reachable without navigating away, because logging a
/// sale is the highest-frequency action in the product (UI/UX 5.1).
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final snapshot = ref.watch(dashboardProvider);
    final sync = ref.watch(syncProvider);

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: RefreshIndicator(
        onRefresh: () async {
          HapticFeedback.lightImpact();
          await ref.read(syncProvider.notifier).flush();
          ref.invalidate(dashboardProvider);
        },
        color: v360.colors.accent,
        child: snapshot.when(
          loading: () => const _DashboardSkeleton(),
          error: (error, _) => _ErrorView(
            message: '$error',
            onRetry: () => ref.invalidate(dashboardProvider),
          ),
          data: (data) => _DashboardBody(data: data, strings: s, queued: sync.queued),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.data,
    required this.strings,
    required this.queued,
  });

  final DashboardSnapshot data;
  final Strings strings;
  final int queued;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final sync = ref.watch(syncProvider);

    return CustomScrollView(
      // Always scrollable so pull-to-refresh works even when the content fits.
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: <Widget>[
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              v360.spacing.gutter,
              v360.spacing.xxl,
              v360.spacing.gutter,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                V360Reveal(child: _Greeting(vendor: data.vendor, queued: queued, syncing: sync.syncing)),
                SizedBox(height: v360.spacing.xxl),

                // Today's money, given the most visual weight on the screen.
                V360Reveal(
                  delayIndex: 1,
                  child: _TodayCard(data: data, strings: strings),
                ),
                SizedBox(height: v360.spacing.lg),

                // Things demanding action.
                V360Reveal(
                  delayIndex: 2,
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: StatTile(
                          label: strings.lowStock,
                          value: '${data.lowStockCount}',
                          caption: data.lowStockCount == 0
                              ? 'Everything above its reorder point'
                              : 'below reorder point',
                          icon: Icons.trending_down_rounded,
                          tone: data.lowStockCount > 0 ? colors.warning : null,
                          compact: true,
                          onTap: () => context.go('/inventory'),
                        ),
                      ),
                      SizedBox(width: v360.spacing.md),
                      Expanded(
                        child: StatTile(
                          label: strings.expiringSoon,
                          value: '${data.expiringSoonCount}',
                          caption: '${data.valueAtRisk.display} ${strings.atRisk}',
                          icon: Icons.schedule_rounded,
                          tone: data.expiringSoonCount > 0 ? colors.danger : null,
                          compact: true,
                          onTap: () => context.go('/expiry'),
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: v360.spacing.lg),

                // The forward-looking signal — the thing that makes this
                // different from a ledger app.
                if (data.topSignal != null)
                  V360Reveal(
                    delayIndex: 3,
                    child: SignalBanner(
                      title: data.topSignal!,
                      detail: data.topSignalDetail ?? '',
                      onTap: () => context.go('/forecast'),
                    ),
                  ),
                SizedBox(height: v360.spacing.xxl),

                V360Reveal(delayIndex: 4, child: SectionLabel(strings.quickActions)),
                SizedBox(height: v360.spacing.md),
                V360Reveal(delayIndex: 5, child: _QuickActions(strings: strings, data: data)),
                SizedBox(height: v360.spacing.xxl),

                V360Reveal(
                  delayIndex: 6,
                  child: _ScoreCard(
                    score: data.healthScore,
                    band: data.healthBand,
                    strings: strings,
                  ),
                ),
                SizedBox(height: v360.spacing.x5),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.vendor, required this.queued, required this.syncing});

  final dynamic vendor;
  final int queued;
  final bool syncing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Row(
      children: <Widget>[
        Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.accentSurface,
            borderRadius: BorderRadius.circular(V360Radius.sm),
          ),
          child: Text(
            vendor.initials as String,
            style: v360.text.titleS.copyWith(color: colors.accentText),
          ),
        ),
        SizedBox(width: v360.spacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                vendor.storeName as String,
                style: v360.text.titleM.copyWith(color: colors.ink),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${vendor.locality ?? vendor.city}',
                style: v360.text.caption.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
        SyncBadge(queued: queued, syncing: syncing),
        SizedBox(width: v360.spacing.sm),
        V360IconButton(
          icon: v360.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
          onPressed: () => ref.read(themeModeProvider.notifier).toggle(),
          semanticLabel: 'Switch theme',
        ),
      ],
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.data, required this.strings});

  final DashboardSnapshot data;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      padding: EdgeInsets.all(v360.spacing.xxl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[colors.accent, colors.accent.withValues(alpha: 0.82)],
        ),
        borderRadius: BorderRadius.circular(V360Radius.xl),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colors.accent.withValues(alpha: 0.28),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(V360Radius.xl),
        child: Stack(
          children: [
            Positioned(
              right: -24,
              top: -24,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.1),
                ),
              ),
            ),
            Positioned(
              right: 48,
              bottom: -48,
              child: Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  strings.todaySales.toUpperCase(),
                  style: v360.text.label.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                SizedBox(height: v360.spacing.sm),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: RollingNumber(
                    value: data.todaySalesValue.rupees,
                    prefix: '₹',
                    style: v360.text.display.copyWith(
                      color: Colors.white,
                      fontSize: 42,
                      height: 1.0,
                    ),
                  ),
                ),
                SizedBox(height: v360.spacing.md),
                Row(
                  children: <Widget>[
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    SizedBox(width: v360.spacing.xs),
                    Text(
                      '${data.todayTransactionCount} entries',
                      style: v360.text.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.85),
                      ),
                    ),
                    SizedBox(width: v360.spacing.lg),
                    Icon(
                      Icons.calendar_today_outlined,
                      size: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                    SizedBox(width: v360.spacing.xs),
                    Expanded(
                      child: Text(
                        '${strings.thisWeek}: ${data.weekSalesValue.display}',
                        style: v360.text.caption.copyWith(
                          color: Colors.white.withValues(alpha: 0.85),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.strings, required this.data});

  final Strings strings;
  final DashboardSnapshot data;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;

    final actions = <({IconData icon, String label, String route, int? badge})>[
      (icon: Icons.mic_rounded, label: strings.speak, route: '/voice', badge: null),
      (
        icon: Icons.document_scanner_outlined,
        label: strings.scanReceipt,
        route: '/receipt',
        badge: null
      ),
      (
        icon: Icons.map_outlined,
        label: 'Demand map',
        route: '/heatmap',
        badge: null
      ),
      (
        icon: Icons.groups_outlined,
        label: 'Bulk deals',
        route: '/pools',
        badge: data.pendingPools > 0 ? data.pendingPools : null
      ),
      (
        icon: Icons.hourglass_bottom_rounded,
        label: 'Expiry',
        route: '/expiry',
        badge: data.expiringSoonCount > 0 ? data.expiringSoonCount : null
      ),
      (
        icon: Icons.analytics_outlined,
        label: 'Accuracy',
        route: '/accuracy',
        badge: null
      ),
    ];

    return Wrap(
      spacing: v360.spacing.md,
      runSpacing: v360.spacing.md,
      children: <Widget>[
        for (final action in actions)
          _ActionChip(
            icon: action.icon,
            label: action.label,
            badge: action.badge,
            onTap: () => context.go(action.route),
          ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
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

    return V360Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(V360Radius.md),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.lg,
          vertical: v360.spacing.md,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(V360Radius.md),
          border: Border.all(color: colors.hairline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: colors.accentText),
            SizedBox(width: v360.spacing.sm),
            Text(label, style: v360.text.bodyStrong.copyWith(color: colors.ink)),
            if (badge != null) ...<Widget>[
              SizedBox(width: v360.spacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: colors.warningSurface,
                  borderRadius: BorderRadius.circular(V360Radius.pill),
                ),
                child: Text(
                  '$badge',
                  style: v360.text.label.copyWith(color: colors.warningText),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreCard extends StatelessWidget {
  const _ScoreCard({
    required this.score,
    required this.band,
    required this.strings,
  });

  final double? score;
  final String? band;
  final Strings strings;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      onTap: () => context.go('/health'),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                SectionLabel(strings.healthScore),
                SizedBox(height: v360.spacing.sm),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: <Widget>[
                    RollingNumber(
                      value: score ?? 0,
                      style: v360.text.display.copyWith(color: colors.ink),
                    ),
                    SizedBox(width: v360.spacing.xs),
                    Text(
                      '/ 100',
                      style: v360.text.body.copyWith(color: colors.inkSubtle),
                    ),
                  ],
                ),
                SizedBox(height: v360.spacing.xs),
                Text(
                  band == 'provisional'
                      ? 'Provisional — more history needed'
                      : 'Ready to share with a lender',
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: colors.inkSubtle),
        ],
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
      padding: EdgeInsets.all(v360.spacing.gutter),
      children: <Widget>[
        const V360Skeleton(height: 44, width: 220),
        SizedBox(height: v360.spacing.xxl),
        const V360Skeleton(height: 148),
        SizedBox(height: v360.spacing.lg),
        Row(
          children: <Widget>[
            const Expanded(child: V360Skeleton(height: 108)),
            SizedBox(width: v360.spacing.md),
            const Expanded(child: V360Skeleton(height: 108)),
          ],
        ),
        SizedBox(height: v360.spacing.lg),
        const V360Skeleton(height: 92),
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
