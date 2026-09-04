import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../data/live_connection.dart';

/// Whether the app is currently being told about changes.
///
/// Small, and load-bearing. A screen that has silently stopped receiving
/// updates looks exactly like a quiet afternoon, and the difference matters:
/// one means nothing is happening, the other means you are not being told what
/// is. Showing the state removes the guess.
///
/// Pulses only while live, and only when motion is allowed — a permanently
/// animating dot in the corner of every screen is a distraction, and on
/// reduce-motion it is worse than that.
class LiveDot extends ConsumerWidget {
  const LiveDot({super.key, this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final status = ref.watch(liveStatusProvider).value ?? LiveStatus.offline;

    final (Color tint, String label) = switch (status) {
      LiveStatus.live => (colors.accent, 'Live'),
      LiveStatus.reconnecting => (colors.warning, 'Reconnecting'),
      LiveStatus.offline => (colors.inkSubtle, 'Not live'),
    };

    return Semantics(
      label: switch (status) {
        LiveStatus.live => 'Live. Updates arrive as they happen.',
        LiveStatus.reconnecting =>
          'Reconnecting. Showing the last data loaded.',
        LiveStatus.offline => 'Not connected. Showing the last data loaded.',
      },
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _Pulse(tint: tint, animate: status == LiveStatus.live),
          if (showLabel) ...<Widget>[
            SizedBox(width: v360.spacing.xs),
            Text(
              label,
              style: v360.text.label.copyWith(color: colors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class _Pulse extends StatefulWidget {
  const _Pulse({required this.tint, required this.animate});

  final Color tint;
  final bool animate;

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    // Resolved through MotionScope rather than checked per-widget, so the
    // platform's reduce-motion setting is honoured in one place.
    final allowed = !MotionScope.of(context).reduced;
    if (widget.animate && allowed) {
      if (!_controller.isAnimating) _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 1;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = 0.45 + (_controller.value * 0.55);
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: widget.tint.withValues(alpha: t),
            shape: BoxShape.circle,
            boxShadow: widget.animate
                ? <BoxShadow>[
                    BoxShadow(
                      color: widget.tint.withValues(alpha: 0.35 * t),
                      blurRadius: 6,
                      spreadRadius: 1.5,
                    ),
                  ]
                : null,
          ),
        );
      },
    );
  }
}

/// The unread-alert bell.
///
/// Placed on each shell's home screen rather than in a persistent app bar,
/// because neither shell has one — screens own their headers here, and adding
/// chrome just to hold a bell would cost vertical space on every screen to
/// serve one.
class AlertBell extends ConsumerWidget {
  const AlertBell({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final unread = ref.watch(alertsProvider).value?.unread ?? 0;

    return Semantics(
      button: true,
      label: unread == 0 ? 'Alerts' : 'Alerts, $unread unread',
      excludeSemantics: true,
      child: V360Pressable(
        onTap: onTap,
        child: Stack(
          clipBehavior: Clip.none,
          children: <Widget>[
            SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                unread > 0
                    ? Icons.notifications_active_rounded
                    : Icons.notifications_none_rounded,
                size: 22,
                color: unread > 0 ? colors.voiceText : colors.inkMuted,
              ),
            ),
            if (unread > 0)
              Positioned(
                right: 4,
                top: 4,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: colors.danger,
                    borderRadius: BorderRadius.circular(V360Radius.pill),
                    border: Border.all(color: colors.surface, width: 1.5),
                  ),
                  child: Text(
                    unread > 9 ? '9+' : '$unread',
                    style: v360.text.label.copyWith(
                      color: colors.onFill,
                      fontSize: 9,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
