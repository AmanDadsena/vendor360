import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import '../controls/v360_pressable.dart';

/// A case-count stepper that shows what the count comes to.
///
/// Wholesalers sell by the case, so the number a vendor adjusts is cases —
/// but the number that matters to them is kilograms on a shelf. Showing both,
/// live, is the whole point of this control: the alternative is a shopkeeper
/// typing "12" for twelve kilos and receiving a hundred and twenty.
///
/// The minimum-order floor is enforced here rather than validated later, so
/// the decrement simply stops instead of accepting a value the server will
/// reject.
class PackStepper extends StatelessWidget {
  const PackStepper({
    super.key,
    required this.packs,
    required this.packSize,
    required this.unit,
    required this.onChanged,
    this.minPacks = 1,
    this.maxPacks = 999,
    this.unitPrice,
    this.dense = false,
  });

  final int packs;
  final double packSize;
  final String unit;
  final ValueChanged<int> onChanged;
  final int minPacks;
  final int maxPacks;

  /// When given, the running total is shown beside the quantity.
  final double? unitPrice;

  final bool dense;

  double get _quantity => packs * packSize;

  String get _sizeLabel => packSize == packSize.roundToDouble()
      ? packSize.toStringAsFixed(0)
      : packSize.toString();

  String get _quantityLabel {
    final rounded = (_quantity * 100).round() / 100;
    final text = rounded == rounded.roundToDouble()
        ? rounded.toStringAsFixed(0)
        : rounded.toString();
    return '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final atFloor = packs <= minPacks;
    final atCeiling = packs >= maxPacks;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(V360Radius.pill),
            border: Border.all(color: colors.hairline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _Step(
                icon: Icons.remove_rounded,
                enabled: !atFloor,
                dense: dense,
                semanticLabel: 'One case fewer',
                onTap: () => onChanged(packs - 1),
              ),
              Container(
                constraints: BoxConstraints(minWidth: dense ? 30 : 38),
                alignment: Alignment.center,
                child: Text(
                  '$packs',
                  style: (dense ? v360.text.body : v360.text.titleS).copyWith(
                    fontWeight: FontWeight.w800,
                    color: colors.ink,
                    // Tabular figures: the row must not jitter as the count
                    // crosses from 9 to 10.
                    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
              _Step(
                icon: Icons.add_rounded,
                enabled: !atCeiling,
                dense: dense,
                semanticLabel: 'One case more',
                onTap: () => onChanged(packs + 1),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Text(
          unitPrice == null
              ? '× $_sizeLabel $unit = $_quantityLabel'
              : '$_quantityLabel · ₹${(_quantity * unitPrice!).round()}',
          style: v360.text.label.copyWith(
            color: colors.inkSubtle,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.semanticLabel,
    required this.dense,
  });

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final String semanticLabel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    final size = dense ? 30.0 : 38.0;

    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      excludeSemantics: true,
      child: V360Pressable(
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            size: dense ? 16 : 19,
            color: enabled ? colors.ink : colors.inkSubtle.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}
