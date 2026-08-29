import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

/// The microphone action.
///
/// The UI/UX guide makes this the most prominent control on any data-entry
/// screen, in a fixed thumb-reachable position, with a pulsing state to
/// confirm active listening. It is saffron rather than teal because it is the
/// one action the product is built around, and it reads on the `voice` token
/// so a stock alert can never accidentally borrow the same colour.
///
/// The listening animation is two expanding rings behind the button rather
/// than a scaling button: the target must not move while a finger is on it,
/// and a control that grows under the thumb reads as a misfire.
class VoiceOrb extends StatefulWidget {
  const VoiceOrb({
    super.key,
    required this.onTap,
    this.listening = false,
    this.processing = false,
    this.size = 88,
    this.label,
  });

  final VoidCallback? onTap;

  /// Actively capturing speech.
  final bool listening;

  /// Speech captured, transcription in flight.
  final bool processing;

  final double size;

  /// Announced to screen readers and shown beneath the orb.
  final String? label;

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  );

  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.listening) _pulse.repeat();
  }

  @override
  void didUpdateWidget(VoiceOrb old) {
    super.didUpdateWidget(old);
    if (widget.listening && !_pulse.isAnimating) {
      _pulse.repeat();
    } else if (!widget.listening && _pulse.isAnimating) {
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
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);
    final enabled = widget.onTap != null;

    final icon = widget.processing
        ? Icons.graphic_eq_rounded
        : widget.listening
            ? Icons.mic_rounded
            : Icons.mic_none_rounded;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label ??
          (widget.listening ? 'Listening, tap to stop' : 'Tap to speak'),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: widget.size * 1.9,
            height: widget.size * 1.9,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Rings are painted behind and are non-interactive, so they can
                // extend past the button without enlarging the tap target.
                if (widget.listening && !motion.reduced)
                  AnimatedBuilder(
                    animation: _pulse,
                    builder: (context, _) => CustomPaint(
                      size: Size.square(widget.size * 1.9),
                      painter: _RingPainter(
                        progress: _pulse.value,
                        color: colors.voice,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
                  onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
                  onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
                  onTap: widget.onTap,
                  child: AnimatedScale(
                    scale: _pressed ? 0.94 : 1.0,
                    duration: motion.fast,
                    curve: motion.standard,
                    child: Container(
                      width: widget.size,
                      height: widget.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: enabled ? colors.voice : colors.surfaceMuted,
                        boxShadow: enabled
                            ? <BoxShadow>[
                                BoxShadow(
                                  color: colors.voice.withValues(alpha: 0.34),
                                  blurRadius: widget.listening ? 28 : 16,
                                  offset: const Offset(0, 6),
                                ),
                              ]
                            : null,
                      ),
                      child: Icon(
                        icon,
                        size: widget.size * 0.42,
                        color: enabled ? Colors.white : colors.inkSubtle,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.label != null) ...<Widget>[
            SizedBox(height: v360.spacing.sm),
            Text(
              widget.label!,
              style: v360.text.caption.copyWith(color: colors.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Two rings expanding out of phase, so the pulse reads as continuous rather
/// than as a single ring restarting.
class _RingPainter extends CustomPainter {
  _RingPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final minRadius = size.width * 0.26;
    final maxRadius = size.width * 0.5;

    for (final offset in <double>[0.0, 0.5]) {
      final t = (progress + offset) % 1.0;
      final radius = minRadius + (maxRadius - minRadius) * t;
      // Fade out as it expands, so the ring dissolves instead of clipping at
      // the edge of the box.
      final opacity = (1.0 - t) * 0.45;

      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: opacity.clamp(0.0, 1.0)),
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

/// A compact microphone for app bars and list rows.
class VoiceOrbMini extends StatelessWidget {
  const VoiceOrbMini({super.key, required this.onTap, this.listening = false});

  final VoidCallback? onTap;
  final bool listening;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Semantics(
      button: true,
      label: 'Tap to speak',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: v360.spacing.lg,
            vertical: v360.spacing.md,
          ),
          decoration: BoxDecoration(
            color: v360.colors.voiceSurface,
            borderRadius: BorderRadius.circular(V360Radius.pill),
            border: Border.all(color: v360.colors.voice.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                size: 18,
                color: v360.colors.voiceText,
              ),
              SizedBox(width: v360.spacing.sm),
              Text(
                listening ? 'Listening…' : 'Speak',
                style: v360.text.bodyStrong.copyWith(color: v360.colors.voiceText),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
