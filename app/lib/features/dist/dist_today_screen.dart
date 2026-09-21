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
      body: summary.when(
        loading: () => ListView(
          padding: EdgeInsets.zero,
          children: <Widget>[
            // The band keeps the screen's shape while the numbers load.
            Container(height: 250, color: colors.band),
            Padding(
              padding: EdgeInsets.all(v360.spacing.gutter),
              child: const Column(
                children: <Widget>[
                  V360Skeleton(height: 64),
                  SizedBox(height: 16),
                  V360Skeleton(height: 180),
                ],
              ),
            ),
          ],
        ),
        error: (error, _) => SafeArea(
          child: EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load your day',
            body: '$error',
          ),
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
            padding: EdgeInsets.zero,
            children: <Widget>[
              PackHeader(
                title: data.businessName,
                subtitle: _greeting(),
                actions: <Widget>[
                  const LiveDot(onBand: true),
                  AlertBell(onBand: true, onTap: () => showAlerts(context)),
                  V360IconButton(
                    icon: Icons.logout_rounded,
                    color: colors.onBand,
                    semanticLabel: 'Sign out',
                    onPressed: () =>
                        ref.read(sessionProvider.notifier).signOut(),
                  ),
                ],
                // The wholesaler's one number: shops waiting to hear back.
                figure: Text('${data.needsAction}'),
                figureCaption: data.needsAction == 1
                    ? 'order waiting for your answer'
                    : 'orders waiting for your answer',
                facts: <PackFact>[
                  PackFact(
                    '${data.toDispatch}',
                    'to send out',
                    onTap: () => showDispatch(context),
                  ),
                  PackFact('${data.inTransit}', 'on the road'),
                  PackFact(data.revenue.display, 'this week'),
                ],
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  v360.spacing.gutter,
                  v360.spacing.xl,
                  v360.spacing.gutter,
                  v360.spacing.x5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (data.topPrompt != null) ...<Widget>[
                      SignalBanner(
                        icon: data.needsAction > 0
                            ? Icons.inbox_rounded
                            : Icons.insights_rounded,
                        title: data.topPrompt!,
                        detail: data.topPromptDetail ?? '',
                        onTap: () => context.go(
                          data.needsAction > 0
                              ? '/dist/orders'
                              : '/dist/demand',
                        ),
                      ),
                      SizedBox(height: v360.spacing.x3),
                    ],
                    const SectionLabel('Orders'),
                    SizedBox(height: v360.spacing.sm),
                    _Statement(
                      rows: <_Line>[
                        _Line(
                          label: 'To answer',
                          value: '${data.needsAction}',
                          tone: data.needsAction > 0 ? colors.warning : null,
                          onTap: () => context.go('/dist/orders'),
                        ),
                        _Line(
                          label: 'Delivered this week',
                          value: '${data.deliveredThisWeek}',
                        ),
                      ],
                    ),
                    SizedBox(height: v360.spacing.x3),
                    const SectionLabel('Money'),
                    SizedBox(height: v360.spacing.sm),
                    _Statement(
                      rows: <_Line>[
                        _Line(
                          label: 'Owed to you',
                          value: data.outstandingMoney.display,
                          onTap: () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) =>
                                const LedgerSheet(distributorView: true),
                          ),
                        ),
                        _Line(
                          label: 'Overdue',
                          value: data.overdueMoney.display,
                          tone: data.overdue > 0 ? colors.danger : null,
                        ),
                      ],
                    ),
                    SizedBox(height: v360.spacing.x3),
                    const SectionLabel('Your book'),
                    SizedBox(height: v360.spacing.sm),
                    _Statement(
                      rows: <_Line>[
                        _Line(
                          label: 'Shops',
                          value: '${data.connectedShops}',
                          onTap: () => context.go('/dist/shops'),
                        ),
                        _Line(
                          label: 'Running out',
                          caption: 'before you can reach them',
                          value: '${data.atRiskCount}',
                          tone: data.atRiskCount > 0 ? colors.warning : null,
                          onTap: () => context.go('/dist/demand'),
                        ),
                      ],
                    ),
                    if (data.openPoolCount > 0) ...<Widget>[
                      SizedBox(height: v360.spacing.lg),
                      V360Banner(
                        icon: Icons.groups_rounded,
                        title:
                            '${data.openPoolCount} group '
                            '${data.openPoolCount == 1 ? 'order' : 'orders'} open',
                        body:
                            'Several shops need the same thing. Quote once, '
                            'supply all of them.',
                        onTap: () => context.go('/dist/demand'),
                      ),
                    ],
                  ],
                ),
              ),
            ],
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

/// One line of a statement: what, how much, and where to go for more.
@immutable
class _Line {
  const _Line({
    required this.label,
    required this.value,
    this.caption,
    this.tone,
    this.onTap,
  });

  final String label;
  final String value;
  final String? caption;
  final Color? tone;
  final VoidCallback? onTap;
}

/// Figures set as a ruled statement, the way a wholesaler's ledger reads
/// them — label on the left, amount on the right — rather than a grid of
/// equal tiles that makes "in transit" look as urgent as "overdue".
class _Statement extends StatelessWidget {
  const _Statement({required this.rows});

  final List<_Line> rows;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      padding: EdgeInsets.zero,
      child: Column(
        children: <Widget>[
          for (var i = 0; i < rows.length; i++) ...<Widget>[
            if (i > 0) Divider(indent: v360.spacing.lg),
            Semantics(
              button: rows[i].onTap != null,
              label: '${rows[i].label}, ${rows[i].value}',
              excludeSemantics: true,
              child: InkWell(
                onTap: rows[i].onTap,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: v360.spacing.lg,
                    vertical: v360.spacing.md,
                  ),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            rows[i].tone == null
                                ? Text(
                                    rows[i].label,
                                    style: v360.text.body.copyWith(
                                      color: colors.ink,
                                    ),
                                  )
                                : StatusMark(
                                    label: rows[i].label,
                                    color: rows[i].tone!,
                                  ),
                            if (rows[i].caption != null)
                              Text(
                                rows[i].caption!,
                                style: v360.text.caption.copyWith(
                                  color: colors.inkMuted,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        rows[i].value,
                        style: v360.text.titleS
                            .copyWith(color: colors.ink)
                            .weight(FontWeight.w700)
                            .narrow(86),
                      ),
                      if (rows[i].onTap != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            size: 20,
                            color: colors.inkSubtle,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
