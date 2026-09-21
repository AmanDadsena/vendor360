import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';
import '../buttons/v360_button.dart';
import '../feedback/status_mark.dart';
import 'stat_tile.dart';

/// A countdown to spoilage.
///
/// Both a colour and a label, never colour alone — the guide requires status
/// to survive colour-blindness, and "2 days left" carries the meaning on its
/// own.
class ExpiryChip extends StatelessWidget {
  const ExpiryChip({super.key, required this.daysLeft, this.dense = false});

  final int daysLeft;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final (String label, PillTone tone, IconData icon) = switch (daysLeft) {
      < 0 => ('Expired', PillTone.urgent, Icons.dangerous_outlined),
      0 => ('Today', PillTone.urgent, Icons.timer_outlined),
      1 => ('1 day', PillTone.urgent, Icons.timer_outlined),
      <= 3 => ('$daysLeft days', PillTone.attention, Icons.schedule_rounded),
      <= 7 => ('$daysLeft days', PillTone.attention, Icons.schedule_rounded),
      _ => (
        '$daysLeft days',
        PillTone.healthy,
        Icons.check_circle_outline_rounded,
      ),
    };

    return StatusPill(label: label, tone: tone, icon: icon, dense: dense);
  }
}

/// A row on the expiry board.
///
/// Leads with value at risk rather than quantity. A vendor deciding what to
/// discount first is making a money decision, and 3 kg of paneer outranks
/// 40 kg of potatoes even though the potato pile looks bigger.
class ExpiryRow extends StatelessWidget {
  const ExpiryRow({
    super.key,
    required this.skuName,
    required this.quantityLabel,
    required this.daysLeft,
    required this.valueAtRisk,
    required this.suggestedDiscountPct,
    this.onDiscount,
    this.onMarkWasted,
  });

  final String skuName;
  final String quantityLabel;
  final int daysLeft;
  final String valueAtRisk;
  final int suggestedDiscountPct;
  final VoidCallback? onDiscount;
  final VoidCallback? onMarkWasted;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final expired = daysLeft < 0;

    final (String due, Color tone) = switch (daysLeft) {
      < 0 => ('Expired', colors.danger),
      0 => ('Today', colors.danger),
      1 => ('1 day left', colors.danger),
      <= 7 => ('$daysLeft days left', colors.warning),
      _ => ('$daysLeft days left', colors.accent),
    };

    // One ruled row of a list, not a card: what it is, how long it has, what
    // it is worth, and the two things to do about it.
    return Padding(
      padding: EdgeInsets.fromLTRB(
        v360.spacing.lg,
        v360.spacing.md,
        v360.spacing.md,
        v360.spacing.xs,
      ),
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
                      skuName,
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: <Widget>[
                        StatusMark(label: due, color: tone, dense: true),
                        Flexible(
                          child: Text(
                            '  ·  $quantityLabel',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: v360.text.caption.copyWith(
                              color: colors.inkMuted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              SizedBox(width: v360.spacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    valueAtRisk,
                    style: v360.text.titleS
                        .copyWith(
                          color: expired ? colors.dangerText : colors.ink,
                        )
                        .weight(FontWeight.w700)
                        .narrow(86),
                  ),
                  Text(
                    'at risk',
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ),
            ],
          ),
          if (suggestedDiscountPct > 0 || expired) ...<Widget>[
            SizedBox(height: v360.spacing.sm),
            Text(
              expired
                  ? 'Past shelf life. Record it as waste to keep your score honest.'
                  : 'Discount $suggestedDiscountPct% to clear it before it spoils.',
              style: v360.text.caption.copyWith(color: colors.ink),
            ),
          ],
          SizedBox(height: v360.spacing.sm),
          Row(
            children: <Widget>[
              if (onDiscount != null && !expired)
                Expanded(
                  child: V360Button.tonal(
                    label: 'Mark $suggestedDiscountPct% off',
                    leadingIcon: Icons.sell_outlined,
                    size: V360ButtonSize.md,
                    expand: true,
                    onPressed: onDiscount,
                  ),
                ),
              if (onMarkWasted != null)
                Expanded(
                  child: TextButton.icon(
                    onPressed: onMarkWasted,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Record waste'),
                    style: TextButton.styleFrom(
                      foregroundColor: colors.dangerText,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
