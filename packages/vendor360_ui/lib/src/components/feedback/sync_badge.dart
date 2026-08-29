import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// Offline sync indicator.
///
/// Buses lose signal on highways, so scans queue locally and flush when
/// signal returns (roadmap §8, item 1). This badge is the crew's assurance
/// that queued work is not lost — it breathes while items are pending and
/// collapses to nothing when the queue drains.
class SyncBadge extends StatefulWidget {
  const SyncBadge({super.key, required this.queued, this.syncing = false});

  final int queued;
  final bool syncing;

  @override
  State<SyncBadge> createState() => _SyncBadgeState();
}

class _SyncBadgeState extends State<SyncBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  @override
  void initState() {
    super.initState();
    if (widget.queued > 0) _pulse.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(SyncBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.queued > 0 && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (widget.queued == 0 && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.queued == 0) return const SizedBox.shrink();

    final v360 = context.v360;
    final colors = v360.colors;
    final reduced = MotionScope.of(context).reduced;

    // Breathes for as long as the queue is non-empty, which on a highway
    // can be the whole trip.
    return RepaintBoundary(
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.md,
          vertical: v360.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: colors.warningSurface,
          borderRadius: BorderRadius.circular(V360Radius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Opacity(
                opacity: reduced ? 1.0 : 0.45 + (_pulse.value * 0.55),
                child: child,
              ),
              child: Icon(
                widget.syncing ? Icons.sync : Icons.cloud_off_outlined,
                size: 14,
                color: colors.warningText,
              ),
            ),
            SizedBox(width: v360.spacing.sm),
            Text(
              widget.syncing
                  ? 'Syncing ${widget.queued}'
                  : '${widget.queued} queued',
              style: v360.text.caption.copyWith(
                color: colors.warningText,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
