import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import 'providers.dart';

/// Makes a phone-first app behave on a wide screen.
///
/// Every layout in this product was drawn for a handset, and stretched across
/// a 1440px browser they fall apart in the ordinary way: cards a metre wide,
/// two words of label marooned from their value, line lengths well past what
/// anyone reads comfortably.
///
/// The two audiences want opposite things about it, so this resolves on role
/// rather than picking one:
///
/// * A **shop** is a phone product. Someone opening it on a laptop is
///   demoing or doing paperwork, and the honest presentation is the phone
///   itself — so it gets [V360PhoneFrame], which was built for exactly this
///   and had never been wired in.
/// * A **wholesaler** works at a desk. Framing their order book as a handset
///   would be a costume; they get the real width, capped where lines stop
///   being readable, so the density they need survives.
class AdaptiveFrame extends ConsumerWidget {
  const AdaptiveFrame({super.key, required this.child});

  final Widget child;

  /// Past this, a text column stops being comfortable to read and a row of
  /// two stat tiles starts looking like a mistake. Wider than the phone frame
  /// because a console legitimately wants more.
  static const double consoleMaxWidth = 1100;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Signed out, the onboarding screen already caps itself, and a phone
    // frame around a sign-in form is just a smaller sign-in form.
    final session = ref.watch(sessionProvider);
    if (!session.isSignedIn) return child;

    if (session.isDistributor) return _Console(child: child);
    return V360PhoneFrame(child: child);
  }
}

class _Console extends StatelessWidget {
  const _Console({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.v360.colors;

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth <= AdaptiveFrame.consoleMaxWidth) return child;

        return ColoredBox(
          // The gutter reads as deliberate margin rather than as the app
          // failing to fill the window.
          color: Color.alphaBlend(
            colors.ink.withValues(alpha: 0.05),
            colors.canvas,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AdaptiveFrame.consoleMaxWidth,
              ),
              // The child is a Scaffold, so it paints its own canvas across
              // the capped width and the bottom nav stays inside it.
              child: child,
            ),
          ),
        );
      },
    );
  }
}
