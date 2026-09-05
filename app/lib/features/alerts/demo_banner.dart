import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';

/// Says out loud that the activity on screen is simulated.
///
/// The demo pulse writes real transactions — it has to, or the heatmap would
/// not move — which means the numbers changing in front of someone describe
/// events that did not happen. That is fine for a demonstration and dishonest
/// without a label, so this is deliberately hard to miss: full width, saffron,
/// pinned above the content rather than tucked into a corner.
///
/// It renders nothing at all when the pulse is off, which is every case except
/// a machine that was explicitly started with `DEMO_MODE=1`.
class DemoBanner extends ConsumerWidget {
  const DemoBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final running = ref.watch(demoPulseProvider).value?.running ?? false;
    if (!running) return const SizedBox.shrink();

    final v360 = context.v360;
    final colors = v360.colors;

    return Semantics(
      liveRegion: true,
      label: 'Demo mode. The activity on screen is simulated, not real sales.',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        color: colors.voice,
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.md,
          vertical: v360.spacing.xs,
        ),
        child: SafeArea(
          bottom: false,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.science_outlined, size: 13, color: colors.onFill),
              SizedBox(width: v360.spacing.xs),
              Text(
                'DEMO MODE · simulated activity',
                style: v360.text.label.copyWith(
                  color: colors.onFill,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
