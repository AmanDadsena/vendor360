import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// Heights for the three button sizes.
enum V360ButtonSize { sm, md, lg }

enum V360ButtonVariant { primary, secondary, ghost, danger }

/// The Vendor360 pill button.
///
/// The primary variant is **near-black in light mode and azure in dark mode**. That
/// inversion lives in the `actionFill` token — never hardcode either colour.
class V360Button extends StatefulWidget {
  const V360Button._({
    super.key,
    required this.label,
    required this.onPressed,
    required this.variant,
    this.size = V360ButtonSize.lg,
    this.leadingIcon,
    this.trailingIcon,
    this.loading = false,
    this.expand = false,
  });

  const V360Button.primary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    V360ButtonSize size = V360ButtonSize.lg,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool loading = false,
    bool expand = false,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         variant: V360ButtonVariant.primary,
         size: size,
         leadingIcon: leadingIcon,
         trailingIcon: trailingIcon,
         loading: loading,
         expand: expand,
       );

  const V360Button.secondary({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    V360ButtonSize size = V360ButtonSize.lg,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool loading = false,
    bool expand = false,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         variant: V360ButtonVariant.secondary,
         size: size,
         leadingIcon: leadingIcon,
         trailingIcon: trailingIcon,
         loading: loading,
         expand: expand,
       );

  const V360Button.ghost({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    V360ButtonSize size = V360ButtonSize.lg,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool expand = false,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         variant: V360ButtonVariant.ghost,
         size: size,
         leadingIcon: leadingIcon,
         trailingIcon: trailingIcon,
         expand: expand,
       );

  const V360Button.danger({
    Key? key,
    required String label,
    required VoidCallback? onPressed,
    V360ButtonSize size = V360ButtonSize.lg,
    IconData? leadingIcon,
    IconData? trailingIcon,
    bool loading = false,
    bool expand = false,
  }) : this._(
         key: key,
         label: label,
         onPressed: onPressed,
         variant: V360ButtonVariant.danger,
         size: size,
         leadingIcon: leadingIcon,
         trailingIcon: trailingIcon,
         loading: loading,
         expand: expand,
       );

  final String label;
  final VoidCallback? onPressed;
  final V360ButtonVariant variant;
  final V360ButtonSize size;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool loading;
  final bool expand;

  bool get isEnabled => onPressed != null && !loading;

  @override
  State<V360Button> createState() => _V360ButtonState();
}

class _V360ButtonState extends State<V360Button> {
  bool _pressed = false;

  double get _height => switch (widget.size) {
    V360ButtonSize.sm => 40,
    V360ButtonSize.md => 48,
    V360ButtonSize.lg => 56,
  };

  double get _padding => switch (widget.size) {
    V360ButtonSize.sm => 16,
    V360ButtonSize.md => 20,
    V360ButtonSize.lg => 24,
  };

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final Color fill;
    final Color content;
    Border? border;

    switch (widget.variant) {
      case V360ButtonVariant.primary:
        fill = colors.actionFill;
        content = colors.onActionFill;
      case V360ButtonVariant.secondary:
        fill = colors.surface;
        content = colors.ink;
        border = Border.all(color: colors.hairline);
      case V360ButtonVariant.ghost:
        fill = const Color(0x00000000);
        content = colors.accentText;
      case V360ButtonVariant.danger:
        fill = colors.danger;
        content = const Color(0xFFFFFFFF);
    }

    final enabled = widget.isEnabled;
    final effectiveFill = enabled
        ? fill
        : Color.alphaBlend(fill.withValues(alpha: 0.35), colors.canvas);
    final effectiveContent = enabled ? content : colors.inkSubtle;

    final Widget inner = widget.loading
        ? SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(effectiveContent),
            ),
          )
        : Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.leadingIcon != null) ...<Widget>[
                Icon(widget.leadingIcon, size: 18, color: effectiveContent),
                const SizedBox(width: 8),
              ],
              // Flexible so a long label ellipsizes rather than overflowing
              // the pill — and so an expanded button cannot round its way
              // into a sub-pixel overflow.
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: v360.text.bodyStrong.copyWith(
                    color: effectiveContent,
                  ),
                ),
              ),
              if (widget.trailingIcon != null) ...<Widget>[
                const SizedBox(width: 8),
                Icon(widget.trailingIcon, size: 18, color: effectiveContent),
              ],
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      // Without this the inner Text contributes its own node and the label
      // merges to "Accept parcel\nAccept parcel" — screen readers announce
      // it twice. Excluding the subtree makes the announced label exactly
      // what we intend, and keeps icons and the spinner out of it.
      excludeSemantics: true,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: motion.fast,
          curve: motion.standard,
          child: AnimatedContainer(
            duration: motion.base,
            curve: motion.standard,
            height: _height,
            width: widget.expand ? double.infinity : null,
            padding: EdgeInsets.symmetric(horizontal: _padding),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: effectiveFill,
              border: border,
              borderRadius: BorderRadius.circular(V360Radius.pill),
            ),
            child: inner,
          ),
        ),
      ),
    );
  }
}
