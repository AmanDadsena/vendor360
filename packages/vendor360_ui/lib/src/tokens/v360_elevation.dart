import 'package:flutter/widgets.dart';

/// Depth, the way print has it: almost none.
///
/// A panel on a printed pack is separated from the next by a rule, not by
/// being lifted off the board, so [card] is empty in both themes — panels
/// carry a hairline border instead. Only things that genuinely float over
/// the page — a bottom sheet, a menu, a dragged row — get [floating], and
/// that shadow has an offset and a soft blur like a real object's, never a
/// coloured halo.
abstract final class V360Elevation {
  static List<BoxShadow> card(Brightness brightness) => const <BoxShadow>[];

  /// For surfaces that float over the page. None in dark mode, where a
  /// shadow on a near-black canvas reads as mud.
  static List<BoxShadow> floating(Brightness brightness) {
    if (brightness == Brightness.dark) return const <BoxShadow>[];
    return const <BoxShadow>[
      BoxShadow(
        color: Color(0x2410201C),
        blurRadius: 18,
        offset: Offset(0, 6),
      ),
    ];
  }
}
