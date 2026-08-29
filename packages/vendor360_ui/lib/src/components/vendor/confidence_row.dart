import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import 'stat_tile.dart';

/// A parsed voice or OCR line awaiting confirmation.
///
/// This component is where the guide's "forgiving" principle is enforced: ASR
/// and OCR are imperfect, so nothing commits without the vendor seeing it
/// first, and a low-confidence row is visually distinct rather than merely
/// annotated.
///
/// The quantity is editable inline through a stepper. Sending a vendor to a
/// keyboard to fix a misheard number would give back exactly the friction that
/// voice entry exists to remove — a single tap corrects it.
class ConfidenceRow extends StatelessWidget {
  const ConfidenceRow({
    super.key,
    required this.skuName,
    required this.quantity,
    required this.unit,
    required this.confidence,
    required this.needsReview,
    this.movementLabel,
    this.isKnownItem = true,
    this.onIncrement,
    this.onDecrement,
    this.onRemove,
    this.matchedText,
  });

  final String skuName;
  final double quantity;
  final String? unit;
  final double confidence;
  final bool needsReview;
  final String? movementLabel;

  /// False when the SKU is not yet in the vendor's catalogue — it will be
  /// created on confirm, which the row says explicitly rather than surprising
  /// the vendor afterwards.
  final bool isKnownItem;

  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;
  final VoidCallback? onRemove;

  /// What was actually heard or read, shown when confidence is low so the
  /// vendor can see why the parse is uncertain.
  final String? matchedText;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final tone = needsReview ? colors.warning : colors.accent;

    return Container(
      margin: EdgeInsets.only(bottom: v360.spacing.md),
      padding: EdgeInsets.all(v360.spacing.lg),
      decoration: BoxDecoration(
        color: needsReview ? colors.warningSurface : colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.md),
        border: Border.all(
          color: needsReview ? colors.warning.withValues(alpha: 0.4) : colors.hairline,
          width: needsReview ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      skuName,
                      style: v360.text.titleS.copyWith(color: colors.ink),
                    ),
                    SizedBox(height: v360.spacing.xs),
                    Wrap(
                      spacing: v360.spacing.sm,
                      runSpacing: v360.spacing.xs,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        if (movementLabel != null)
                          StatusPill(
                            label: movementLabel!,
                            tone: PillTone.neutral,
                            dense: true,
                          ),
                        StatusPill(
                          label: '${(confidence * 100).round()}% sure',
                          tone: needsReview ? PillTone.attention : PillTone.healthy,
                          dense: true,
                        ),
                        if (!isKnownItem)
                          const StatusPill(
                            label: 'New item',
                            tone: PillTone.voice,
                            icon: Icons.add_rounded,
                            dense: true,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              _Stepper(
                quantity: quantity,
                unit: unit,
                onIncrement: onIncrement,
                onDecrement: onDecrement,
              ),
              if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.close_rounded, size: 18, color: colors.inkSubtle),
                  tooltip: 'Remove this line',
                ),
            ],
          ),
          if (needsReview && matchedText != null) ...<Widget>[
            SizedBox(height: v360.spacing.sm),
            Row(
              children: <Widget>[
                Icon(Icons.hearing_rounded, size: 13, color: tone),
                SizedBox(width: v360.spacing.xs),
                Expanded(
                  child: Text(
                    'Heard "$matchedText" — please check',
                    style: v360.text.caption.copyWith(color: colors.warningText),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Stepper extends StatelessWidget {
  const _Stepper({
    required this.quantity,
    required this.unit,
    this.onIncrement,
    this.onDecrement,
  });

  final double quantity;
  final String? unit;
  final VoidCallback? onIncrement;
  final VoidCallback? onDecrement;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final text = quantity == quantity.roundToDouble()
        ? quantity.toStringAsFixed(0)
        : quantity.toStringAsFixed(1);

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _StepButton(icon: Icons.remove_rounded, onTap: onDecrement),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: v360.spacing.sm),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  text,
                  style: v360.text.titleS.copyWith(color: colors.ink),
                ),
                if (unit != null)
                  Text(
                    unit!,
                    style: v360.text.label.copyWith(color: colors.inkSubtle),
                  ),
              ],
            ),
          ),
          _StepButton(icon: Icons.add_rounded, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Padding(
        // 44x44 minimum target from the accessibility notes — these are tapped
        // one-handed while serving a customer.
        padding: const EdgeInsets.all(12),
        child: Icon(
          icon,
          size: 20,
          color: onTap == null ? colors.inkSubtle : colors.accentText,
        ),
      ),
    );
  }
}
