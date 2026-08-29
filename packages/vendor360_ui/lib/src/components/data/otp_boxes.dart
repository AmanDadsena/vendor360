import 'package:flutter/material.dart';

import '../../motion/motion_scope.dart';
import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

enum OtpState { idle, success, error }

/// Digit boxes for the handover OTP.
///
/// Used both to display a code (the sender's pass) and to enter one (the
/// conductor confirming delivery). Digits use the `code` style so they stay
/// monospaced-feeling and aligned.
class OtpBoxes extends StatelessWidget {
  const OtpBoxes({
    super.key,
    required this.value,
    this.length = 6,
    this.state = OtpState.idle,
    this.boxSize = const Size(44, 54),
  });

  final String value;
  final int length;
  final OtpState state;
  final Size boxSize;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final (Color border, Color fill, Color ink) = switch (state) {
      OtpState.idle => (colors.hairline, colors.surfaceMuted, colors.ink),
      OtpState.success => (
        colors.accent,
        colors.accentSurface,
        colors.accentText,
      ),
      OtpState.error => (
        colors.danger,
        colors.dangerSurface,
        colors.dangerText,
      ),
    };

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (var i = 0; i < length; i++) ...<Widget>[
          if (i > 0) SizedBox(width: v360.spacing.sm),
          AnimatedContainer(
            duration: motion.base,
            curve: motion.standard,
            width: boxSize.width,
            height: boxSize.height,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(V360Radius.sm),
              border: Border.all(color: border, width: 1.5),
            ),
            child: Text(
              i < value.length ? value[i] : '',
              style: v360.text.titleM.copyWith(color: ink),
            ),
          ),
        ],
      ],
    );
  }
}
