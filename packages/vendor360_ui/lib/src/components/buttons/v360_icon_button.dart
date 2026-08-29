import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// A circular icon button with a hairline border.
///
/// Used for the swap, stepper and back affordances in the design.
class V360IconButton extends StatefulWidget {
  const V360IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.filled = false,
    this.semanticLabel,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  /// When true the button uses `actionFill` instead of a hairline outline.
  final bool filled;

  final String? semanticLabel;

  bool get isEnabled => onPressed != null;

  @override
  State<V360IconButton> createState() => _V360IconButtonState();
}

class _V360IconButtonState extends State<V360IconButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;
    final motion = MotionScope.of(context);
    final enabled = widget.isEnabled;

    final fill = widget.filled ? colors.actionFill : colors.surface;
    final content = widget.filled ? colors.onActionFill : colors.ink;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.92 : 1.0,
          duration: motion.fast,
          curve: motion.standard,
          child: Container(
            height: widget.size,
            width: widget.size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              shape: BoxShape.circle,
              border: widget.filled ? null : Border.all(color: colors.hairline),
            ),
            child: Icon(
              widget.icon,
              size: widget.size * 0.42,
              color: enabled ? content : colors.inkSubtle,
            ),
          ),
        ),
      ),
    );
  }
}
