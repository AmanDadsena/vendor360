import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_theme.dart';

/// A round icon button.
///
/// Plain by default — an icon with a 48dp round target and a pressed wash,
/// the way Android's own icon buttons behave — rather than an icon inside a
/// hairline circle, which is decoration every generated screen repeats.
/// [filled] prints it as a solid teal disc for the one icon action that
/// matters on a screen. [color] recolours the icon, for buttons sitting on
/// the teal band.
class V360IconButton extends StatefulWidget {
  const V360IconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.filled = false,
    this.semanticLabel,
    this.color,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;

  /// When true the button uses `actionFill` instead of a hairline outline.
  final bool filled;

  final String? semanticLabel;

  /// Icon colour override — `colors.onBand` on the band.
  final Color? color;

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

    final content =
        widget.color ?? (widget.filled ? colors.onActionFill : colors.ink);
    final Color fill;
    if (widget.filled) {
      fill = _pressed
          ? Color.alphaBlend(colors.ink.withValues(alpha: 0.14),
              colors.actionFill)
          : colors.actionFill;
    } else {
      fill = _pressed
          ? content.withValues(alpha: 0.12)
          : const Color(0x00000000);
    }

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
        child: AnimatedContainer(
          duration: motion.fast,
          curve: motion.standard,
          height: widget.size,
          width: widget.size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          child: Icon(
            widget.icon,
            size: widget.size * 0.46,
            color: enabled ? content : colors.inkSubtle,
          ),
        ),
      ),
    );
  }
}
