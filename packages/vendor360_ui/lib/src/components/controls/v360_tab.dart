import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import 'v360_pressable.dart';

/// A printed filter tab — the small ruled box a category or status filter
/// sits in, ink when chosen.
///
/// One component for every filter row in the app, so Stock's categories,
/// the order filters and the map's categories are the same size, the same
/// type and the same ink, instead of three near-copies drifting apart.
/// It centres itself at 36dp inside whatever height its row gives it.
class V360Tab extends StatelessWidget {
  const V360Tab({
    super.key,
    required this.label,
    required this.active,
    required this.onTap,
    this.marker,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  /// A status square printed before the label while the tab is off — the
  /// marigold square on "Running out".
  final Color? marker;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Center(
      child: Semantics(
        button: true,
        selected: active,
        label: label,
        excludeSemantics: true,
        child: V360Pressable(
          onTap: onTap,
          borderRadius: BorderRadius.circular(V360Radius.sm),
          child: Container(
            height: 36,
            alignment: Alignment.center,
            padding: EdgeInsets.symmetric(horizontal: v360.spacing.md),
            decoration: BoxDecoration(
              color: active ? colors.ink : colors.surface,
              borderRadius: BorderRadius.circular(V360Radius.sm),
              border: Border.all(color: active ? colors.ink : colors.hairline),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (marker != null && !active) ...<Widget>[
                  Container(width: 7, height: 7, color: marker),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: v360.text.caption
                      .copyWith(color: active ? colors.canvas : colors.ink)
                      .weight(FontWeight.w600),
                  strutStyle: v360Strut(v360.text.caption),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
