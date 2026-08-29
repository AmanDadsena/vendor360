import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';
import 'v360_card.dart';

/// A card whose rows are separated by hairline dividers.
///
/// This is the FROM / TO / DEPARTS / WEIGHT / SIZE pattern from the design.
/// Dividers span the full card width, so row padding is applied inside each
/// row rather than on the card.
class V360StackCard extends StatelessWidget {
  const V360StackCard({
    super.key,
    required this.rows,
    this.rowPadding = const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
  });

  final List<Widget> rows;
  final EdgeInsetsGeometry rowPadding;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    final children = <Widget>[];

    for (var i = 0; i < rows.length; i++) {
      children.add(Padding(padding: rowPadding, child: rows[i]));
      if (i != rows.length - 1) {
        children.add(Container(height: 1, color: colors.hairline));
      }
    }

    return V360Card(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    );
  }
}
