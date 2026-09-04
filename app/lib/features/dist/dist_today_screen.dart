import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../alerts/alerts_sheet.dart';
import 'dispatch_sheet.dart';
import '../alerts/live_dot.dart';
import '../orders/order_widgets.dart';

/// The wholesaler's morning screen.
///
/// Built around one question — *what should I do first?* — rather than a
/// dashboard of everything. The prompt at the top is the server's single
/// highest-value next action, chosen by urgency to the relationship rather
/// than by size: an unanswered order is a shop waiting on you, which costs
/// more than a stale receivable.
class DistTodayScreen extends ConsumerWidget {
  const DistTodayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final summary = ref.watch(distSummaryProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: summary.when(
          loading: () => ListView(
            padding: EdgeInsets.all(v360.spacing.gutter),
            children: <Widget>[
              const V360Skeleton(height: 90),
              SizedBox(height: v360.spacing.md),
              const V360Skeleton(height: 130),
              SizedBox(height: v360.spacing.md),
              const V360Skeleton(height: 130),
            ],
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load your day',
            body: '$error',
          ),
          data: (data) => RefreshIndicator(
            color: colors.accent,
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref
                ..invalidate(distSummaryProvider)
                ..invalidate(distInboxProvider)
                ..invalidate(distDemandProvider);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                v360.spacing.gutter,
                v360.spacing.md,
                v360.spacing.gutter,
                v360.spacing.x5,
              ),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            _greeting(),
                            style: v360.text.caption
                                .copyWith(color: colors.inkMuted),
                          ),
                          Text(
                            data.businessName,
                            style: v360.text.titleL
                                .copyWith(color: colors.ink),
                          ),
                        ],
                      ),
                    ),
                    const LiveDot(),
                    SizedBox(width: v360.spacing.xs),
                    AlertBell(onTap: () => showAlerts(context)),
                    V360IconButton(
                      icon: Icons.logout_rounded,
                      semanticLabel: 'Sign out',
                      onPressed: () =>
                          ref.read(sessionProvider.notifier).signOut(),
                    ),
                  ],
                ),

                SizedBox(height: v360.spacing.lg),

                if (data.topPrompt != null)
                  Padding(
                    padding: EdgeInsets.only(bottom: v360.spacing.lg),
                    child: V360Banner(
                      icon: Icons.bolt_rounded,
                      tone: data.needsAction > 0
                          ? V360BannerTone.warning
                          : V360BannerTone.info,
                      title: data.topPrompt!,
                      body: data.topPromptDetail,
                      onTap: () => context.go(
                        data.needsAction > 0 ? '/dist/orders' : '/dist/demand',
                      ),
                    ),
                  ),

                SectionLabel('Orders'),
                SizedBox(height: v360.spacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: 'To answer',
                        value: '${data.needsAction}',
                        icon: Icons.inbox_rounded,
                        tone: data.needsAction > 0 ? colors.voiceText : null,
                        onTap: () => context.go('/dist/orders'),
                      ),
                    ),
                    SizedBox(width: v360.spacing.md),
                    Expanded(
                      child: StatTile(
                        label: 'To send out',
                        value: '${data.toDispatch}',
                        caption: data.toDispatch > 0 ? "see today's round" : null,
                        icon: Icons.local_shipping_outlined,
                        onTap: () => showDispatch(context),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: v360.spacing.md),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: 'In transit',
                        value: '${data.inTransit}',
                        icon: Icons.route_outlined,
                      ),
                    ),
                    SizedBox(width: v360.spacing.md),
                    Expanded(
                      child: StatTile(
                        label: 'Delivered this week',
                        value: '${data.deliveredThisWeek}',
                        caption: data.revenue.display,
                        icon: Icons.check_circle_outline_rounded,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: v360.spacing.lg),
                SectionLabel('Money'),
                SizedBox(height: v360.spacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: 'Owed to you',
                        value: data.outstandingMoney.display,
                        icon: Icons.account_balance_wallet_outlined,
                        onTap: () => showModalBottomSheet<void>(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) =>
                              const LedgerSheet(distributorView: true),
                        ),
                      ),
                    ),
                    SizedBox(width: v360.spacing.md),
                    Expanded(
                      child: StatTile(
                        label: 'Overdue',
                        value: data.overdueMoney.display,
                        tone: data.overdue > 0 ? colors.dangerText : null,
                        icon: Icons.schedule_rounded,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: v360.spacing.lg),
                SectionLabel('Your book'),
                SizedBox(height: v360.spacing.sm),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: StatTile(
                        label: 'Shops',
                        value: '${data.connectedShops}',
                        icon: Icons.storefront_outlined,
                        onTap: () => context.go('/dist/shops'),
                      ),
                    ),
                    SizedBox(width: v360.spacing.md),
                    Expanded(
                      child: StatTile(
                        label: 'Running out',
                        value: '${data.atRiskCount}',
                        caption: 'before you can reach them',
                        tone: data.atRiskCount > 0 ? colors.warningText : null,
                        icon: Icons.priority_high_rounded,
                        onTap: () => context.go('/dist/demand'),
                      ),
                    ),
                  ],
                ),

                if (data.openPoolCount > 0) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  V360Banner(
                    icon: Icons.groups_rounded,
                    title: '${data.openPoolCount} group '
                        '${data.openPoolCount == 1 ? 'order' : 'orders'} open',
                    body: 'Several shops need the same thing. Quote once, '
                        'supply all of them.',
                    onTap: () => context.go('/dist/demand'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }
}
