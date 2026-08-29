import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_elevation.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

@immutable
class V360NavItem {
  const V360NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// The floating pill navigation bar from the design.
///
/// The active item is mint; its icon pops slightly on selection, which is
/// enough feedback without a heavier transition.
class V360BottomNav extends StatelessWidget {
  const V360BottomNav({
    super.key,
    required this.items,
    required this.index,
    required this.onChanged,
  });

  final List<V360NavItem> items;
  final int index;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Container(
      margin: EdgeInsets.all(v360.spacing.lg),
      padding: EdgeInsets.symmetric(vertical: v360.spacing.md),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(V360Radius.xl),
        border: v360.isDark ? Border.all(color: colors.hairline) : null,
        boxShadow: V360Elevation.floating(v360.brightness),
      ),
      child: Row(
        children: <Widget>[
          // Slots share the width equally rather than sizing to content,
          // so five items with longer labels still fit a 390px phone.
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: _NavSlot(
                item: items[i],
                selected: i == index,
                onTap: () => onChanged(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavSlot extends StatelessWidget {
  const _NavSlot({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final V360NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final motion = MotionScope.of(context);
    final content = selected ? v360.colors.accentText : v360.colors.inkMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: v360.spacing.xs),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 1, end: selected ? 1.12 : 1.0),
                duration: motion.fast,
                curve: motion.standard,
                builder: (context, scale, child) =>
                    Transform.scale(scale: scale, child: child),
                child: Icon(item.icon, size: 22, color: content),
              ),
              SizedBox(height: v360.spacing.xs),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: v360.text.caption.copyWith(
                  color: content,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
