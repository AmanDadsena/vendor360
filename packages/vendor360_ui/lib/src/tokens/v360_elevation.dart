import 'package:flutter/widgets.dart';

/// Card and surface elevation.
///
/// Light mode uses a soft shadow. Dark mode uses none — on a near-black
/// canvas a shadow reads as mud, so separation comes from a hairline border
/// instead.
abstract final class V360Elevation {
  static List<BoxShadow> card(Brightness brightness) {
    if (brightness == Brightness.dark) return const <BoxShadow>[];
    return const <BoxShadow>[
      BoxShadow(
        color: Color(0x0F0A0D0C),
        blurRadius: 8,
        offset: Offset(0, 2),
      ),
    ];
  }

  /// A deeper shadow for floating elements — bottom nav, sticky CTAs.
  static List<BoxShadow> floating(Brightness brightness) {
    if (brightness == Brightness.dark) return const <BoxShadow>[];
    return const <BoxShadow>[
      BoxShadow(
        color: Color(0x140A0D0C),
        blurRadius: 20,
        offset: Offset(0, 6),
      ),
    ];
  }
}
