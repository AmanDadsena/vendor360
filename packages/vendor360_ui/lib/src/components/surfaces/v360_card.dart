import 'package:flutter/material.dart';

import '../../tokens/v360_elevation.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';
import '../controls/v360_pressable.dart';

/// The Vendor360 card surface.
///
/// Light mode carries a soft shadow; dark mode uses a hairline border
/// instead, because a shadow on a near-black canvas reads as mud.
class V360Card extends StatelessWidget {
  const V360Card({
    super.key,
    required this.child,
    this.padding,
    this.radius = V360Radius.xl,
    this.onTap,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final VoidCallback? onTap;

  /// Overrides the surface colour. Pass a token, never a literal.
  final Color? color;

  /// What a tappable card announces. Without it a reader falls back to
  /// reading every string inside, which on a dense card is a paragraph where
  /// a name would do.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final card = Container(
      padding: padding ?? EdgeInsets.all(v360.spacing.xl),
      decoration: BoxDecoration(
        color: color ?? colors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: v360.isDark ? Border.all(color: colors.hairline) : null,
        boxShadow: V360Elevation.card(v360.brightness),
      ),
      child: child,
    );

    if (onTap == null) return card;

    // Through V360Pressable rather than a bare GestureDetector, so a card
    // acknowledges the finger. `soft` because a full-width surface that
    // shrinks as hard as a chip looks broken, and `highlight` because on a
    // stack of cards the scale alone does not say which one was hit.
    return V360Pressable(
      onTap: onTap,
      feel: V360PressFeel.soft,
      highlight: true,
      borderRadius: BorderRadius.circular(radius),
      semanticLabel: semanticLabel,
      child: card,
    );
  }
}
