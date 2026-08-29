import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// A small uppercase, letterspaced section label.
///
/// Uppercasing happens here rather than at call sites, so the design's
/// treatment cannot be forgotten and the source string stays readable.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Text(
      text.toUpperCase(),
      style: v360.text.label.copyWith(color: color ?? v360.colors.inkSubtle),
    );
  }
}
