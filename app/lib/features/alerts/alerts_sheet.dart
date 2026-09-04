import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/marketplace_models.dart';
import '../orders/order_widgets.dart';
import '../orders/sourcing_sheet.dart';
import 'live_dot.dart';

/// What the detectors noticed, and the one tap that answers it.
///
/// An alert that only tells you something is a notification. An alert that
/// tells you something and hands you the action is a feature — so a stockout
/// opens sourcing for that exact item, and a surge opens the pool it formed.
/// Without that, every alert ends in the user navigating to find the screen
/// the alert was already looking at.
Future<void> showAlerts(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AlertsSheet(),
    );

class AlertsSheet extends ConsumerWidget {
  const AlertsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final feed = ref.watch(alertsProvider);
    final isDistributor = ref.watch(sessionProvider).isDistributor;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, controller) => Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(V360Radius.xl),
          ),
        ),
        child: Column(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.fromLTRB(
                v360.spacing.gutter,
                v360.spacing.lg,
                v360.spacing.gutter,
                v360.spacing.sm,
              ),
              child: Row(
                children: <Widget>[
                  Text(
                    'What changed',
                    style: v360.text.titleM.copyWith(color: colors.ink),
                  ),
                  SizedBox(width: v360.spacing.sm),
                  const LiveDot(showLabel: true),
                  const Spacer(),
                  if ((feed.value?.unread ?? 0) > 0)
                    TextButton(
                      onPressed: () async {
                        await ref
                            .read(marketplaceProvider)
                            .markAllAlertsRead(distributor: isDistributor);
                        ref.invalidate(alertsProvider);
                      },
                      child: const Text('Mark all read'),
                    ),
                ],
              ),
            ),
            Expanded(
              child: feed.when(
                loading: () => ListView.builder(
                  controller: controller,
                  padding: EdgeInsets.all(v360.spacing.gutter),
                  itemCount: 3,
                  itemBuilder: (_, _) => Padding(
                    padding: EdgeInsets.only(bottom: v360.spacing.md),
                    child: const V360Skeleton(height: 84),
                  ),
                ),
                error: (error, _) => EmptyState(
                  icon: Icons.cloud_off_rounded,
                  title: 'Could not load alerts',
                  body: '$error',
                ),
                data: (data) => data.alerts.isEmpty
                    ? const EmptyState(
                        icon: Icons.notifications_none_rounded,
                        title: 'Nothing to flag',
                        body: 'Alerts appear here when something runs low, '
                            'sells unusually fast, or a group order forms '
                            'near you.',
                      )
                    : ListView(
                        controller: controller,
                        padding: EdgeInsets.fromLTRB(
                          v360.spacing.gutter,
                          0,
                          v360.spacing.gutter,
                          v360.spacing.x5,
                        ),
                        children: <Widget>[
                          for (final alert in data.alerts)
                            Padding(
                              padding:
                                  EdgeInsets.only(bottom: v360.spacing.md),
                              child: _AlertCard(
                                alert: alert,
                                isDistributor: isDistributor,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AlertCard extends ConsumerWidget {
  const _AlertCard({required this.alert, required this.isDistributor});

  final VendorAlert alert;
  final bool isDistributor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    final (Color fill, Color tint, IconData icon) = switch (alert.severity) {
      'urgent' => (colors.dangerSurface, colors.dangerText, Icons.priority_high_rounded),
      'warning' => (colors.warningSurface, colors.warningText, Icons.warning_amber_rounded),
      _ => (colors.surfaceMuted, colors.inkMuted, Icons.insights_rounded),
    };

    return V360Card(
      // Read alerts drop to the plain surface. Keeping the tint would leave a
      // wall of red for things already dealt with.
      color: alert.read ? null : fill,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 18, color: alert.read ? colors.inkSubtle : tint),
              SizedBox(width: v360.spacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      alert.title,
                      style: v360.text.bodyStrong.copyWith(
                        color: alert.read ? colors.inkMuted : colors.ink,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      alert.body,
                      style:
                          v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              Text(
                _ago(alert.createdAt),
                style: v360.text.label.copyWith(color: colors.inkSubtle),
              ),
            ],
          ),
          if (_action != null) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            Row(
              children: <Widget>[
                Expanded(
                  child: V360Button.secondary(
                    label: _action!,
                    expand: true,
                    onPressed: () => _act(context, ref),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// The one thing this alert is really asking for.
  String? get _action {
    if (isDistributor) {
      return switch (alert.kind) {
        'stockout' || 'anomaly' => 'See who needs stock',
        'surge' => 'Quote this group order',
        _ => null,
      };
    }
    return switch (alert.kind) {
      'stockout' => alert.itemId == null ? null : 'Order now',
      'anomaly' => alert.itemId == null ? null : 'Order more',
      'surge' => 'See the group order',
      _ => null,
    };
  }

  Future<void> _act(BuildContext context, WidgetRef ref) async {
    HapticFeedback.selectionClick();

    // Acting on an alert is the clearest possible signal it has been read.
    if (!alert.read) {
      await ref
          .read(marketplaceProvider)
          .markAlertRead(alert.id, distributor: isDistributor);
      ref.invalidate(alertsProvider);
    }
    if (!context.mounted) return;

    Navigator.of(context).pop();

    if (isDistributor) {
      context.go(alert.kind == 'surge' ? '/dist/demand' : '/dist/demand');
      return;
    }

    switch (alert.kind) {
      case 'surge':
        context.go('/pools');
      case 'stockout':
      case 'anomaly':
        final itemId = alert.itemId;
        if (itemId != null) await showSourcingSheet(context, itemId: itemId);
    }
  }

  static String _ago(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inMinutes < 1) return 'now';
    if (gap.inMinutes < 60) return '${gap.inMinutes}m';
    if (gap.inHours < 24) return '${gap.inHours}h';
    return shortDate(when);
  }
}
