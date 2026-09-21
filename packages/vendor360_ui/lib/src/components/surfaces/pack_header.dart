import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// One line of a [DeclarationStrip]: a value and what it is.
@immutable
class PackFact {
  const PackFact(this.value, this.label, {this.onTap});

  /// Printed first and bold — "14", "₹48,200".
  final String value;

  /// Printed small beneath — "entries", "this week".
  final String label;

  final VoidCallback? onTap;
}

/// The ruled box a pack prints its MRP, net quantity and best-before in:
/// equal cells separated by thin rules, value first, label beneath.
///
/// Value-first is deliberate. "14 entries" reads as a fact; a small grey
/// label *above* a number is the dashboard eyebrow this design avoids.
class DeclarationStrip extends StatelessWidget {
  const DeclarationStrip({
    super.key,
    required this.facts,
    this.onBand = false,
  });

  final List<PackFact> facts;

  /// True when printed on the teal band rather than on white.
  final bool onBand;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final value = onBand ? colors.onBand : colors.ink;
    final label = onBand ? colors.onBandMuted : colors.inkMuted;
    final rule = onBand
        ? colors.onBand.withValues(alpha: 0.32)
        : colors.hairline;

    final cells = <Widget>[];
    for (var i = 0; i < facts.length; i++) {
      final fact = facts[i];
      if (i > 0) {
        cells.add(Container(width: 1, color: rule));
      }
      final cell = Padding(
        padding: EdgeInsets.fromLTRB(
          i == 0 ? 0 : v360.spacing.md,
          v360.spacing.sm + 2,
          v360.spacing.sm,
          v360.spacing.sm + 2,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                fact.value,
                maxLines: 1,
                style: v360.text.titleS
                    .copyWith(color: value)
                    .weight(FontWeight.w700)
                    .narrow(86),
              ),
            ),
            Text(
              fact.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v360.text.caption.copyWith(color: label),
            ),
          ],
        ),
      );
      cells.add(
        Expanded(
          child: Semantics(
            label: '${fact.value} ${fact.label}',
            button: fact.onTap != null,
            excludeSemantics: true,
            child: fact.onTap == null
                ? cell
                : InkWell(onTap: fact.onTap, child: cell),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: rule),
          bottom: BorderSide(color: rule),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: cells,
        ),
      ),
    );
  }
}

/// The front of the pack: the flat teal band that opens a primary screen.
///
/// One per screen. It carries who and where (the [title] and [subtitle]),
/// the screen's actions, and — when the screen has one number that matters
/// more than everything else — that number, printed large and narrow the
/// way a pack prints its product name, with a [DeclarationStrip] of the
/// facts that qualify it.
///
/// Flat colour, white type, nothing else: no gradient, no glow, no
/// decorative circles. The band reaches under the status bar so the top of
/// the phone reads as one printed field.
class PackHeader extends StatelessWidget {
  const PackHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
    this.figure,
    this.figureCaption,
    this.facts = const <PackFact>[],
    this.bottom,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// The screen's one number, already styled or a [Text]. Printed in the
  /// display style on the band's ink unless the widget sets its own.
  final Widget? figure;
  final String? figureCaption;

  final List<PackFact> facts;

  /// Anything that belongs on the band below the facts — a search field.
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Material(
      color: colors.band,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter,
            v360.spacing.sm,
            v360.spacing.xs,
            figure == null && facts.isEmpty && bottom == null
                ? v360.spacing.md
                : v360.spacing.lg,
          ),
          child: IconTheme.merge(
            data: IconThemeData(color: colors.onBand),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      if (leading != null) ...<Widget>[
                        leading!,
                        SizedBox(width: v360.spacing.sm),
                      ],
                      Expanded(
                        child: Semantics(
                          header: true,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: v360.text.titleM
                                    .copyWith(color: colors.onBand)
                                    .weight(FontWeight.w700),
                              ),
                              if (subtitle != null)
                                Text(
                                  subtitle!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: v360.text.caption
                                      .copyWith(color: colors.onBandMuted),
                                ),
                            ],
                          ),
                        ),
                      ),
                      ...actions,
                    ],
                  ),
                ),
                if (figure != null) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  Padding(
                    padding: EdgeInsets.only(right: v360.spacing.md),
                    child: DefaultTextStyle.merge(
                      style: v360.text.display.copyWith(color: colors.onBand),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: figure!,
                      ),
                    ),
                  ),
                  if (figureCaption != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        figureCaption!,
                        style: v360.text.body
                            .copyWith(color: colors.onBandMuted),
                      ),
                    ),
                ],
                if (facts.isNotEmpty) ...<Widget>[
                  SizedBox(height: v360.spacing.lg),
                  Padding(
                    padding: EdgeInsets.only(right: v360.spacing.md),
                    child: DeclarationStrip(facts: facts, onBand: true),
                  ),
                ],
                if (bottom != null) ...<Widget>[
                  SizedBox(height: v360.spacing.md),
                  Padding(
                    padding: EdgeInsets.only(right: v360.spacing.md),
                    child: bottom!,
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
