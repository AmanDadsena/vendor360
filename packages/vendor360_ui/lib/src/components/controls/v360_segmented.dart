import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// One option in a [V360Segmented] row.
@immutable
class V360Segment<T> {
  const V360Segment({
    required this.value,
    required this.label,
    this.sublabel,
    this.icon,
  });

  final T value;
  final String label;

  /// Renders a second line, as on the Small / Medium / Large size chips.
  final String? sublabel;
  final IconData? icon;
}

/// A row of pill chips with single selection.
///
/// The selected chip uses `actionFill`, so it is black in light mode and
/// mint in dark mode — the same inversion as the primary button.
class V360Segmented<T> extends StatelessWidget {
  const V360Segmented({
    super.key,
    required this.segments,
    required this.value,
    required this.onChanged,
    this.scrollable = false,
  });

  final List<V360Segment<T>> segments;
  final T value;
  final ValueChanged<T> onChanged;
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final children = <Widget>[];

    for (var i = 0; i < segments.length; i++) {
      if (i > 0) children.add(SizedBox(width: v360.spacing.md));
      children.add(
        _Chip<T>(
          segment: segments[i],
          selected: segments[i].value == value,
          onTap: () {
            if (segments[i].value != value) onChanged(segments[i].value);
          },
        ),
      );
    }

    if (scrollable) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _Chip<T> extends StatelessWidget {
  const _Chip({
    required this.segment,
    required this.selected,
    required this.onTap,
  });

  final V360Segment<T> segment;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final fill = selected ? colors.actionFill : colors.surface;
    final content = selected ? colors.onActionFill : colors.ink;
    final subContent = selected
        ? colors.onActionFill.withValues(alpha: 0.7)
        : colors.inkMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: segment.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: motion.base,
          curve: motion.standard,
          padding: EdgeInsets.symmetric(
            horizontal: v360.spacing.xl,
            vertical: segment.sublabel == null ? 12 : 10,
          ),
          decoration: BoxDecoration(
            color: fill,
            border: selected ? null : Border.all(color: colors.hairline),
            borderRadius: BorderRadius.circular(V360Radius.pill),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (segment.icon != null) ...<Widget>[
                    Icon(segment.icon, size: 16, color: content),
                    SizedBox(width: v360.spacing.sm),
                  ],
                  Text(
                    segment.label,
                    style: v360.text.bodyStrong.copyWith(color: content),
                  ),
                ],
              ),
              if (segment.sublabel != null)
                Text(
                  segment.sublabel!,
                  style: v360.text.caption.copyWith(color: subContent),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
