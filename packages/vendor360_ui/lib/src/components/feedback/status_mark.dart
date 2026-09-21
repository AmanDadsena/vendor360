import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// A status, printed the way a pack prints one: a small solid square of
/// colour beside a word in ink.
///
/// Colour lives only in the square. The word stays ink, so "Out of stock"
/// is as readable as the item name next to it — tinted red or amber text on
/// a tinted pill is the thing that fails first in sunlight. And because the
/// word is always there, colour is never the only signal.
///
/// Pass [icon] to draw a glyph in the status colour instead of the square,
/// where the kind of status matters more than its level (a clock for
/// "due today").
class StatusMark extends StatelessWidget {
  const StatusMark({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.dense = false,
    this.emphasis = true,
  });

  final String label;

  /// The status colour — a token such as `colors.danger`.
  final Color color;

  final IconData? icon;
  final bool dense;

  /// Bold label. Off for a status that should sit quietly in a meta line.
  final bool emphasis;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final size = dense ? 7.0 : 8.0;
    final style = (dense ? v360.text.label : v360.text.caption)
        .copyWith(color: v360.colors.ink)
        .weight(emphasis ? FontWeight.w600 : FontWeight.w400);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (icon != null)
          Icon(icon, size: dense ? 12 : 14, color: color)
        else
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
        SizedBox(width: dense ? 5 : 6),
        Flexible(
          child: Text(
            label,
            style: style,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
