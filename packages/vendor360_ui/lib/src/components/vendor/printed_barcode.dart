import 'package:flutter/material.dart';

import '../../tokens/v360_theme.dart';

/// The EAN-13 encoder, separated from the painting so it can be tested
/// without a canvas.
///
/// This is the real encoding, not a decorative pattern of stripes: 95 modules
/// made of a start guard, six left digits whose parity is chosen by the first
/// digit, a centre guard, six right digits, and an end guard. A phone pointed
/// at the result reads the number back, which is the only way to know the
/// drawing is right.
abstract final class Ean13 {
  static const List<String> _left = <String>[
    '0001101', '0011001', '0010011', '0111101', '0100011',
    '0110001', '0101111', '0111011', '0110111', '0001011',
  ];

  static const List<String> _g = <String>[
    '0100111', '0110011', '0011011', '0100001', '0011101',
    '0111001', '0000101', '0010001', '0001001', '0010111',
  ];

  static const List<String> _right = <String>[
    '1110010', '1100110', '1101100', '1000010', '1011100',
    '1001110', '1010000', '1000100', '1001000', '1110100',
  ];

  /// Which of the left six digits use the G table, chosen by digit one.
  ///
  /// The first digit is never drawn as bars — it is encoded entirely in this
  /// parity pattern, which is why an EAN-13 fits in the same 95 modules as
  /// the 12-digit code it extends.
  static const List<String> _parity = <String>[
    'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
  ];

  /// The check digit for a 12-digit body, by the weighted mod-10 rule.
  static int checkDigit(String body) {
    var total = 0;
    for (var i = 0; i < body.length; i++) {
      total += (body.codeUnitAt(i) - 48) * (i.isOdd ? 3 : 1);
    }
    return (10 - total % 10) % 10;
  }

  /// Whether a string is a code a scanner would accept.
  static bool isValid(String code) {
    if (code.length != 13) return false;
    for (var i = 0; i < 13; i++) {
      final c = code.codeUnitAt(i);
      if (c < 48 || c > 57) return false;
    }
    return checkDigit(code.substring(0, 12)) == code.codeUnitAt(12) - 48;
  }

  /// The 95 modules, as a string of '0' (space) and '1' (bar).
  ///
  /// Returns null for anything a scanner would reject, because drawing bars
  /// for a bad number produces something that looks scannable and is not.
  static String? modules(String code) {
    if (!isValid(code)) return null;

    final digits = <int>[for (var i = 0; i < 13; i++) code.codeUnitAt(i) - 48];
    final parity = _parity[digits[0]];
    final out = StringBuffer('101');

    for (var i = 0; i < 6; i++) {
      final d = digits[i + 1];
      out.write(parity[i] == 'L' ? _left[d] : _g[d]);
    }
    out.write('01010');
    for (var i = 0; i < 6; i++) {
      out.write(_right[digits[i + 7]]);
    }
    out.write('101');
    return out.toString();
  }
}

/// A barcode, printed the way a pack prints one.
///
/// Every other surface in this product borrows from packaging; this one is
/// the thing itself. It also does real work: on a laptop, where there is no
/// camera to scan with, pointing a phone at this on screen is how the scan
/// flow gets demonstrated at all.
///
/// An invalid code draws no bars. The digits appear on their own with the
/// code struck as unreadable, because a decorative stripe pattern that never
/// scans is a lie told in ink.
class PrintedBarcode extends StatelessWidget {
  const PrintedBarcode({
    super.key,
    required this.code,
    this.height = 56,
    this.showDigits = true,
  });

  final String code;

  /// Height of the bars, before the digits underneath.
  final double height;

  final bool showDigits;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final modules = Ean13.modules(code);

    if (modules == null) {
      return Text(
        '$code — not a readable code',
        style: v360.text.label.copyWith(color: colors.inkMuted),
      );
    }

    // The guard bars run past the digits, as they do on a real pack. The
    // human-readable line sits inside that overhang rather than below it.
    final overhang = showDigits ? 9.0 : 0.0;

    return Semantics(
      label: 'Barcode $code',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            height: height + overhang,
            child: CustomPaint(
              size: Size.infinite,
              painter: _BarsPainter(
                modules: modules,
                ink: colors.ink,
                overhang: overhang,
              ),
            ),
          ),
          if (showDigits)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                // Grouped the way it is printed: the parity digit stands
                // outside the bars it silently encodes.
                '${code[0]}  ${code.substring(1, 7)}  ${code.substring(7)}',
                style: v360.text.label
                    .copyWith(color: colors.ink, letterSpacing: 0.5)
                    .narrow(92),
              ),
            ),
        ],
      ),
    );
  }
}

class _BarsPainter extends CustomPainter {
  const _BarsPainter({
    required this.modules,
    required this.ink,
    required this.overhang,
  });

  final String modules;
  final Color ink;
  final double overhang;

  /// The modules that belong to a guard, which run the full height.
  static bool _isGuard(int i) =>
      i < 3 || (i >= 45 && i < 50) || i >= 92;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width / modules.length;
    final paint = Paint()..color = ink;
    final short = size.height - overhang;

    // Adjacent bars are drawn as one rectangle. Leaving a hairline seam
    // between two black modules is what makes a rendered barcode fail to
    // scan on a low-DPI screen.
    var i = 0;
    while (i < modules.length) {
      if (modules[i] != '1') {
        i++;
        continue;
      }
      final start = i;
      final guard = _isGuard(i);
      while (i < modules.length && modules[i] == '1' && _isGuard(i) == guard) {
        i++;
      }
      canvas.drawRect(
        Rect.fromLTWH(
          start * unit,
          0,
          (i - start) * unit,
          guard ? size.height : short,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_BarsPainter old) =>
      old.modules != modules || old.ink != ink || old.overhang != overhang;
}
