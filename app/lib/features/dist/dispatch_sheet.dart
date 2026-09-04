import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/order_widgets.dart';

/// Today's round, grouped by locality.
///
/// A flat list of confirmed orders is a to-do list. Grouped by area it is a
/// route — one van, one locality at a time, densest first. The money owed
/// rides along on each stop because collecting on delivery is how this trade
/// actually settles, and a driver who does not know what to ask for does not
/// ask.
Future<void> showDispatch(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DispatchSheet(),
    );

class DispatchSheet extends ConsumerWidget {
  const DispatchSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final dispatch = ref.watch(distDispatchProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        child: dispatch.when(
          loading: () => Padding(
            padding: EdgeInsets.all(v360.spacing.gutter),
            child: const V360Skeleton(height: 200),
          ),
          error: (error, _) => EmptyState(
            icon: Icons.cloud_off_rounded,
            title: 'Could not load the round',
            body: '$error',
          ),
          data: (data) => data.stopCount == 0
              ? const EmptyState(
                  icon: Icons.local_shipping_outlined,
                  title: 'Nothing to send out',
                  body: 'Orders appear here once you have accepted them.',
                )
              : ListView(
                  controller: controller,
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  children: <Widget>[
                    Text(
                      "Today's round",
                      style: v360.text.titleM.copyWith(color: colors.ink),
                    ),
                    SizedBox(height: v360.spacing.xs),
                    Text(
                      '${data.stopCount} '
                      '${data.stopCount == 1 ? 'stop' : 'stops'} · '
                      '${data.value.display} of goods',
                      style:
                          v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                    SizedBox(height: v360.spacing.lg),
                    if (data.toCollect > 0) ...<Widget>[
                      V360Banner(
                        icon: Icons.payments_outlined,
                        tone: V360BannerTone.warning,
                        title: '${data.collect.display} to collect',
                        body: 'Owed on the stops below. Worth asking while '
                            'you are at the door.',
                      ),
                      SizedBox(height: v360.spacing.lg),
                    ],
                    for (final leg in data.legs)
                      Padding(
                        padding: EdgeInsets.only(bottom: v360.spacing.lg),
                        child: _Leg(leg: leg),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _Leg extends StatelessWidget {
  const _Leg({required this.leg});

  final DispatchLeg leg;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.place_outlined, size: 15, color: colors.accentText),
            SizedBox(width: v360.spacing.xs),
            Expanded(
              child: Text(
                '${leg.locality.toUpperCase()} · ${leg.stops.length}',
                style: v360.text.label.copyWith(color: colors.inkSubtle),
              ),
            ),
            Text(
              leg.value.display,
              style: v360.text.label.copyWith(color: colors.inkMuted),
            ),
          ],
        ),
        SizedBox(height: v360.spacing.sm),
        V360Card(
          child: Column(
            children: <Widget>[
              for (final stop in leg.stops) _Stop(stop: stop),
            ],
          ),
        ),
      ],
    );
  }
}

class _Stop extends StatelessWidget {
  const _Stop({required this.stop});

  final DispatchStop stop;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: v360.spacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  stop.storeName,
                  style: v360.text.bodyStrong.copyWith(color: colors.ink),
                ),
                SizedBox(height: 2),
                Text(
                  '${stop.orderCode} · ${stop.lineCount} '
                  '${stop.lineCount == 1 ? 'item' : 'items'}'
                  '${stop.overdue ? '' : ' · due ${shortDate(stop.expectedAt)}'}',
                  style: v360.text.caption.copyWith(color: colors.inkMuted),
                ),
                if (stop.overdue) ...<Widget>[
                  SizedBox(height: v360.spacing.xs),
                  Text(
                    'Late — promised ${shortDate(stop.expectedAt)}',
                    style:
                        v360.text.label.copyWith(color: colors.dangerText),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(width: v360.spacing.sm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              if (stop.amountDue > 0)
                Text(
                  'collect ${stop.due.display}',
                  style:
                      v360.text.label.copyWith(color: colors.warningText),
                ),
              SizedBox(height: v360.spacing.xs),
              V360IconButton(
                icon: Icons.phone_outlined,
                size: 34,
                semanticLabel: 'Copy ${stop.storeName}’s number',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: stop.phone));
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('${stop.phone} copied')),
                  );
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}
