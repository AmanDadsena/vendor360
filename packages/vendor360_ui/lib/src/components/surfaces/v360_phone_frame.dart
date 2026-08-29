import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// Keeps a phone-shaped surface phone-shaped on a wider viewport.
///
/// The conductor and driver screens are laid out to a 390pt canvas — fixed
/// gutters, cards that fill the width, a route strip whose endpoints hug the
/// edges. Let loose in a desktop browser those stretch to 1400pt and the
/// design comes apart: a capacity meter becomes a hairline, and a trip's
/// departure and arrival end up a foot apart.
///
/// This is deliberately **not** applied to the operator console. A conductor
/// is standing at a bus with a phone; a fleet owner is at a desk, and framing
/// their dashboard to 390pt would waste the screen the job actually needs.
///
/// Below [breakpoint] it is a no-op, so real phones and small windows are
/// untouched.
class V360PhoneFrame extends StatelessWidget {
  const V360PhoneFrame({super.key, required this.child});

  final Widget child;

  /// The design's canvas width.
  static const double frameWidth = 390;

  /// Anything narrower is treated as a phone and left alone. Sits above the
  /// widest common handset (about 430pt) so no real device gets framed.
  static const double breakpoint = 480;

  /// The tallest the frame grows before it stops and centres. Keeps the
  /// device believable on a tall monitor instead of stretching a phone into
  /// a ribbon.
  static const double maxFrameHeight = 900;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < breakpoint) return child;

        final media = MediaQuery.of(context);
        final frameHeight = constraints.maxHeight > maxFrameHeight
            ? maxFrameHeight
            : constraints.maxHeight;

        // Dark's canvas is already near-black, so it needs true black behind
        // it to read as a separate surface. Light gets its own ink at a low
        // alpha rather than a colour that is in no token.
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final backdrop = isDark
            ? const Color(0xFF000000)
            : Color.alphaBlend(
                colors.ink.withValues(alpha: 0.10),
                colors.canvas,
              );

        return ColoredBox(
          color: backdrop,
          child: Center(
            child: SizedBox(
              width: frameWidth,
              height: frameHeight,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.canvas,
                  borderRadius: BorderRadius.circular(v360.spacing.lg),
                  border: Border.all(color: colors.hairline),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.18),
                      blurRadius: 32,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(v360.spacing.lg),
                  // Screens read MediaQuery for safe-area insets and for
                  // their own breakpoints. Left reporting the whole window
                  // they would size against 1400pt rather than the frame —
                  // which is how a "mobile" layout ends up laying itself out
                  // for a desktop it cannot see.
                  child: MediaQuery(
                    data: media.copyWith(
                      size: Size(frameWidth, frameHeight),
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
