import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// The heading that opens a section — "Running out", "Today's orders".
///
/// A real heading, in ink and in the case it was written: the small grey
/// letterspaced uppercase label that used to sit here is the eyebrow every
/// generated dashboard wears, and it made each section whisper its name
/// instead of saying it. Uppercasing also does nothing for Devanagari, so
/// in the default language the old treatment was just small grey text.
///
/// [action] sits at the far end of the row — a "See all" link, a count.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color, this.action});

  final String text;
  final Color? color;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final heading = Text(
      text,
      style: v360.text.titleS
          .copyWith(color: color ?? v360.colors.ink)
          .weight(FontWeight.w700)
          .narrow(92),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    final label = Semantics(header: true, child: heading);
    if (action == null) return label;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        Expanded(child: label),
        action!,
      ],
    );
  }
}
