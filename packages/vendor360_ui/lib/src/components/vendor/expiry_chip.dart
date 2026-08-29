import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
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
      _ => ('$daysLeft days', PillTone.healthy, Icons.check_circle_outline_rounded),
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

    return Container(
      margin: EdgeInsets.only(bottom: v360.spacing.md),
      padding: EdgeInsets.all(v360.spacing.lg),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.md),
        border: Border.all(
          color: expired
              ? colors.danger.withValues(alpha: 0.4)
              : daysLeft <= 3
                  ? colors.warning.withValues(alpha: 0.35)
                  : colors.hairline,
        ),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(skuName, style: v360.text.titleS.copyWith(color: colors.ink)),
                    SizedBox(height: v360.spacing.xs),
                    Text(
                      quantityLabel,
                      style: v360.text.caption.copyWith(color: colors.inkMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  ExpiryChip(daysLeft: daysLeft, dense: true),
                  SizedBox(height: v360.spacing.xs),
                  Text(
                    '$valueAtRisk at risk',
                    style: v360.text.bodyStrong.copyWith(
                      color: expired ? colors.dangerText : colors.ink,
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (suggestedDiscountPct > 0) ...<Widget>[
            SizedBox(height: v360.spacing.md),
            Container(
              padding: EdgeInsets.all(v360.spacing.md),
              decoration: BoxDecoration(
                color: colors.voiceSurface,
                borderRadius: BorderRadius.circular(V360Radius.sm),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.sell_outlined, size: 16, color: colors.voiceText),
                  SizedBox(width: v360.spacing.sm),
                  Expanded(
                    child: Text(
                      expired
                          ? 'Past shelf life — record as waste to keep your score honest'
                          : 'Discount $suggestedDiscountPct% to clear before spoilage',
                      style: v360.text.caption.copyWith(color: colors.voiceText),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: v360.spacing.md),
          Row(
            children: <Widget>[
              if (onDiscount != null && !expired)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDiscount,
                    icon: const Icon(Icons.sell_outlined, size: 16),
                    label: Text('Mark $suggestedDiscountPct% off'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.accentText,
                      side: BorderSide(color: colors.hairline),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(V360Radius.pill),
                      ),
                    ),
                  ),
                ),
              if (onDiscount != null && onMarkWasted != null && !expired)
                SizedBox(width: v360.spacing.sm),
              if (onMarkWasted != null)
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onMarkWasted,
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Record waste'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: colors.dangerText,
                      side: BorderSide(color: colors.danger.withValues(alpha: 0.3)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(V360Radius.pill),
                      ),
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
