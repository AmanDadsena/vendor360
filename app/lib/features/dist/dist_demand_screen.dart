import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';

/// What the book will need, and who runs out before the van can reach them.
///
/// This is the screen that makes the distributor side worth having. The
/// forecasting engine that tells one shop what it will sell is pointed at a
/// whole vendor book instead, so a wholesaler stops guessing what to load and
/// starts knowing.
///
/// The consent notice is not a disclaimer. A distributor reading these numbers
/// has to know the picture is partial and by how much, or they will plan
/// against a total that quietly excludes a fifth of their customers.
class DistDemandScreen extends ConsumerWidget {
  const DistDemandScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final demand = ref.watch(distDemandProvider);
    final horizon = ref.watch(demandHorizonProvider);

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
        title: Text('Demand', style: v360.text.titleM.copyWith(color: colors.ink)),
      ),
      body: SafeArea(
        child: demand.when(
          loading: () => ListView(
            padding: EdgeInsets.all(v360.spacing.gutter),
            children: <Widget>[
              const V360Skeleton(height: 70),
              SizedBox(height: v360.spacing.md),
              const V360Skeleton(height: 200),
            ],
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load demand',
            body: '$error',
          ),
          data: (data) => RefreshIndicator(
            color: colors.accent,
            onRefresh: () async {
              HapticFeedback.lightImpact();
              ref.invalidate(distDemandProvider);
            },
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                v360.spacing.gutter,
                0,
                v360.spacing.gutter,
                v360.spacing.x5,
              ),
              children: <Widget>[
                V360Segmented<int>(
                  value: horizon,
                  segments: const <V360Segment<int>>[
                    V360Segment(value: 3, label: '3 days'),
                    V360Segment(value: 7, label: '1 week'),
                    V360Segment(value: 14, label: '2 weeks'),
                  ],
                  onChanged: (v) =>
                      ref.read(demandHorizonProvider.notifier).value = v,
                ),

                SizedBox(height: v360.spacing.lg),

                // ------------------------------------------------ at risk
                if (data.atRisk.isNotEmpty) ...<Widget>[
                  SectionLabel('Call these shops'),
                  SizedBox(height: v360.spacing.xs),
                  Text(
                    'They run out before your delivery could reach them.',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                  SizedBox(height: v360.spacing.sm),
                  for (final shop in data.atRisk)
                    Padding(
                      padding: EdgeInsets.only(bottom: v360.spacing.md),
                      child: _AtRiskCard(shop: shop),
                    ),
                  SizedBox(height: v360.spacing.lg),
                ],

                // ------------------------------------------------- outlook
                SectionLabel('What to stock'),
                SizedBox(height: v360.spacing.sm),
                if (data.lines.isEmpty)
                  EmptyState(
                    icon: Icons.insights_outlined,
                    title: data.totalConnected < 3
                        ? 'Not enough shops yet'
                        : 'No shared demand yet',
                    body: data.totalConnected < 3
                        ? 'Demand is only shown once at least three shops '
                            'contribute, so no single shop\'s numbers can be '
                            'read off the total. You have '
                            '${data.totalConnected}.'
                        : 'Your connected shops have not shared their demand, '
                            'or you do not stock what they sell.',
                  )
                else
                  for (final line in data.lines)
                    Padding(
                      padding: EdgeInsets.only(bottom: v360.spacing.md),
                      child: _DemandCard(line: line, horizon: data.horizonDays),
                    ),

                // ------------------------------------------------- consent
                if (data.withheld > 0) ...<Widget>[
                  SizedBox(height: v360.spacing.md),
                  V360Banner(
                    icon: Icons.lock_outline_rounded,
                    title: '${data.withheld} of ${data.totalConnected} shops '
                        'keep their numbers private',
                    body: 'These figures cover the '
                        '${data.consentingShops} who chose to share. They are '
                        'still your customers — they have simply not opted in.',
                  ),
                ],

                // ---------------------------------------------- dead lines
                if (data.deadLines.isNotEmpty) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  SectionLabel('Nobody is ordering these'),
                  SizedBox(height: v360.spacing.sm),
                  V360Card(
                    child: Column(
                      children: <Widget>[
                        for (final dead in data.deadLines)
                          Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: v360.spacing.sm,
                            ),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    dead.skuName,
                                    style: v360.text.body
                                        .copyWith(color: colors.ink),
                                  ),
                                ),
                                Text(
                                  dead.daysSinceLastOrder == null
                                      ? 'never ordered'
                                      : '${dead.daysSinceLastOrder}d ago',
                                  style: v360.text.label
                                      .copyWith(color: colors.inkSubtle),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AtRiskCard extends StatelessWidget {
  const _AtRiskCard({required this.shop});

  final AtRiskShop shop;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Card(
      color: colors.warningSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  shop.storeName,
                  style: v360.text.titleS.copyWith(color: colors.ink),
                ),
              ),
              Text(
                shop.value.display,
                style: v360.text.titleS.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 2),
          Text(
            '${shop.locality} · ${shop.skuName}',
            style: v360.text.caption.copyWith(color: colors.inkMuted),
          ),
          SizedBox(height: v360.spacing.md),
          Text(
            shop.urgency,
            style: v360.text.bodyStrong.copyWith(color: colors.warningText),
          ),
          SizedBox(height: v360.spacing.xs),
          Text(
            '${shop.currentQty < 0.05 ? 'Shelf is empty' : 'Down to ${Quantity(shop.currentQty, shop.unit).approx}'}, '
            'selling about ${Quantity(shop.dailyRate, shop.unit).approx} a '
            'day. Suggest ${shop.suggestedPacks.round()} '
            '${shop.suggestedPacks.round() == 1 ? 'case' : 'cases'}.',
            style: v360.text.caption.copyWith(color: colors.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _DemandCard extends StatelessWidget {
  const _DemandCard({required this.line, required this.horizon});

  final DemandLine line;
  final int horizon;

  @override
  Widget build(BuildContext context) {
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
                  line.skuName,
                  style: v360.text.titleS.copyWith(color: colors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  'across ${line.shopCount} '
                  '${line.shopCount == 1 ? 'shop' : 'shops'} · next $horizon days',
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
                SizedBox(height: v360.spacing.sm),
                if (line.packsToStock != null)
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: v360.spacing.sm,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accentSurface,
                      borderRadius: BorderRadius.circular(V360Radius.pill),
                    ),
                    child: Text(
                      'stock ${line.packsToStock!.round()} '
                      '${line.packsToStock!.round() == 1 ? 'case' : 'cases'}',
                      style:
                          v360.text.label.copyWith(color: colors.accentText),
                    ),
                  ),
              ],
            ),
          ),
          SizedBox(width: v360.spacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                Quantity(line.expectedQty, line.unit).approx,
                style: v360.text.titleS.copyWith(
                  color: colors.ink,
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
              Text(
                line.revenue.display,
                style: v360.text.label.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
